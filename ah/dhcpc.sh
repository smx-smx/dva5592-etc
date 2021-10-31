#!/bin/sh
AH_NAME="Dhcpc"
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_ipcalc.sh
set_delayed=""
add_ntp_servers() {
local ntp_srv="" setm_params_ntp="" idx=1
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=","
for ntp_srv in $1; do
setm_params_ntp="${setm_params_ntp:+$setm_params_ntp	}Device.Time.NTPServer${idx}=${ntp_srv}"
idx=$((idx+1))
done
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
while [ $idx -lt 6 ]; do
setm_params_ntp="${setm_params_ntp:+$setm_params_ntp	}Device.Time.NTPServer${idx}="
idx=$((idx+1))
done
cmclient SETM "$setm_params_ntp"
}
modify_static_routes() {
local action="$1" routelist="$2" defroute="$3" setm_params="" routeEnable
if [ "$action" = "DEL" ]; then
setm_params="Device.Routing.Router.1.IPv4Forwarding.[Interface=$ifp].[StaticRoute=false]"
[ "$defroute" = "nodefault" ] && setm_params="$setm_params.[DestIPAddress!]"
cmclient DEL "$setm_params"
else
cmclient -v routeEnable GETV "$ifp.X_ADB_DHCPOpt121Enable"
local source gateway destinationIpAddr destinationSubnetMask AutoGateway i
for source in $routelist; do
case "$source" in
*/*)
destinationIpAddr="${source%/*}"
help_cidr2mask destinationSubnetMask ${source#*/}
;;
*)
gateway="$source"
cmclient -v AutoGateway GETO Device.Routing.Router.1.IPv4Forwarding.+.[DestIPAddress="$destinationIpAddr"].[DestSubnetMask="$destinationSubnetMask"].[Interface="$ifp"].[StaticRoute=true].[X_ADB_AutoGateway=true]
if [ ${#AutoGateway} -ne 0 ]; then
for AutoGateway in $AutoGateway; do
cmclient SET "$AutoGateway.GatewayIPAddress" "$gateway"
done
else
[ "$action" = "ADD" ] && action='ADDS'
cmclient -v i $action Device.Routing.Router.1.IPv4Forwarding
i="Device.Routing.Router.1.IPv4Forwarding.$i"
[ "$action" = 'ADDS' ] && cmclient SETS "%($i.X_ADB_TR098Reference)" 0
setm_params="${setm_params:+$setm_params	}$i.Interface=$ifp"
setm_params="$setm_params	$i.StaticRoute=false"
setm_params="$setm_params	$i.Origin=DHCPv4"
setm_params="$setm_params	$i.DestIPAddress=$destinationIpAddr"
setm_params="$setm_params	$i.DestSubnetMask=$destinationSubnetMask"
setm_params="$setm_params	$i.GatewayIPAddress=$gateway"
setm_params="$setm_params	$i.Enable=$routeEnable"
if [ ${#setm_params} -ge 10000 ]; then
[ "$routeEnable" = 'false' ] && cmclient -v _ SETEM "$setm_params" || cmclient -v _ SETM "$setm_params"
setm_params=""
fi
fi
;;
esac
done
if [ ${#setm_params} -ne 0 ]; then
[ "$routeEnable" = 'false' ] && cmclient -v _ SETEM "$setm_params" || cmclient -v _ SETM "$setm_params"
fi
fi
}
reset_autogateway()
{
cmclient -v def_route GETO Device.Routing.Router.1.IPv4Forwarding.+.[Interface="$ifp"].[StaticRoute=true].[X_ADB_AutoGateway=true]
for def_route in $def_route; do
cmclient SET "$def_route.GatewayIPAddress" ""
done
}
passthrough_reqopts()
{
local _opt="$1" _tag="$2" _value="$3"
[ -z "$_value" ] && return
cmclient -v passthrough GETV "$_opt".X_ADB_PassthroughEnable
if [ "$passthrough" = "true" ]; then
cmclient -v server_pool GETV "$_opt".X_ADB_PassthroughDHCPServerPool
if [ -n "$server_pool" ]; then
cmclient -v opt_obj GETO "$server_pool.Option.[Tag=$_tag]"
[ -n "$opt_obj" ] && cmclient SET "$opt_obj.Value" "$_value"
fi
fi
}
reset_reqopts() {
local _client="$1"
cmclient SETE "$_client.ReqOption.[Enable=true].Value" ""
}
update_sentopts() {
local _client="$1" _ip="$2" sent_opt=""
cmclient -v sent_opt GETO "${_client}.SentOption.[Enable=true].[Tag=50]"
[ -n "$sent_opt" ] && cmclient -u "DHCPv4Client" SETM "${sent_opt}.Value=$_ip	${sent_opt}.X_ADB_Type=IPAddress"
}
update_reqopts() {
local _client="$1" _defroute="$2" setm_params="" opt tag value
cmclient -v opt GETO "$_client".ReqOption.[Enable=true]
for opt in $opt; do
cmclient -v tag GETV "$opt".Tag
cmclient -v value GETV "$opt".Value
case "$tag" in
"1" )
if [ "$value" != "$subnet" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$subnet"
passthrough_reqopts "$opt" "$tag" "$subnet"
fi
;;
"2" )
if [ "$value" != "$timezone" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$timezone"
passthrough_reqopts "$opt" "$tag" "$timezone"
fi
;;
"3" )
new_value=$(help_tr " " "," "$router")
if [ "$value" != "$new_value" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$new_value"
passthrough_reqopts "$opt" "$tag" "$new_value"
fi
cmclient -v AutoGateway GETO Device.Routing.Router.1.IPv4Forwarding.+.[GatewayIPAddress=].[Interface=$ifp].[StaticRoute=true].[X_ADB_AutoGateway=true]
for obj in $AutoGateway; do
setm_params="${setm_params:+$setm_params	}$obj.GatewayIPAddress=$new_value"
done
;;
"4" )
new_value=$(help_tr " " "," "$timesrv")
if [ "$value" != "$new_value" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$new_value"
passthrough_reqopts "$opt" "$tag" "$new_value"
fi
;;
"5" )
new_value=$(help_tr " " "," "$namesrv")
if [ "$value" != "$new_value" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$new_value"
passthrough_reqopts "$opt" "$tag" "$new_value"
fi
;;
"6" )
new_value=$(help_tr " " "," "$dns")
if [ "$value" != "$new_value" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$new_value"
passthrough_reqopts "$opt" "$tag" "$new_value"
fi
;;
"7" )
new_value=$(help_tr " " "," "$logsrv")
if [ "$value" != "$new_value" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$new_value"
passthrough_reqopts "$opt" "$tag" "$new_value"
fi
;;
"8" )
new_value=$(help_tr " " "," "$cookiesrv")
if [ "$value" != "$new_value" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$new_value"
passthrough_reqopts "$opt" "$tag" "$new_value"
fi
;;
"9" )
new_value=$(help_tr " " "," "$lprsrv")
if [ "$value" != "$new_value" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$new_value"
passthrough_reqopts "$opt" "$tag" "$new_value"
fi
;;
"12" )
if [ "$value" != "$hostname" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$hostname"
passthrough_reqopts "$opt" "$tag" "$hostname"
fi
;;
"13" )
if [ "$value" != "$bootsize" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$bootsize"
passthrough_reqopts "$opt" "$tag" "$bootsize"
fi
;;
"15" )
if [ "$value" != "$domain" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$domain"
passthrough_reqopts "$opt" "$tag" "$domain"
fi
;;
"16" )
if [ "$value" != "$swapsrv" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$swapsrv"
passthrough_reqopts "$opt" "$tag" "$swapsrv"
fi
;;
"17" )
if [ "$value" != "$rootpath" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$rootpath"
passthrough_reqopts "$opt" "$tag" "$rootpath"
fi
;;
"23" )
if [ "$value" != "$ipttl" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$ipttl"
passthrough_reqopts "$opt" "$tag" "$ipttl"
fi
;;
"26" )
if [ "$value" != "$mtu" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$mtu"
passthrough_reqopts "$opt" "$tag" "$mtu"
fi
;;
"28" )
if [ "$value" != "$broadcast" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$broadcast"
passthrough_reqopts "$opt" "$tag" "$broadcast"
fi
;;
"40" )
if [ "$value" != "$nisdomain" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$nisdomain"
passthrough_reqopts "$opt" "$tag" "$nisdomain"
fi
;;
"41" )
new_value=$(help_tr " " "," "$nissrv")
if [ "$value" != "$new_value" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$new_value"
passthrough_reqopts "$opt" "$tag" "$new_value"
fi
;;
"42" )
new_value=$(help_tr " " "," "$ntpsrv")
if [ "$value" != "$new_value" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$new_value"
passthrough_reqopts "$opt" "$tag" "$new_value"
fi
[ ${#new_value} -ne 0 ] && add_ntp_servers $new_value
;;
"43" )
new_value=$(help_tr " " "," "$acsurl")
if [ "$value" != "$new_value" ]; then
cmclient SET -u "DHCPv4Client$opt" "$opt".Value "$new_value"
passthrough_reqopts "$opt" "$tag" "$new_value"
cmclient -v _tmp GETO "$_client".SentOption.*.[Tag=60].[Enable=true].[Value=dslforum.org]
[ -n "$_tmp" ] && cmclient SET Device.ManagementServer.URL "$new_value"
fi
;;
"44" )
new_value=$(help_tr " " "," "$wins")
if [ "$value" != "$new_value" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$new_value"
passthrough_reqopts "$opt" "$tag" "$new_value"
fi
;;
"50" )
if [ "$value" != "$requestip" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$requestip"
passthrough_reqopts "$opt" "$tag" "$requestip"
fi
;;
"51" )
if [ "$value" != "$lease" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$lease"
passthrough_reqopts "$opt" "$tag" "$lease"
fi
;;
"54" )
if [ "$value" != "$serverid" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$serverid"
passthrough_reqopts "$opt" "$tag" "$serverid"
fi
;;
"56" )
if [ "$value" != "$message" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$message"
passthrough_reqopts "$opt" "$tag" "$message"
fi
;;
"58" )
if [ "$value" != "$renewal" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$renewal"
passthrough_reqopts "$opt" "$tag" "$renewal"
fi
;;
"59" )
if [ "$value" != "$rebind" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$rebind"
passthrough_reqopts "$opt" "$tag" "$rebind"
fi
;;
"60" )
if [ "$value" != "$vendorclass" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$vendorclass"
passthrough_reqopts "$opt" "$tag" "$vendorclass"
fi
;;
"61" )
if [ "$value" != "$clientid" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$clientid"
passthrough_reqopts "$opt" "$tag" "$clientid"
fi
;;
"66" )
if [ "$value" != "$tftp" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$tftp"
passthrough_reqopts "$opt" "$tag" "$tftp"
fi
;;
"67" )
if [ "$value" != "$bootfile" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$bootfile"
passthrough_reqopts "$opt" "$tag" "$bootfile"
fi
;;
"77" )
if [ "$value" != "$userclass" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$userclass"
passthrough_reqopts "$opt" "$tag" "$userclass"
fi
;;
"119" )
if [ "$value" != "$search" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$search"
passthrough_reqopts "$opt" "$tag" "$search"
fi
;;
"120" )
if [ "$value" != "$sipsrv" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$sipsrv"
passthrough_reqopts "$opt" "$tag" "$sipsrv"
fi
;;
"121" )
if [ "$value" != "$staticroutes" ]; then
setm_params="${setm_params:+$setm_params	}$opt.Value=$staticroutes"
modify_static_routes DEL "" nodefault
modify_static_routes ADD "$staticroutes" "$_defroute"
passthrough_reqopts "$opt" "$tag" "$staticroutes"
fi
;;
"212" )
if [ "$value" != "$ip6rd" ]; then
set -- $ip6rd
masklen=$1
preflen=$2
prefix=$3
relayIP=$4
cmclient -v rdobj GETO Device.IPv6rd.InterfaceSetting.[TunneledInterface=$ifp]
for rdobj in $rdobj
do
setm_params="${setm_params:+$setm_params	}$rdobj.BorderRelayIPv4Addresses=$relayIP"
setm_params="${setm_params:+$setm_params	}$rdobj.IPv4MaskLength=$masklen"
setm_params="${setm_params:+$setm_params	}$rdobj.SPIPv6Prefix=$prefix/$preflen"
done
fi
;;
esac
done
[ -n "$setm_params" ] && cmclient SETM -u "DHCPv4Client" "$setm_params"
}
custom_settings() {
local _ifp="$1" _ip="$2" _client="$3" _ifname="$4"
}
set_dhcp_status() {
local _status="$1" _client="$2"
[ "$_status" = "Bound" ] && date +%s > /tmp/"$ip"
cmclient SETE "$_client".DHCPStatus "$_status"
}
create_default_route() {
local cmd="$1" i setm_params autogateway ddnsobj
cmclient -v i GETO "Device.Routing.Router.1.IPv4Forwarding.[Interface="$ifp"].[DestIPAddress=]"
if [ ${#i} -eq 0 ]; then
cmclient -v i ADDS "Device.Routing.Router.1.IPv4Forwarding"
i="Device.Routing.Router.1.IPv4Forwarding.$i"
fi
setm_params="$i.Interface=$ifp"
cmclient -v autogateway GETV "$i.X_ADB_AutoGateway"
[ "$autogateway" = "false" ] && setm_params="$setm_params	$i.StaticRoute=false"
setm_params="$setm_params	$i.GatewayIPAddress=$router"
if [ "$cmd" = "true" ]; then
setm_params="$setm_params	$i.Enable=true"
cmclient SETM "$setm_params"
else
cmclient SETEM "$setm_params"
fi
if [ "$cmd" = "no" ]; then
[ ${#table_idx} -ne 0 ] && ip route add default dev $ifname via $router table $table_idx
fi
}
echo "### udhcpc calls dhcpc.sh with parameter <$1>  ###"
client=${pidfile#"/tmp/dhcpc_"}
cmclient -v ifp GETV "$client".Interface
. /etc/ah/helper_serialize.sh && help_serialize "$client"
if [ -n "$ifp" ]; then
help_lowlayer_ifname_get ifname "$ifp"
[ -n "$ifname" ] && table_idx=`get_dev_rule_table $ifp`
fi
if [ "$1" = "deconfig" ]; then
cmclient -v _tmp GETV ${client}.SubnetMask
[ -z "$_tmp" ] && exit 0
set_dhcp_status Init "$client"
setm_params="$client.IPAddress="""
setm_params="$setm_params	$client.SubnetMask="""
setm_params="$setm_params	$client.IPRouters="""
setm_params="$setm_params	$client.DNSServers="""
setm_params="$setm_params	$client.DHCPServer="""
setm_params="$setm_params	$client.Renew=false"
cmclient SETM -u "DHCPv4Client" "$setm_params"
modify_static_routes DEL ""
reset_reqopts "$client"
reset_autogateway
cmclient -v i GETO "$ifp".IPv4Address.[AddressingType=DHCP]
if [ -n "$i" ]; then
cmclient DEL "$i"
fi
[ -f /etc/ah/VoIPNetwork.sh ] && /etc/ah/VoIPNetwork.sh u $ifp &
elif [ "$1" = "bound" ]; then
new_router=`help_tr " " "," "$router"`
new_dns=`help_tr " " "," "$dns"`
cmclient -v i GETO "$ifp".IPv4Address.[AddressingType=DHCP]
if [ -z "$i" ]; then
cmclient -v i_idx ADD "$ifp".IPv4Address
i="$ifp.IPv4Address.$i_idx"
fi
setm_params="$i.IPAddress=$ip"
setm_params="$setm_params	$i.SubnetMask=$subnet"
setm_params="$setm_params	$i.AddressingType=DHCP"
setm_params="$setm_params	$i.Enable=true"
cmclient -v is_default GETV "$ifp.X_ADB_DefaultRoute"
cmclient -v vpnHandled GETO "Device.X_ADB_VPN.Client.PPTP.*.[Interface=$ifp]"
cmclient -v intfHandled GETO "Device.X_ADB_InterfaceMonitor.[Enable=true].Group.[Enable=true].Interface.[MonitoredInterface=$ifp].[Enable=true]"
if [ "$is_default" = "true" ]; then
def_route="true"
elif [ ${#vpnHandled} -ne 0 ]; then
def_route="false"
elif [ ${#intfHandled} -ne 0 ]; then
local defrouteHandled=""
cmclient -v defrouteHandled GETO "$intfHandled.Action.[Path~X_ADB_DefaultRoute]"
[ ${#defrouteHandled} -ne 0 ] && def_route="false" || def_route="no"
else
def_route="no"
fi
[ "$def_route" = "false" ] && create_default_route "$def_route"
cmclient -v route_act_here GETV "$ifp.X_ADB_DHCPOpt121Enable"
if [ "$route_act_here" = 'true' ]; then
cmclient SETM "$setm_params"
update_reqopts "$client" "$new_router"
else
update_reqopts "$client" "$new_router"
cmclient SETM "$setm_params"
fi
setm_params="$client.IPAddress=$ip"
setm_params="$setm_params	$client.SubnetMask=$subnet"
setm_params="$setm_params	$client.IPRouters=$new_router"
setm_params="$setm_params	$client.DNSServers=$new_dns"
setm_params="$setm_params	$client.DHCPServer=$serverid"
setm_params="$setm_params	$client.Renew=false"
cmclient SETM -u "DHCPv4Client" "$setm_params"
[ "$def_route" != "false" ] && create_default_route "$def_route"
custom_settings "$ifp" "$ip" "$client" "$ifname"
update_sentopts "$client" "$ip"
[ -f /etc/ah/VoIPNetwork.sh ] && /etc/ah/VoIPNetwork.sh u $ifp &
set_dhcp_status Bound "$client"
elif [ "$1" = "renew" ] || [ "$1" = "renew_req" ]; then
set_dhcp_status Renewing "$client"
cmclient -v old_ip GETV "$client".IPAddress
cmclient -v old_mask GETV "$client".SubnetMask
cmclient -v old_router GETV "$client".IPRouters
cmclient -v old_dns GETV "$client".DNSServers
cmclient -v old_dhcps GETV "$client".DHCPServer
new_router=`help_tr " " "," "$router"`
new_dns=`help_tr " " "," "$dns"`
if [ "$old_ip" != "$ip" ] \
|| [ "$old_mask" != "$subnet" ] \
|| [ "$old_router" != "$new_router" ] \
|| [ "$old_dns" != "$new_dns" ] \
|| [ "$old_dhcps" != "$serverid" ]
then
cmclient -v i GETO "$ifp".IPv4Address.[AddressingType=DHCP]
if [ -z "$i" ]; then
set_dhcp_status Bound "$client"
exit 0
fi
setm_params="$client.IPAddress=$ip"
setm_params="$setm_params	$client.SubnetMask=$subnet"
setm_params="$setm_params	$client.IPRouters=$new_router"
setm_params="$setm_params	$client.DNSServers=$new_dns"
setm_params="$setm_params	$client.DHCPServer=$serverid"
setm_params="$setm_params	$client.Renew=false"
cmclient SETM -u "DHCPv4Client" "$setm_params"
setm_params="$i.IPAddress=$ip"
setm_params="$setm_params	$i.SubnetMask=$subnet"
setm_params="$setm_params	$i.Enable=true"
cmclient SETM "$setm_params"
cmclient -v is_default GETV "$ifp.X_ADB_DefaultRoute"
cmclient -v vpnHandled GETO "Device.X_ADB_VPN.Client.PPTP.*.[Interface=$ifp]"
cmclient -v intfHandled GETO "Device.X_ADB_InterfaceMonitor.Group.*.Interface.[MonitoredInterface=$ifp].[Enable=true]"
if [ "$is_default" = "true" -o -n "$intfHandled" -o -n "$vpnHandled" ]; then
cmclient -v i GETO Device.Routing.Router.1.IPv4Forwarding.[Interface="$ifp"].[DestIPAddress=]
if [ -z "$i" ]; then
cmclient -v i_idx ADDS Device.Routing.Router.1.IPv4Forwarding
i="Device.Routing.Router.1.IPv4Forwarding.$i_idx"
fi
setm_params="$i.Interface=$ifp"
cmclient -v autogateway GETV $i.X_ADB_AutoGateway
[ "$autogateway" = "false" ] && setm_params="$setm_params	$i.StaticRoute=false"
setm_params="$setm_params	$i.GatewayIPAddress=$router"
setm_params="$setm_params	$i.Origin=DHCPv4"
[ "$is_default" = "true" ] && setm_params="$setm_params	$i.Enable=true"
cmclient SETM "$setm_params"
fi
custom_settings "$ifp" "$ip" "$client" "$ifname"
[ -f /etc/ah/VoIPNetwork.sh  ] && /etc/ah/VoIPNetwork.sh u $ifp &
fi
update_reqopts "$client" "$new_router"
update_sentopts "$client" "$ip"
set_dhcp_status Bound "$client"
elif [ "$1" = "leasefail" ]; then
echo "### udhcpc leasefail  ###"
set_dhcp_status Init "$client"
setm_params="$client.IPAddress="""
setm_params="$setm_params	$client.SubnetMask="""
setm_params="$setm_params	$client.IPRouters="""
setm_params="$setm_params	$client.DNSServers="""
setm_params="$setm_params	$client.DHCPServer="""
setm_params="$setm_params	$client.Renew=false"
cmclient SETM -u "DHCPv4Client" "$setm_params"
reset_reqopts "$client"
reset_autogateway
elif [ "$1" = "nak" ]; then
echo "### udhcpc nak for: <$message>  ###"
fi
exit 0
