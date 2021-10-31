#!/bin/sh
#udp:*,dhcps,*
#sync:max=5,skipcycles
. /etc/ah/helper_serialize.sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
getType() {
local v
if [ -z "$1" -o "$1" = "hex" ]; then
v="Hex"
elif [ "$1" = "string" ]; then
v="String"
elif [ "$1" = "empty" ]; then
v="Empty"
elif [ "$1" = "bool" ]; then
v="Boolean"
elif [ "$1" = "ip" ]; then
v="IPAddress"
elif [ "$1" = "u8" ]; then
v="U8"
elif [ "$1" = "u16" ]; then
v="U16"
elif [ "$1" = "u32" ]; then
v="U32"
elif [ "$1" = "s8" ]; then
v="S8"
elif [ "$1" = "s16" ]; then
v="S16"
elif [ "$1" = "s32" ]; then
v="S32"
fi
eval $2='$v'
}
uptime() {
local u
read u < /proc/uptime
u="${u%%.*}"
eval $1='$u'
}
delete_toolkit_firewall_rules() {
local tk_g_en toolkit_ip_firewall
[ -x /etc/ah/Toolkit.sh ] || return
cmclient -v tk_g_en GETV Device.X_SWISSCOM-COM_DeviceManagement.ToolkitEnable
if [ "$tk_g_en" = "true" ]; then
cmclient -v toolkit_ip_firewall GETV Device.Firewall.Chain.[Alias=DMZTraffic].Rule.[Alias=BlockToolkitPorts].DestIP
[ "$toolkit_ip_firewall" = "$IP_ADDR" ] && cmclient DEL Device.Firewall.Chain.[Alias=DMZTraffic].Rule.[Alias=BlockToolkitPorts]
fi
}
help_serialize "$MAC_ADDR" notrap
if [ "$OP" = "release" ]; then
delete_toolkit_firewall_rules
cmclient -v entry GETO "Device.Hosts.Host.*.[PhysAddress=$MAC_ADDR].[IPAddress=$IP_ADDR].[Active=true]"
if [ -n "$entry" ]; then
cmclient -v entry_manageable_dev GETO "Device.ManagementServer.ManageableDevice.[Host,$entry]"
if [ -n "$entry_manageable_dev" ]; then
cmclient -v manageable_dev_host GETV "$entry_manageable_dev.Host"
manageable_dev_host=$(help_item_replace_uniq_in_list "$manageable_dev_host" "$entry" "")
if [ ${#manageable_dev_host} -eq 0 ]; then
cmclient DEL "$entry_manageable_dev"
else
cmclient SET "$entry_manageable_dev.Host" "$manageable_dev_host"
fi
fi
cmclient -v entry_client GETV $entry.DHCPClient
[ -n "$entry_client" ] && cmclient -v entry_client_ip GETO $entry_client.IPv4Address.[IPAddress=$IP_ADDR]
help_serialize_unlock "$MAC_ADDR" # help_host_disconnect locks on mac
help_host_disconnect "$entry" "$IF_NAME" "$MAC_ADDR" "$IP_ADDR"
[ -n "$entry_client_ip" ] && cmclient SET $entry_client_ip.X_ADB_LeaseTimeRemaining 0
exit 0
fi
help_serialize_unlock "$MAC_ADDR"
exit 0
fi
if [ "$OP" = "delete" ]; then
local entry_host entry_client host_active host_addr_src
delete_toolkit_firewall_rules
cmclient -v entry_host GETO "Device.Hosts.Host.[PhysAddress=$MAC_ADDR]"
cmclient -v entry_client GETO "Device.DHCPv4.Server.Pool.*.Client.[Chaddr=$MAC_ADDR]"
if [ ${#entry_host} -ne 0 ]; then
cmclient -v host_active GETV "$entry_host.Active"
if  [ "$host_active" = "true" ]; then
cmclient -v host_addr_src GETV "$entry_host.DHCPClient"
if [ ${#host_addr_src} -eq 0 ]; then
[ -n "$entry_client" ] && cmclient DEL "$entry_client"
fi
else
[ ${#entry_client} -ne 0 ] && cmclient DEL "$entry_client"
cmclient DEL "$entry_host"
fi
else
[ ${#entry_client} -ne 0 ] && cmclient DEL "$entry_client"
fi
rm /tmp/HostsHost_Lease"$MAC_ADDR"
help_serialize_unlock "$MAC_ADDR"
[ -x /etc/ah/TA_helper_cm.sh ] && . /etc/ah/TA_helper_cm.sh && austria_save || \
cmclient SAVE
exit 0
fi
if [ "$OP" = "no_available_ip_addr" ]; then
logger -t "cm" -p 3 "LAN: DHCP error – too many hosts"
help_serialize_unlock "$MAC_ADDR"
exit 0
fi
ifn=${PORT_NAME:-$IF_NAME}
if [ -z "$ifn" ]; then
help_serialize_unlock "$MAC_ADDR"
exit 0
fi
l1path=`help_obj_from_ifname_get "$ifn"`
if [ -x /etc/ah/Toolkit.sh ]; then
cmclient -v tk_g_en GETV Device.X_SWISSCOM-COM_DeviceManagement.ToolkitEnable
if [ "$tk_g_en" = "true" ]; then
tko="Device.X_SWISSCOM-COM_Toolkit"
cmclient -v tk_opt_12 GETV "$tko.DHCPOpt12"
cmclient -v tk_opt_60 GETV "$tko.DHCPOpt60"
set -f
IFS=';'
set -- $OPTION
unset IFS
set +f
k=0
for arg; do
IFS="," read -r tag type value << EOF
$arg
EOF
value=${value%%	*}
[ "$tag" = "60" ] || continue
case $tk_opt_60 in
*"$value"*)
opt_60_correct=1
;;
esac
done
if [ ${#opt_60_correct} -ne 0 -a "$OPT_12" = "$tk_opt_12" ]; then
cmclient -v tk_enable GETV "$tko.Enable"
if [ "$tk_enable" = "false" ]; then
setm_p="$tko.L1Interface=$l1path"
setm_p="$setm_p	$tko.IPAddress=$IP_ADDR"
cmclient SETM "$setm_p"
fi
fi
unset IFS
fi
fi
if is_wan_intf "$l1path"; then
help_serialize_unlock "$MAC_ADDR"
exit 0
fi
cmclient -v entry GETO Device.Hosts.Host.[PhysAddress="$MAC_ADDR"]
if [ -z "$entry" ]; then
cmclient -v entry ADDIN Device.Hosts.Host
entry="Device.Hosts.Host.$entry"
cmclient -v entry_host_ip ADD $entry.IPv4Address
entry_host_ip="$entry.IPv4Address.$entry_host_ip"
else
cmclient -v old_ipaddr GETV "$entry.IPAddress"
cmclient -v entry_host_ip GETO "$entry.IPv4Address"
if [ -z "$entry_host_ip" ]; then
cmclient -v entry_host_ip ADD $entry.IPv4Address
entry_host_ip="$entry.IPv4Address.$entry_host_ip"
fi
cmclient -v old_identifier GETV "$entry.X_ADB_Identifier"
cmclient -v old_hostname GETV "$entry.HostName"
fi
cmclient -v entry_client GETO $POOL.Client.[Chaddr="$MAC_ADDR"]
if [ -z "$entry_client" ]; then
cmclient -v entry_client ADD ${POOL}.Client
entry_client="$POOL.Client.$entry_client"
cmclient -v entry_client_ip ADD $entry_client.IPv4Address
entry_client_ip="$entry_client.IPv4Address.$entry_client_ip"
setm_params="$entry_client.Chaddr=$MAC_ADDR	"
else
cmclient -v entry_client_ip GETO "$entry_client.IPv4Address"
fi
setm_params="${setm_params}$entry.DHCPClient=$entry_client"
cmclient -v _d_ssid_reference GETO "Device.WiFi.SSID.*.[Name=$ifn]"
cmclient -v assocDevObj GETO "Device.WiFi.AccessPoint.*.[SSIDReference=$_d_ssid_reference].AssociatedDevice.*.[MACAddress=$MAC_ADDR]"
if [ -n "$assocDevObj" ]; then
setm_params="$setm_params	$entry.AssociatedDevice=$assocDevObj"
fi
setm_params="$setm_params	$entry.Layer1Interface=$l1path"
setm_params="$setm_params	$entry.IPAddress=$IP_ADDR"
setm_params="$setm_params	$entry_host_ip.IPAddress=$IP_ADDR"
setm_params="$setm_params	$entry.PhysAddress=$MAC_ADDR"
setm_params="$setm_params	$entry.AddressSource=DHCP"
setm_params="$setm_params	$entry.X_ADB_LastUp=`date -u +%s`"
setm_params="$setm_params	$entry.Active=true"
cmclient -v up GETV "${POOL}.Interface"
[ -n "$up" ] && setm_params="$setm_params	$entry.Layer3Interface=$up"
[ -n "$OPT_12" ] && \
setm_params="$setm_params	$entry.HostName=${OPT_12%%	*}"
setm_params="$setm_params	$entry_client_ip.IPAddress=$IP_ADDR"
[ $EXPIRE_SECONDS -eq -1 ] && ut=-1 || uptime ut
setm_params="$setm_params	$entry_client_ip.X_ADB_LeaseTimeRemaining=$ut"
set -f
IFS=';'
set -- $OPTION
unset IFS
set +f
k=0
for arg; do
IFS="," read -r tag type value << EOF
$arg
EOF
value=${value%%	*}
getType "$type" type
k=$((k + 1))
setm_opt="$entry_client.Option.$k.Tag=$tag	$setm_opt"
setm_opt="$entry_client.Option.$k.X_ADB_Type=$type	$setm_opt"
setm_opt="$entry_client.Option.$k.Value=$value	$setm_opt"
done
cmclient -v entry_option GETO $entry_client.Option.
[ -n "$entry_option" ] && cmclient DEL "$entry_client.Option"
while [ $k -ne 0 ];do
cmclient ADD "$entry_client.Option.$k"
k=$((k - 1))
done
cmclient SETM "$setm_params"
cmclient -v res SETM "$setm_opt"
case "$res" in
*ERROR*)
cmclient DEL "$entry_client.Option"
;;
esac
help_serialize_unlock "$MAC_ADDR"
[ -n "$old_ipaddr" -a "$old_ipaddr" != "$IP_ADDR" ] && \
ip neigh del "$old_ipaddr" dev "$IF_NAME"
if [ -n "$OPT_125" ]; then
str_cut enterprise_num $OPT_125 1 8
str_cut data_len $OPT_125 9 10
data_len=$((0x$data_len))
i=0
last_b=10
while [ $i -lt 3 ]; do
first_data_b=$((last_b + 1))
last_b=$((last_b + 2))
str_cut subcode $OPT_125 $first_data_b $last_b
subcode=$((0x$subcode))
first_data_b=$((last_b + 1))
last_b=$((last_b + 2))
str_cut sublen $OPT_125 $first_data_b $last_b
sublen=$((0x$sublen))
sublen=$((2 * $sublen))
first_data_b=$((last_b + 1))
last_b=$((last_b + $sublen))
str_cut subdata $OPT_125 $first_data_b $last_b
if [ -n "$subdata" ]; then
data=""
for b in `echo $subdata | sed "s/../& /g"`; do
[ "$b" = "09" ] && break
data=$data`printf "\x$b"`
done
case "$i" in
"0") manufacturerOUI="$data"
;;
"1") serialNum="$data"
;;
"2") productClass="$data"
;;
esac
fi
i=$((i + 1))
done
if [ -n "$manufacturerOUI" -a -n "$serialNum" -a -n "$productClass" ]; then
cmclient -v manageableDevice GETO Device.ManagementServer.ManageableDevice.*.[ManufacturerOUI="$manufacturerOUI"].[SerialNumber="$serialNum"].[ProductClass="$productClass"]
if [ -n "$manageableDevice" ]; then
cmclient -v list GETV "$manageableDevice".Host
if [ -z "$list" ]; then
cmclient SET "$manageableDevice".Host "$entry"
[ -x /etc/ah/TA_helper_cm.sh ] && . /etc/ah/TA_helper_cm.sh && austria_save || \
(. /etc/ah/helper_cm.sh && help_cm_save now weak)
exit 0
fi
found=""
IFS=","
for h in $list; do
if [ "$h" = "$entry" ]; then
found=1
break
fi
done
unset IFS
[ -z "$found" ] && cmclient SET "$manageableDevice".Host "$list","$entry"
[ -x /etc/ah/TA_helper_cm.sh ] && . /etc/ah/TA_helper_cm.sh && austria_save || \
(. /etc/ah/helper_cm.sh && help_cm_save now weak)
exit 0
fi
cmclient -v idx ADDIN Device.ManagementServer.ManageableDevice.
managObj="Device.ManagementServer.ManageableDevice.$idx"
setm_man_params="$managObj.ManufacturerOUI=$manufacturerOUI"
setm_man_params="$setm_man_params	$managObj.SerialNumber=$serialNum"
setm_man_params="$setm_man_params	$managObj.ProductClass=$productClass"
setm_man_params="$setm_man_params	$managObj.Host=$entry"
setm_man_params="$setm_man_params	$managObj.Alias=Device$idx"
cmclient SETM "$setm_man_params"
fi
fi
[ -x /etc/ah/TA_helper_cm.sh ] && . /etc/ah/TA_helper_cm.sh && austria_save || \
(. /etc/ah/helper_cm.sh && help_cm_save now weak)
exit 0
