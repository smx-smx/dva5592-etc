#!/bin/sh
AH_NAME="noUpdate"
[ "$user" = "${AH_NAME}" ] && exit 0
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
[ "$op" = "g" ] && . /etc/ah/helper_serialize.sh && help_serialize "X_ADB_ParentalControl.DefaultPolicy" > /dev/null
dns_port="53"
dns_proxy_port="3128"
http_port="80"
https_port="443"
http_proxy_port="3129"
gui_url="/ui/cbpc/request_pin"
ip_ag=""
cmclient -v interfaces GETO Device.IP.Interface.[Enable=true].[X_ADB_Upstream=false]
for i in $interfaces; do
help_lowlayer_ifname_get ifname "$i"
cmclient -v ips GETV "${i}".IPv4Address.[Enable=true].IPAddress
for ips in $ips; do
ip_ag="$ips"
break
done
if [ ${#ip_ag} -ne 0 ]; then
break
fi
done
get_provider_categories(){
local all_cate_prov virg x item id cate_provider
all_cate_prov=""
virg=""
set -f
IFS=","
set -- $1
unset IFS
set +f
for x; do
cmclient -v item GETO "${ServiceProvObj}.ContentCategory.**.[Name=${x}]."
id=${item##*.}
cmclient -v cate_provider GETV "${ServiceProvObj}.ContentCategory.${id}.ProviderIdentifiers"
if [ "$all_cate_prov" != "" ]; then
virg=","
fi
all_cate_prov="${all_cate_prov}${virg}${cate_provider}"
done
echo "${all_cate_prov}"
}
create_yaps_cbpc_conf () {
echo "Request_pin_page \"${ip_ag}/ui/cbpc/request_pin\""
echo "Filtered_page      \"${ip_ag}/ui/cbpc/filtered\""
echo "Error_message_page \"${ip_ag}/ui/cbpc/error_message\""
echo "Local_dns_server \"${ip_ag}\""
echo "Port_local_dns_server ${dns_port}"
echo "Dns_proxy_port ${dns_proxy_port}"
echo "Port_local_http_server ${http_port}"
echo "Port_local_https_server ${https_port}"
echo "Http_proxy_port ${http_proxy_port}"
echo "Local_gui_to_request_pin \"${ip_ag}\""
echo "Parental_control_policy \"/tmp/cbpc/parental_control_policy.conf\""
echo "Policy_path \"/tmp/cbpc/policy.bin\""
echo "Policy_device_association \"/tmp/cbpc/policy_device_association.conf\""
echo "devmac_path \"/tmp/cbpc/device.bin\""
echo "Url_cache  \"/tmp/cbpc/url_cache\""
echo "Filter \"/tmp/cbpc/filter\""
echo "UrlCache_Buckets 100"
cmclient -v item GETV "X_ADB_ParentalControl.UrlCacheHousekeepingPeriod"
echo "Url_cache_hk_period ${item}"
cmclient -v item GETV "Device.X_ADB_ParentalControl.CurrentProvider"
if [ -z $item ]; then
echo "currentprovider \"Local\""
else
cmclient -v item GETV ${item}.Name
echo "currentprovider \"${item}\""
fi
cmclient -v name GETV "X_ADB_ParentalControl.ServiceProvider.*.Name"
for name in $name ; do
case "$name" in
BluePrintData)
cmclient -v item GETV "Device.X_ADB_ParentalControl.ServiceProvider.1.Username"
echo "Blueprintdata_user ${item}"
cmclient -v item GETV "Device.X_ADB_ParentalControl.ServiceProvider.1.Password"
echo "Blueprintdata_passw ${item}"
cmclient -v item GETV "Device.X_ADB_ParentalControl.ServiceProvider.1.QueryType"
echo "Blueprintdata_type ${item}"
cmclient -v item GETV "Device.X_ADB_ParentalControl.ServiceProvider.1.Url"
echo "BPD_endpoint \"${item}\""
;;
SurfRight)
cmclient -v item GETV "Device.X_ADB_ParentalControl.ServiceProvider.2.Url"
a=${item##*:}
echo "surfright_port $a"
b=${item%:*$a}
g=${b##*udp://}
echo "surfright_host \"$g\""
cmclient -v item GETV "Device.X_ADB_FactoryData.BaseMACAddress"
echo "surfright_router_mac \"${item}\""
;;
esac
done
cmclient -v item GETV "X_ADB_ParentalControl.PolicyOverrideHousekeepingPeriod"
echo "policy_override_hk_period ${item}"
cmclient -v item GETV "Device.X_ADB_ParentalControl.AdminPIN"
echo "admin_pin \"${item}\""
cmclient -v item1 GETV "X_ADB_ParentalControl.DefaultPolicy"
cmclient -v item GETV "$item1.PolicyID"
echo "default_policy \"${item}\""
}
create_parental_control () {
local _pol objid item ServiceProvObj pp
cmclient -v pp GETO "X_ADB_ParentalControl.Policy"
for _pol in $pp; do
objid=${_pol##*.}
echo "#[Policy Name]"
cmclient -v item GETV "X_ADB_ParentalControl.Policy.${objid}.PolicyID"
echo "${item}"
cmclient -v ServiceProvObj GETV "Device.X_ADB_ParentalControl.CurrentProvider"
echo "#[Categories Allowed]"
if [ -n "$ServiceProvObj" ]; then
cmclient -v item GETV "X_ADB_ParentalControl.Policy.${objid}.AllowedCategories"
get_provider_categories $item
else
echo " "
fi
echo "#[Categories Blocked]"
if [ -n "$ServiceProvObj" ]; then
cmclient -v item GETV "X_ADB_ParentalControl.Policy.${objid}.BlockedCategories"
get_provider_categories $item
else
echo " "
fi
echo "#[Url Blocked]"
cmclient -v item GETV "X_ADB_ParentalControl.Policy.${objid}.BlockedUrls"
echo "${item}"
echo "#[Url Allowed]"
cmclient -v item GETV "X_ADB_ParentalControl.Policy.${objid}.AllowedUrls"
echo "${item}"
echo "#[Policy Pin]"
cmclient -v item GETV "X_ADB_ParentalControl.Policy.${objid}.PolicyPIN"
echo "${item}"
echo "#[Action on url lookupfail]"
cmclient -v item GETV "X_ADB_ParentalControl.Policy.${objid}.ActionOnUrlLookupFail"
echo "${item}"
echo " "
done
}
create_policy_device_assoc () {
local _dev objid item pol_name ppa
cmclient -v ppa GETO "X_ADB_ParentalControl.PolicyDeviceAssociation"
for _dev in $ppa
do
objid=${_dev##*.}
echo "#[MAC address]"
cmclient -v item GETV "X_ADB_ParentalControl.PolicyDeviceAssociation.${objid}.MacAddress"
echo "${item}"
echo "#[Pre-assigned ID]"
cmclient -v item GETV "X_ADB_ParentalControl.PolicyDeviceAssociation.${objid}.PreAssignedPolicy"
cmclient -v pol_name GETV "${item}.PolicyID"
echo "${pol_name}"
echo "#[Allow Policy Override]"
cmclient -v item GETV "X_ADB_ParentalControl.PolicyDeviceAssociation.${objid}.AllowPolicyOverride"
[ "$item" = "true" ] && item="yes" || item="no"
echo "${item}"
echo " "
done
}
create_filter () {
local _url objid item pu
cmclient -v pu GETO "X_ADB_ParentalControl.UrlFilter"
for _url in $pu
do
objid=${_url##*.}
cmclient -v item GETV "X_ADB_ParentalControl.UrlFilter.${objid}.Url"
echo "$objid ${item}"
done
}
conf_files () {
local objid _pol _dev _url item pol_name
rm /tmp/cbpc/yaps-cbpc.conf
create_yaps_cbpc_conf > /tmp/cbpc/yaps-cbpc.conf
rm /tmp/cbpc/parental_control_policy.conf
create_parental_control > /tmp/cbpc/parental_control_policy.conf
rm /tmp/cbpc/policy_device_association.conf
create_policy_device_assoc > /tmp/cbpc/policy_device_association.conf
rm /tmp/cbpc/filter
create_filter > /tmp/cbpc/filter
}
Populate_RestrictedHost() {
local action DefaultPolicy mode host act mac_host PDevice set_p \
Device_policy ip_host tod_enable tod_profile tod_profile_id RHentry
action=$1
cmclient -v DefaultPolicy GETV Device.X_ADB_ParentalControl.DefaultPolicy
cmclient -v mode GETV "Device.X_ADB_ParentalControl.Mode"
cmclient -v host GETO "Device.Hosts.Host"
for host in $host; do
cmclient -v act GETV $host.Active
if [ "$act" = "true" ]; then
cmclient -v mac_host GETV $host.PhysAddress
cmclient -v ip_host GETV $host.IPAddress
cmclient -v PDevice GETO "Device.X_ADB_ParentalControl.PolicyDeviceAssociation.*.[MacAddress=$mac_host]"
cmclient -v RHentry GETO "Device.X_ADB_ParentalControl.RestrictedHosts.Host.*.[MACAddress=$mac_host]"
if [ "$action" = "ADD" ]; then
if [ -z "$PDevice" ]; then
cmclient -v PDevice ADD "Device.X_ADB_ParentalControl.PolicyDeviceAssociation."
set_p="Device.X_ADB_ParentalControl.PolicyDeviceAssociation.$PDevice.MacAddress=$mac_host"
set_p="$set_p	Device.X_ADB_ParentalControl.PolicyDeviceAssociation.$PDevice.PreAssignedPolicy=$DefaultPolicy"
if [ "$mode" = "Advanced" ]; then
set_p="$set_p	Device.X_ADB_ParentalControl.PolicyDeviceAssociation.$PDevice.AllowPolicyOverride=true"
else
set_p="$set_p	Device.X_ADB_ParentalControl.PolicyDeviceAssociation.$PDevice.AllowPolicyOverride=false"
fi
cmclient SETM "$set_p" > /dev/null
fi
if [ -z "$RHentry" ]; then
cmclient -v tod_enable GETV $DefaultPolicy.TimeOfDayEnable
cmclient -v tod_profile GETV $DefaultPolicy.TimeOfDayProfile
tod_profile_id=${tod_profile##*.}
cmclient -v RHentry ADD "Device.X_ADB_ParentalControl.RestrictedHosts.Host."
set_p="Device.X_ADB_ParentalControl.RestrictedHosts.Host.$RHentry.MACAddress=$mac_host"
set_p="$set_p	Device.X_ADB_ParentalControl.RestrictedHosts.Host.$RHentry.Blocked=false"
set_p="$set_p	Device.X_ADB_ParentalControl.RestrictedHosts.Host.$RHentry.TypeOfRestriction=TIMEOFDAY"
set_p="$set_p	Device.X_ADB_ParentalControl.RestrictedHosts.Host.$RHentry.Enable=$tod_enable"
cmclient SETM "$set_p" > /dev/null
cmclient SET -u "RestrictedHostEntry" Device.X_ADB_ParentalControl.RestrictedHosts.Host.$RHentry.Profile $tod_profile_id
fi
fi
if [ "$action" = "SET" ]; then
Device_policy=`cbpc-cli GET $ip_host`
cmclient -v PDevice GETO "Device.X_ADB_ParentalControl.Policy.*.[PolicyID=$Device_policy]"
cmclient -v tod_enable GETV "$PDevice.TimeOfDayEnable"
cmclient -v tod_profile GETV "$PDevice.TimeOfDayProfile"
tod_profile_id=${tod_profile##*.}
if [ -n "$RHentry" ]; then
if [ -n "$PDevice" ]; then
cmclient SET $RHentry.Profile $tod_profile_id
cmclient SET $RHentry.Enable $tod_enable
cmclient SET X_ADB_ParentalControl.RestrictedHosts.Check true
fi
fi
fi
fi
done
}
refresh_rules() {
rm /tmp/cbpc/cbpc_iptables_rules
help_iptables_no_cache -t mangle -F CbpcRedirect
help_iptables_no_cache -t nat -F CbpcRedirect
help_iptables_no_cache -t nat -I CbpcRedirect -p tcp --dport "$dns_port" -j REDIRECT --to-ports "$dns_proxy_port"
help_iptables_no_cache -t nat -I CbpcRedirect -p udp --dport "$dns_port" -j REDIRECT --to-ports "$dns_proxy_port"
help_iptables commit
unset tmpiptablesprefix
create_iprule
restart_service
}
create_rules_for_IP () {
local ips
HTTP_PATH_FILE="/tmp/l7-protocols"
HTTP_FILE="http.pat"
HTTP_10_FILE="http_10.pat"
HTTP_10_PROTO="http_10"
PATTERN_HTTP10='Host: ([0-9])?([0-9])?[0-9]\.([0-9])?([0-9])?[0-9]\.([0-9])?([0-9])?[0-9]\.([0-9])?([0-9])?[0-9]'
DIR_HTTP10="httpversion_10"
ERROR_VALUE="ERROR"
mkdir -p "$HTTP_PATH_FILE" 2> /dev/null
help_iptables_no_cache -t mangle -I PC -i lo -j RETURN
cmclient -v ips GETV "Device.IP.Interface.IPv4Address.**.[Enable=true].IPAddress"
for ips in $ips
do
help_iptables_no_cache -t mangle -A PC -d "$ips" -j RETURN
done
help_iptables_no_cache -t mangle -I PC -j CbpcRedirect
mkdir -p "$HTTP_PATH_FILE/$DIR_HTTP10"
echo "$HTTP_10_PROTO" > "$HTTP_PATH_FILE/$DIR_HTTP10/$HTTP_10_FILE"
echo -n "$PATTERN_HTTP10" >> "$HTTP_PATH_FILE/$DIR_HTTP10/$HTTP_10_FILE"
help_iptables_no_cache -t mangle -A PC -m layer7 --l7dir "$HTTP_PATH_FILE/$DIR_HTTP10" --l7proto "$HTTP_10_PROTO" -p tcp --dport "$http_port" -j TPROXY --on-port "$http_proxy_port" --tproxy-mark 0xffff --on-ip "$ip_ag"
help_iptables_no_cache -t mangle -A PC -p tcp --dport "$http_port" -m connbytes --connbytes 1:3 --connbytes-dir both --connbytes-mode packets -j SKIPFC
help_iptables_no_cache -t mangle -A PC -p tcp --dport "$http_port" -m connbytes --connbytes 1:3 --connbytes-dir both --connbytes-mode packets -j RETURN
}
delete_rules_for_IP () {
rm -rf "$HTTP_PATH_FILE"
help_iptables_no_cache -t mangle -F PC_HTTP10
help_iptables_no_cache -t mangle -F PC_HTTP11
help_iptables_no_cache -t mangle -F PC_HTTPS
}
service_enable () {
local _count if _ifs="" dhh host act mac
echo "ENABLE service $obj --->" >/dev/console
if [ -x "/etc/ah/RestrictedHost.sh" ]; then
Populate_RestrictedHost ADD
/etc/ah/RestrictedHost.sh enable
else
help_iptables_no_cache -t mangle -F RO
cmclient -v dhh GETO "Device.Hosts.Host"
for host in $dhh
do
cmclient -v act GETV $host.Active
if [ "$act" = "true" ]; then
cmclient -v mac GETV $host.PhysAddress
help_iptables -t mangle -A RO -m mac --mac-source "$mac" -j PC
fi
done
fi
mkdir /tmp/cbpc
conf_files
_count=0
echo "" >/tmp/cbpc/policy.bin
echo "" >/tmp/cbpc/device.bin
echo "" >/tmp/cbpc/cbpc_iptables_rules
/sbin/cbpc-dnsp > /dev/null &
cmclient -v if GETV "Device.IP.Interface.**.[X_ADB_Upstream=false].[Enable=true].IPv4Address.**.IPAddress"
for if in $if
do
_ifs="$_ifs $if"
_count=$((_count+1))
done
/sbin/cbpc-tproxyd $http_port $http_proxy_port $_count $_ifs $gui_url > /dev/null &
/sbin/cbpc-sslproxy -s $ip_ag:3130 -c $ip_ag$gui_url -m 32 -U 2048 > /dev/null &
help_iptables_no_cache -t mangle -F PC
ip rule add fwmark 0xffff lookup 100
ip route add local 0.0.0.0/0 dev lo table 100
create_rules_for_IP
help_iptables_no_cache -t mangle -I PC -j PC_HTTP11
refresh_rules
}
service_disable () {
echo "DISABLE service $obj --->" >/dev/console
killall cbpc-dnsp > /dev/null
killall cbpc-tproxyd > /dev/null
killall cbpc-sslproxy >/dev/null
help_iptables_no_cache -t nat -F CbpcRedirect
rm /tmp/cbpc/parental_control_policy.conf
rm /tmp/cbpc/policy_device_association.conf
rm /tmp/cbpc/filter
rm /tmp/cbpc/policy.bin
rm /tmp/cbpc/device.bin
rm /tmp/cbpc/cbpc_iptables_rules
help_iptables_no_cache -t mangle -F PC_HTTP11
help_iptables_no_cache -t mangle -D PC -j PC_HTTP11
help_iptables_no_cache -t mangle -D PC -j CbpcRedirect
help_iptables_no_cache -t mangle -F CbpcRedirect
help_iptables_no_cache -t mangle -F PC
ip rule del fwmark 0xffff lookup 100
ip route del local 0.0.0.0/0 dev lo table 100
delete_rules_for_IP
if [ -x "/etc/ah/RestrictedHost.sh" ]; then
/etc/ah/RestrictedHost.sh disable
else
help_iptables_no_cache -t mangle -F RO
fi
}
restart_service () {
local _count if _ifs=""
echo "RESTART service $obj --->" >/dev/console
killall cbpc-dnsp > /dev/null
killall cbpc-tproxyd > /dev/null
killall cbpc-sslproxy > /dev/null
rm /tmp/cbpc/parental_control_policy.conf
rm /tmp/cbpc/policy_device_association.conf
rm /tmp/cbpc/filter
rm /tmp/cbpc/policy.bin
rm /tmp/cbpc/device.bin
conf_files
_count=0
echo "" >/tmp/cbpc/policy.bin
echo "" >/tmp/cbpc/device.bin
/sbin/cbpc-dnsp > /dev/null &
cmclient -v if GETV "Device.IP.Interface.**.[X_ADB_Upstream=false].[Enable=true].IPv4Address.**.IPAddress"
for if in $if
do
_ifs="$_ifs $if"
_count=$((_count+1))
done
/sbin/cbpc-tproxyd $http_port $http_proxy_port $_count $_ifs $gui_url > /dev/null &
/sbin/cbpc-sslproxy -s $ip_ag:3130 -c $ip_ag$gui_url -m 32 -U 2048 > /dev/null &
if [ -x "/etc/ah/RestrictedHost.sh" ]; then
Populate_RestrictedHost SET
/etc/ah/RestrictedHost.sh disable
/etc/ah/RestrictedHost.sh enable
fi
}
test_Mode_changed () {
local mode DefaultPolicy set_p host ppd ppa
if [ "$setMode" = "1" ]; then
if [ -x "/etc/ah/RestrictedHost.sh" ]; then
/etc/ah/RestrictedHost.sh disable
/etc/ah/RestrictedHost.sh enable
fi
cmclient -v mode GETV "Device.X_ADB_ParentalControl.Mode"
if [ "$mode" = "Advanced" -a "$oldMode" != "Advanced" ]; then
cmclient -v DefaultPolicy GETO "Device.X_ADB_ParentalControl.Policy.*.[PolicyID=Low]"
set_p="Device.X_ADB_ParentalControl.DefaultPolicy=$DefaultPolicy"
cmclient -v ppd GETO "Device.X_ADB_ParentalControl.PolicyDeviceAssociation"
for host in $ppd
do
set_p="$set_p	$host.PreAssignedPolicy=$DefaultPolicy"
set_p="$set_p	$host.AllowPolicyOverride=true"
done
cmclient SETM -u "noUpdate" "$set_p" > /dev/null
fi
if [ "$mode" = "Low" ] || [ "$mode" = "Medium" ] || [ "$mode" = "High" ]; then
cmclient -v DefaultPolicy GETO "Device.X_ADB_ParentalControl.Policy.*.[PolicyID=$mode]"
set_p="Device.X_ADB_ParentalControl.DefaultPolicy=$DefaultPolicy"
cmclient -v ppa GETO "Device.X_ADB_ParentalControl.PolicyDeviceAssociation"
for host in $ppa
do
set_p="$set_p	$host.PreAssignedPolicy=$DefaultPolicy"
set_p="$set_p	$host.AllowPolicyOverride=false"
done
cmclient SETM -u "noUpdate" "$set_p" > /dev/null
fi
if [ "$changedEnable" = "0" ]; then
restart_service
fi
fi
}
create_iprule () {
local url_objid url _ips _x _host act mac_host ip_host dhh puu
local url_profiles_blocked profile_blocked profile_id
cmclient -v puu GETO "Device.X_ADB_ParentalControl.UrlFilter"
for _type in $puu
do
url_objid=${_type##*.}
cmclient -v url GETV "Device.X_ADB_ParentalControl.UrlFilter.${url_objid}.Url"
cmclient -v url_profiles_blocked GETO Device.X_ADB_ParentalControl.Policy.[BlockedUrls,$url_objid]
_ips=`nslookup -t 1 $url |awk '/Address / {len=split($0,a," ");if(len>=3)print(a[3]);}'`
set -f
IFS="
"
set -- $_ips
unset IFS
set +f
for _x; do
if [ "$_x" = "0.0.0.0" ]; then
continue
elif ! help_is_valid_ip "$_x" = "255" ; then
continue
else
cmclient -v dhh GETO "Device.Hosts.Host"
for _host in $dhh
do
cmclient -v act GETV $_host.Active
if [ "$act" = "true" ]; then
cmclient -v mac_host GETV $_host.PhysAddress
cmclient -v ip_host GETV $_host.IPAddress
cmclient -v profile_id GETV Device.X_ADB_ParentalControl.PolicyDeviceAssociation.[MacAddress=$mac_host].CurrentPolicy
[ -z "$profile_id" ] && cmclient -v profile_id GETV Device.X_ADB_ParentalControl.PolicyDeviceAssociation.[MacAddress=$mac_host].PreAssignedPolicy
[ -z "$profile_id" ] && cmclient -v profile_id GETV Device.X_ADB_ParentalControl.PolicyDeviceAssociation.[MacAddress=00:00:00:00:00:00].PreAssignedPolicy
for profile_blocked in $url_profiles_blocked; do
if [ "$profile_id" = "$profile_blocked" ]; then
cbpc-cli IPA $_x $url $mac_host $ip_host
break
fi
done
fi
done
fi
done
done
}
test_config_changed () {
local mode DefaultPolicy set_p
test_Mode_changed
cmclient -v Eobj GETV Device.X_ADB_ParentalControl.Enable
if [ "$Eobj" = "true" ]; then
if [ -x "/etc/ah/RestrictedHost.sh" ]; then
if [ "$setTimeOfDayEnable" = "1" ]; then
Populate_RestrictedHost SET
/etc/ah/RestrictedHost.sh disable
/etc/ah/RestrictedHost.sh enable
fi
fi
if [ "$setUrlFilterRefresh" = "1" ]; then
refresh_rules
fi
if [ "$changedBlockedUrls" = "1" -o "$changedAllowedUrls" = "1" -o "$changedAllowedCategories" = "1" -o "$changedBlockedCategories" = "1" ]; then
restart_service
else
if [ "$changedPolicyID" = "1" -o "$changedPolicyPIN" = "1" -o "$changedMode" = "1" ]; then
restart_service
fi
if [ "$changedPreAssignedPolicy" = "1" -o "$changedAllowPolicyOverride" = "1" ]; then
restart_service
fi
fi
if [ "$changedDefaultPolicy" = "1" ]; then
			cmclient -v mode GETV Device.X_ADB_ParentalControl.Mode
cmclient -v DefaultPolicy GETV Device.X_ADB_ParentalControl.DefaultPolicy
set_p="X_ADB_ParentalControl.PolicyDeviceAssociation.1.PreAssignedPolicy=$DefaultPolicy"
if [ "$mode" = "Advanced" ]; then
set_p="$set_p	Device.X_ADB_ParentalControl.PolicyDeviceAssociation.1.AllowPolicyOverride=true"
else
set_p="$set_p	Device.X_ADB_ParentalControl.PolicyDeviceAssociation.1.AllowPolicyOverride=false"
fi
cmclient SETM "$set_p" > /dev/null
fi
if [ "$changedCurrentProvider" = "1" ]; then
prov_id="${newCurrentProvider##*Device.X_ADB_ParentalControl.ServiceProvider.}"
cmclient -v prov GETO $newCurrentProvider
if [ -n "$prov" -a "$prov_id" -gt "0" ] || [ -z "$newCurrentProvider" ]; then
service_disable
				if [ -z "$newCurrentProvider" ]; then
cmclient -u "noUpdate" SET "Device.X_ADB_ParentalControl.Mode" Advanced
fi
service_enable
else
exit 7
fi
fi
cmclient -v item GETV "Device.X_ADB_ParentalControl.CurrentProvider"
license_stat=`license-cli USELIB-S 6`
if [ "$license_stat" != "Valid" -a "$license_stat" != "Grace" -a "$license_stat" != "NearlyExpired" ] || [ -z $item ]; then
if [ "$changedActionOnUrlLookupFail" = "1" ]; then
restart_service
fi
fi
if [ "$changedPolicyOverrideHousekeepingPeriod" = "1" -o "$changedUrlCacheHousekeepingPeriod" = "1" ]; then
restart_service
else
if [ "$setPolicyOverrideHousekeepingPeriod" = "1" ]; then
restart_service
fi
fi
if [ "$changedEnable" = "0" -a "$newEnable" = "true" -a "$oldEnable" = "true" -a "$setEnable" = "1" ]; then
service_enable
fi
fi
}
set_conf () {
if [ "$changedEnable" = "1" ]; then
test_Mode_changed
if [ "$newEnable" = "true" ]; then
service_enable
else
service_disable
fi
else
test_config_changed
fi
}
case "$op" in
s)
set_conf "$1"
;;
d)
o="${obj##*Device.X_ADB_ParentalControl.Policy.}"
id_obj="${obj##*.}"
if [ "$o" -eq "$id_obj" ]; then
if [ "$o" -lt "5" ]; then
echo "ERROR ------- was a Read Only Policy" >/dev/console
return $ERR
fi
fi
;;
esac
exit 0
