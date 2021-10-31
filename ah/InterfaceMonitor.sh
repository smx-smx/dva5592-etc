#!/bin/sh
AH_NAME="InterfaceMonitor"
[ "$user" = "${AH_NAME}" ] && exit 0
[ "$user" = "boot" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
MAX_PRIORITY=0
ip_status=""
dns_test() {
local ip="$1" gw="$2" host="$3" timer="$4" intObj="$5" dnsTimer="$6" objs p
cmclient -v objs GETV "Device.DNS.Client.Server.[Enable=true].[Interface=$ip].[DNSServer!].DNSServer"
for dns in $objs; do
route add "$dns" gw "$gw"
cmclient -v dsnId ADD "Device.DNS.Diagnostics.X_ADB_NSLookup"
dnsObj="Device.DNS.Diagnostics.X_ADB_NSLookup.${dsnId}"
p="$dnsObj.HostName=$hostName	$dnsObj.Timeout=$timer	$dnsObj.Alias=$intObj"
p="${p}	$dnsObj.NumberOfRepetitions=1	$dnsObj.DNSServer=$dns"
p="${p}	$dnsObj.WaitResults=true	$dnsObj.DiagnosticsState=Requested"
cmclient SETM "${p}"
cmclient -v result GETV "$dnsObj.Result.1.Status"
cmclient DEL "$dnsObj"
route del "$dns" gw "$gw"
[ "$result" = "Success" ] && return 0
done
timer=$((timer*2))
if [ $timer -lt $dnsTimer ]; then
dns_test "$ip" "$gw" "$host" "$timer" "$intObj" "$dnsTimer"
else
return 1
fi
}
dns_cleaning() {
local intObj="$1" monObj="$2" self="$3" objs gw dns
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${intObj}_DNSTimer]"
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${intObj}_DNSRetest]"
if [ -e /tmp/InterfaceMonitor_DNS_${intObj}.pid ]; then
for pid in `cat /tmp/InterfaceMonitor_DNS_${intObj}.pid`; do
[ ${#self} -ne 0 -a "$pid" = "$self" ] && continue
pkill -P $pid; kill $pid
done
rm -f /tmp/InterfaceMonitor_DNS_${intObj}.pid
fi
cmclient -v objs GETO "Device.DNS.Diagnostics.X_ADB_NSLookup.[Alias=$intObj]"
[ ${#objs} -ne 0 ] && cmclient -v gw GETV "Device.Routing.Router.*.IPv4Forwarding.[Interface=$monObj].[DestIPAddress=].GatewayIPAddress"
for objs in $objs; do
cmclient -v dns GETV "$objs.DNSServer"
cmclient DEL "$objs"
[ ${#gw} -ne 0 ] && route del "$dns" gw "$gw"
done
}
check_up_condition() {
local intObj="$1" mode="$2" monObj="$3" status="" ip_address="" is_enabled="" \
dnsTimer="" dnsBackoff="" hostName="" ip_obj="" gw="" startTimeout="" dnsRetest=""
case "$mode" in
"LINK")
cmclient -v status GETV "$monObj.Status"
[ "$status" = "Up" ] &&	return 0 || return 1
;;
"IP")
cmclient -v ip_status GETV "${monObj%.IPv4Address*}.Status"
cmclient -v ip_address GETV "$monObj.IPAddress"
cmclient -v is_enabled GETV "$monObj.Enable"
[ ${#ip_address} -ne 0 -a "$is_enabled" = "true" -a "$ip_status" = "Up" ] && return 0 || return 1
;;
"ARP")
cmclient SETE "$intObj.ARP.[TimerExpired=true].TimerExpired" "false"
cmclient -v is_enabled GETV "$monObj.Enable"
[ "$is_enabled" = "true" ] && cmclient -v ip_status GETV "${monObj%.IPv4Address*}.Status"
[ "$ip_status" = "Up" ] && cmclient -v ip_address GETV "$monObj.IPAddress"
[ ${#ip_address} -ne 0 ] && cmclient -u "${AH_NAME}" SET "$intObj.ARP.DiagnosticsState" "Request" || cmclient -u "${AH_NAME}" SET "$intObj.ARP.DiagnosticsState" "None"
;;
"DNS")
ip_obj="${monObj%.IPv4Address*}"
cmclient -v ip_status GETV "$ip_obj.Status"
cmclient -v dnsTimer GETV "$intObj.DNSTimer"
cmclient -v dnsBackoff GETV "$intObj.DNSBackoff"
cmclient -v hostName GETV "$intObj.HostName"
startTimeout="$((dnsBackoff*1000))"
cmclient -v gw GETV "Device.Routing.Router.*.IPv4Forwarding.[Interface=$ip_obj].[DestIPAddress=].GatewayIPAddress"
if [ ${#hostName} -ne 0 -a ${#gw} -ne 0 -a $dnsTimer -gt 0 ]; then
cmclient -u "$AH_NAME" SET "$intObj.DNSTimerExpired" "false"
create_aperiodic_timer "$intObj" "$dnsTimer" "DNSTimer" "$intObj.DNSTimerExpired" "true"
if dns_test "$ip_obj" "$gw" "$hostName" "$startTimeout" "$intObj" "$((dnsTimer*1000))"; then
rm -f /tmp/InterfaceMonitor_DNS_${intObj}.pid
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${intObj}_DNSTimer]"
cmclient -v dnsRetest GETV "$intObj.DNSRetest"
create_aperiodic_timer "$intObj" "$dnsRetest" "DNSRetest" "$intObj.DNSRestart" "true"
handle_status_event "$intObj" "Up"
else
rm -f /tmp/InterfaceMonitor_DNS_${intObj}.pid
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${intObj}_DNSTimer]"
cmclient SET "$ip_obj.Reset" "true"
fi
else
handle_status_event "$intObj" "Down"
fi
;;
esac
return 1
}
get_grp_intf_up() {
local gro=$2 _intf ret
cmclient -v ret GETO "$gro.Interface.[OnlineStatus=Up]"
if [ ${#ret} -eq 0 ]; then
cmclient -v _intf GETV "$gro.Interface.MonitoredInterface"
for _intf in $_intf; do
cmclient -v _intf GETO $_intf.[Enable=true].[Status=Up]
if [ ${#_intf} -ne 0 ]; then
cmclient -v ret GETO "$gro.Interface.[MonitoredInterface=$_intf]"
break
fi
done
fi
eval $1='$ret'
}
toggle_enable_interface() {
local obj="$1" val="$2" usr="$3" llayer
case "$obj" in
"Device.IP.Interface"*)
cmclient -v llayer GETV "$obj.X_ADB_ActiveLowerLayer"
[ ${#llayer} -eq 0 ] && cmclient -v llayer GETV "Device.InterfaceStack.[HigherLayer=$obj].LowerLayer"
for llayer in $llayer; do
case "$llayer" in
"Device.PPP.Interface"*)
cmclient -v is_phy GETO "Device.X_ADB_InterfaceMonitor.Group.*.Interface.[ReferenceInterface=].[MonitoredInterface=$llayer]"
if [ ${#is_phy} -eq 0 ]; then
if [ "$usr" = "boot" ]; then
cmclient -u "PPPIf$llayer" SET "$llayer.Enable" "$val"
else
cmclient SET "$llayer.Enable" "$val"
fi
fi
;;
esac
done
;;
"Device.Ethernet.Interface"*)
if [ "$usr" = "boot" ]; then
cmclient -v ifname GETV "$obj.Name"
while [ -d /sys/class/net/${ifname} -a ! -e /tmp/${ifname}_ready ]; do
sleep 1
done
fi
;;
"Device.DSL.Line"*)
[ -x /etc/ah/DslBonding.sh ] && return
;;
esac
if [ "$usr" = "boot" ]; then
cmclient -u "$AH_NAME" SET "$obj.Enable" "$val"
else
cmclient SET "$obj.Enable" "$val"
fi
}
handle_dnstimer_expired() {
local intfObj="$1"
dns_cleaning "$intfObj" "$newMonitoredInterface"
cmclient SET "$newMonitoredInterface.Reset" "true"
cmclient -u "$AH_NAME" SET "$intfObj.DNSTimerExpired" "false"
}
del_startup_timeout() {
local groupObj="$1" intObj startupTimer
cmclient -v intObj GETO "$groupObj.Interface.[Enable=true].[AdminStatus=NotOperational]"
for intObj in $intObj; do
cmclient -v startupTimer GETO "Device.X_ADB_Time.Event.[Alias=${intObj}_StartupTimeout]"
if [ ${#startupTimer} -ne 0 ]; then
cmclient DEL "$startupTimer"
cmclient -u "${AH_NAME}" SET "${intObj}.AdminStatus" "Operational"
fi
done
}
handle_online_status_event() {
local intfObj="$1" status="$2" refIntf="$3" prioOver="$4" prioCurr="$5" groupObj="${1%.Interface*}" objs startupTimeout refMon refStatus i
if [ "$status" = "Up" ]; then
forcedEnable="false"
del_startup_timeout "$groupObj"
if [ ${#refIntf} -ne 0 ]; then
local group="${refIntf%.Interface*}"
del_startup_timeout "$group"
cmclient -v interface GETO "$group.Interface"
for interface in $interface; do
[ "$interface" = "$refIntf" ] && continue
cmclient -v group GETO "Device.X_ADB_InterfaceMonitor.Group.[Interface.ReferenceInterface=$interface]"
for group in $group; do
del_startup_timeout "$group"
done
done
fi
else
forcedEnable="true"
fi
if [ ${#refIntf} -ne 0 ]; then
if [ "$status" = "Down" ]; then
cmclient -v other_obj GETO "Device.X_ADB_InterfaceMonitor.Group.[Enable=true].Interface.[Enable=true].[AdminStatus=Operational].[ReferenceInterface=$refIntf].[OnlineStatus=Up]"
[ ${#other_obj} -eq 0 ] && cmclient SET "$refIntf.OnlineStatus" "$status"
else
cmclient SET "$refIntf.OnlineStatus" "$status"
fi
cmclient -v refMon GETV "$refIntf.MonitoredInterface"
cmclient -v refStatus GETV "$refMon.Status"
fi
cmclient -v objs GETO "$groupObj.Interface.[Enable=true].[AdminStatus=Operational]"
for i in $objs; do
[ "$i" = "$intfObj" ] && continue
if [ "$prioOver" = "false" ]; then
cmclient -v prio GETV "$i.Priority"
if [ $prio -ge $prioCurr ]; then
cmclient -v monitoredObj GETV "$i.MonitoredInterface"
[ "$status" = "Up" ] && cmclient -u "$AH_NAME" SET "$i.OnlineStatus" "Down"
toggle_enable_interface "$monitoredObj" "$forcedEnable"
fi
else
cmclient -v monitoredObj GETV "$i.MonitoredInterface"
[ "$status" = "Up" ] && cmclient -u "$AH_NAME" SET "$i.OnlineStatus" "Down"
toggle_enable_interface "$monitoredObj" "$forcedEnable"
fi
done
}
create_aperiodic_timer() {
local intfObj="$1" delay="$2" type="$3" path="$4" value="$5" eventObj setm_params j
cmclient -v eventObj ADDS "Device.X_ADB_Time.Event"
eventObj="Device.X_ADB_Time.Event.$eventObj"
local setm_params="$eventObj.Alias=${intfObj}_${type}"
setm_params="$setm_params	$eventObj.Type=Aperiodic"
setm_params="$setm_params	$eventObj.DeadLine=$delay"
cmclient -v j ADDS "$eventObj.Action"
setm_params="$setm_params	$eventObj.Action.$j.Operation=Set"
setm_params="$setm_params	$eventObj.Action.$j.Path=$path"
setm_params="$setm_params	$eventObj.Action.$j.Value=$value"
cmclient SETEM "$setm_params"
cmclient SET "$eventObj.Enable" "true"
}
additional_conditions_test() {
local actionObj="$1" condobjs item path pathval value
cmclient -v condobjs GETO "$actionObj.AdditionalCondition"
for item in $condobjs; do
cmclient -v path GETV "$item.Path"
if [  -n "$path" ]; then
cmclient -v pathval GETV "$path"
cmclient -v value GETV "$item.Value"
[ "$pathval" != "$value" ] && return 1
fi
done
return 0
}
create_hysteresis_timer() {
local intfObj="$1" hysteresis="$2" eventType="$3" autoSet="$4" eventObj i objs startupTimeout setm_params op path val
cmclient -v eventObj ADDS "Device.X_ADB_Time.Event"
eventObj="Device.X_ADB_Time.Event.$eventObj"
setm_params="$eventObj.Alias=${intfObj}_${eventType}"
[ $hysteresis -eq 0 ] && hysteresis="1"
setm_params="$setm_params	$eventObj.Type=Aperiodic"
setm_params="$setm_params	$eventObj.DeadLine=$hysteresis"
if [ "$eventType" = "Up" ]; then
cmclient -v ref_obj GETO "Device.X_ADB_InterfaceMonitor.Group.[Enable=true].Interface.[Enable=true].[AdminStatus=Operational].[ReferenceInterface=$intfObj].[OnlineStatus!Up]"
if [ ${#ref_obj} -eq 0 ]; then
if [ "$autoSet" = "false" ]; then
cmclient -v i ADDS "$eventObj.Action"
setm_params="$setm_params	$eventObj.Action.$i.Operation=Set"
setm_params="$setm_params	$eventObj.Action.$i.Path=${intfObj}.OnlineStatus"
setm_params="$setm_params	$eventObj.Action.$i.Value=Up"
fi
else
for ref_obj in $ref_obj; do
cmclient -v startupTimeout GETV "$ref_obj.StartupTimeout"
if [ "$startupTimeout" != "0" ]; then
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${ref_obj}_StartupTimeout]"
cmclient SET "$ref_obj.AdminStatus" "NotOperational"
create_aperiodic_timer "$ref_obj" "$startupTimeout" "StartupTimeout" "$ref_obj.AdminStatus" "Operational"
else
cmclient -v i ADDS "$eventObj.Action"
setm_params="$setm_params	$eventObj.Action.$i.Operation=Set"
setm_params="$setm_params	$eventObj.Action.$i.Path=$ref_obj.AdminStatus"
setm_params="$setm_params	$eventObj.Action.$i.Value=Operational"
fi
done
fi
else
cmclient -v ref_obj GETO "Device.X_ADB_InterfaceMonitor.Group.[Enable=true].Interface.[Enable=true].[AdminStatus=Operational].[ReferenceInterface=$intfObj].[OnlineStatus=Up]"
if [ ${#ref_obj} -eq 0 ]; then
if [ "$autoSet" = "false" ]; then
cmclient -v i ADDS "$eventObj.Action"
setm_params="$setm_params	$eventObj.Action.$i.Operation=Set"
setm_params="$setm_params	$eventObj.Action.$i.Path=${intfObj}.OnlineStatus"
setm_params="$setm_params	$eventObj.Action.$i.Value=Down"
fi
fi
fi
cmclient -v objs GETO "$intfObj.Action.[Event=$eventType].[Operation!None]"
for actionObj in $objs; do
if additional_conditions_test "$actionObj"; then
cmclient -v op GETV "$actionObj.Operation"
cmclient -v path GETV "$actionObj.Path"
cmclient -v val GETV "$actionObj.Value"
cmclient -v i ADDS "$eventObj.Action"
setm_params="$setm_params	$eventObj.Action.$i.Operation=$op"
setm_params="$setm_params	$eventObj.Action.$i.Path=$path"
setm_params="$setm_params	$eventObj.Action.$i.Value=$val"
fi
done
cmclient SETEM "$setm_params"
cmclient SET "$eventObj.Enable" "true"
}
handle_status_event() {
local intfObj="$1" status="$2" currentPrio monitorPrio prioOverride refInterface
[ ${#intfObj} -eq 0 ] && return
if [ "$status" = "Up" ]; then
help_serialize "${AH_NAME}_OnlineStatus_${status}" notrap
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${intfObj}_Down]"
groupObj="${intfObj%.Interface*}"
cmclient -v currentUpIntf GETO "$groupObj.Interface.[OnlineStatus=Up]"
if [ ${#currentUpIntf} -ne 0 ]; then
cmclient -v currentPrio GETV "$currentUpIntf.Priority"
cmclient -v monitorPrio GETV "$intfObj.Priority"
if [ $monitorPrio -lt $currentPrio ]; then
cmclient -v hystObj GETO "Device.X_ADB_Time.Event.[Alias=${intfObj}_${status}]"
if [ ${#hystObj} -eq 0 ]; then
cmclient -v hystUp GETV "$intfObj.HysteresisUp"
create_hysteresis_timer "$intfObj" "$hystUp" "$status" "false"
fi
fi
else
cmclient -v allUpIntf GETO "Device.X_ADB_InterfaceMonitor.Group.*.Interface.[OnlineStatus=Up].[ReferenceInterface!]"
if [ ${#allUpIntf} -eq 0 ]; then
[ "$user" != "Time" ] && cmclient DEL "Device.X_ADB_Time.Event.[Alias=${intfObj}_${status}]"
[ -f /etc/ah/helper_check_custom_if_cond.sh ] && . /etc/ah/helper_check_custom_if_cond.sh && help_get_hysteresisUp hystUp "$intfObj" || hystUp="1"
cmclient -v refInterface GETV "$intfObj.ReferenceInterface"
if [ ${#refInterface} -ne 0 ]; then
cmclient -u "$AH_NAME" SET "$intfObj.OnlineStatus" "Up"
cmclient -v monitorPrio GETV "$intfObj.Priority"
cmclient -v prioOverride GETV "$intfObj.PriorityOverride"
handle_online_status_event "$intfObj" "Up" "$refInterface" "$prioOverride" "$monitorPrio"
create_hysteresis_timer "$intfObj" "$hystUp" "$status" "true"
else
create_hysteresis_timer "$intfObj" "$hystUp" "$status" "false"
fi
else
cmclient -v hystObj GETO "Device.X_ADB_Time.Event.[Alias=${intfObj}_${status}]"
if [ ${#hystObj} -eq 0 ]; then
cmclient -v hystUp GETV "$intfObj.HysteresisUp"
create_hysteresis_timer "$intfObj" "$hystUp" "$status" "false"
fi
fi
fi
help_serialize_unlock "${AH_NAME}_OnlineStatus_${status}"
else
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${intfObj}_Up]"
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${intfObj}_StartupTimeout]"
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${intfObj}_HysteresisARP]"
dns_cleaning "$intfObj" "" "$self_pid"
cmclient -v hystObj GETO "Device.X_ADB_Time.Event.[Alias=${intfObj}_${status}]"
if [ ${#hystObj} -eq 0 ]; then
if [ ${#ip_status} -ne 0 -a "$ip_status" != "Up" ]; then
cmclient -v onlineStatus GETV "$intfObj.OnlineStatus"
if [ "$onlineStatus" != "Down" ]; then
help_serialize "${AH_NAME}_OnlineStatus_${status}" notrap
cmclient -u "$AH_NAME" SET "$intfObj.OnlineStatus" "Down"
cmclient -v monitorPrio GETV "$intfObj.Priority"
cmclient -v prioOverride GETV "$intfObj.PriorityOverride"
cmclient -v refInterface GETV "$intfObj.ReferenceInterface"
handle_online_status_event "$intfObj" "Down" "$refInterface" "$prioOverride" "$monitorPrio"
help_serialize_unlock "${AH_NAME}_OnlineStatus_${status}"
fi
create_hysteresis_timer "$intfObj" "1" "$status" "true"
else
cmclient -v hystDown GETV "$intfObj.HysteresisDown"
create_hysteresis_timer "$intfObj" "$hystDown" "$status" "false"
fi
fi
fi
}
service_delete() {
local intfObj enable ip_obj
case "$obj" in
"Device.X_ADB_InterfaceMonitor.Group."*".Interface."*)
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${obj}_Up]"
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${obj}_StartupTimeout]"
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${obj}_HysteresisARP]"
dns_cleaning "$obj"
toggle_enable_interface "$newMonitoredInterface" "true"
;;
"Device.IP.Interface."*".IPv4Address"*)
cmclient -v ip_status GETV "${obj%.IPv4Address*}.Status"
cmclient -v intfObj GETO "Device.X_ADB_InterfaceMonitor.Group.[Enable=true].Interface.[Enable=true].[AdminStatus=Operational].[MonitoredInterface<$obj]"
if [ ${#intfObj} -ne 0 ]; then
cmclient -u "${AH_NAME}" SET "$intfObj.ARP.DiagnosticsState" "None"
handle_status_event "$intfObj" "Down"
fi
;;
esac
}
service_config() {
local groupObj interface intfObj arpTimer detMode groupEnable _OnlineStatus refStatus address
case "$obj" in
"Device.X_ADB_InterfaceMonitor")
[ "$setEnable" = "1" -a "$newEnable" = "true" ] && ifmonitor_init
;;
"Device.X_ADB_InterfaceMonitor.Group."*".Interface."*".ARP"*)
intfObj="${obj%.ARP*}"
if [ "$changedDiagnosticsState" = "1" -a "$newDiagnosticsState" = "Fail" ]; then
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${intfObj}_HysteresisARP]"
cmclient SETE "$obj.[TimerExpired=true].TimerExpired" "false"
cmclient -v _OnlineStatus GETV "$intfObj.OnlineStatus"
if [ "$_OnlineStatus" != "Down" ]; then
cmclient -v interface GETV "$intfObj.MonitoredInterface"
cmclient SET "$interface.Reset" "true"
fi
elif [ "$changedDiagnosticsState" = "1" -a "$newDiagnosticsState" = "Complete" ]; then
cmclient -v arpTimer GETV "$obj.TimerInterval"
create_aperiodic_timer "$intfObj" "$arpTimer" "HysteresisARP" "$obj.TimerExpired" "true"
cmclient SETE "$obj.[TimerExpired=true].TimerExpired" "false"
elif [ "$changedTimerExpired" = "1" -a "$newTimerExpired" = "true" ]; then
handle_status_event "$intfObj" "Up"
fi
;;
"Device.X_ADB_InterfaceMonitor.Group."*".Interface."*)
groupObj="${obj%.Interface*}"
cmclient -v groupEnable GETV "$groupObj.Enable"
[ "$groupEnable" = "false" ] && return
[ "$changedOnlineStatus" = "1" ] && handle_online_status_event "$obj" "$newOnlineStatus" "$newReferenceInterface" "$newPriorityOverride" "$newPriority"
[ "$changedDNSTimerExpired" = "1" -a "$newDNSTimerExpired" = "true" ] && handle_dnstimer_expired "$obj"
if [ "$changedEnable" = "1" -a ${#newMonitoredInterface} -ne 0 ]; then
cmclient DEL "Device.X_ADB_Time.Event.[Alias=${obj}_Up]"
[ "$user" != "Time" ] && cmclient DEL "Device.X_ADB_Time.Event.[Alias=${obj}_StartupTimeout]"
dns_cleaning "$obj" "" "$self_pid"
if [ "$newEnable" = "true" ]; then
get_grp_intf_up currentUpIntf $groupObj
if [ ${#currentUpIntf} -ne 0 ]; then
cmclient -v _OnlineStatus GETO "Device.X_ADB_InterfaceMonitor.Group.Interface.[ReferenceInterface=$currentUpIntf].[OnlineStatus=Up]"
if [ ${#_OnlineStatus} -eq 0 -a ${#newReferenceInterface} -eq 0 ]; then
toggle_enable_interface "$newMonitoredInterface" "$newEnable"
else
cmclient -v currentPrio GETV "$currentUpIntf.Priority"
cmclient -v monitorPrio GETV "$obj.Priority"
[ $monitorPrio -lt $currentPrio ] && toggle_enable_interface "$newMonitoredInterface" "$newEnable"
fi
else
if [ ${#newReferenceInterface} -eq 0 ]; then
toggle_enable_interface "$newMonitoredInterface" "$newEnable"
else
cmclient -v interface GETV "$newReferenceInterface.MonitoredInterface"
cmclient -v refStatus GETV "$interface.Status"
[ "$refStatus" = "Up" ] && toggle_enable_interface "$newMonitoredInterface" "$newEnable"
fi
fi
elif [ "$newEnable" = "false" ]; then
cmclient -u "${AH_NAME}" SET "$obj.ARP.[DiagnosticsState!None].DiagnosticsState" "None"
toggle_enable_interface "$newMonitoredInterface" "$newEnable"
if [ "$newOnlineStatus" = "Up" ]; then
cmclient -u "$AH_NAME" SET "$obj.OnlineStatus" "Down"
handle_online_status_event "$obj" "Down" "$newReferenceInterface" "$newPriorityOverride" "$newPriority"
fi
fi
fi
if [ "$changedHostName" = "1" -o "$changedDNSTimer" = "1" -o "$changedDNSRetest" = "1" -o "$changedDNSBackoff" = "1" -o "$changedDetectionMode" = "1" ] && \
[ "$newEnable" = "true" -a ${#newMonitoredInterface} -ne 0 -a "$newDetectionMode" = "DNS" ]; then
handle_dnstimer_expired "$obj"
fi
if [ "$setDNSRestart" = "1" -a "$newDNSRestart" = "true" ]; then
(read self_pid _ < /proc/self/stat; check_up_condition "$obj" "$newDetectionMode" "$newMonitoredInterface") &
echo "$!" >> /tmp/InterfaceMonitor_DNS_${obj}.pid
fi
if [ "$changedDetectionMode" = "1" -a ${newMonitoredInterface%.*} = "Device.IP.Interface" ]; then
cmclient -v address GETO "$newMonitoredInterface.IPv4Address"
for address in $address; do
case "$newDetectionMode" in
"IP")
if check_up_condition "$obj" "$newDetectionMode" "$address"; then
[ "$newOnlineStatus" != "Up" ] && handle_status_event "$obj" "Up"
else
[ "$newOnlineStatus" != "Down" ] && handle_status_event "$obj" "Down"
fi
;;
"ARP") check_up_condition "$obj" "$newDetectionMode" "$address" ;;
esac
done
fi
if [ "$setAdminStatus" = "1" -a ${#newMonitoredInterface} -ne 0 ]; then
[ "$changedAdminStatus" = "1" ] && cmclient DEL "Device.X_ADB_Time.Event.[Alias=${obj}_Up]"
[ "$user" != "Time" ] && cmclient DEL "Device.X_ADB_Time.Event.[Alias=${obj}_StartupTimeout]"
dns_cleaning "$obj" "" "$self_pid"
if [ "$newAdminStatus" = "Operational" ]; then
newToggle="true"
else
newToggle="false"
cmclient -u "$AH_NAME" SET "$obj.OnlineStatus" "Down"
handle_online_status_event "$obj" "Down" "$newReferenceInterface" "$newPriorityOverride" "$newPriority"
fi
toggle_enable_interface "$newMonitoredInterface" "$newToggle"
fi
;;
"Device.X_ADB_InterfaceMonitor.Group."*)
;;
*)	# L1 / L3 Interface SET (Status, DNSServers, IPAddress...)
case "$obj" in
"Device.IP.Interface."*".IPv4Address"*)
ip_obj="${obj%.IPv4Address*}"
cmclient -v is_upstream GETV "$ip_obj.X_ADB_Upstream"
set_type="IP"
;;
"Device.PPP.Interface."*)
is_upstream="true"
set_type="OTHER"
;;
*)
cmclient -v is_upstream GETV "$obj.Upstream"
set_type="OTHER"
;;
esac
[ ${#is_upstream} -ne 0 -a "$is_upstream" != "true" ] && return
cmclient -v intfObj GETO "Device.X_ADB_InterfaceMonitor.Group.[Enable=true].Interface.[Enable=true].[AdminStatus=Operational].[MonitoredInterface<$obj]"
if [ ${#intfObj} -ne 0 ]; then
cmclient -v detMode GETV "$intfObj.DetectionMode"
if [ "$set_type" = "IP" -a "$detMode" = "IP" ]; then
if check_up_condition "$intfObj" "$detMode" "$obj"; then
handle_status_event "$intfObj" "Up"
else
handle_status_event "$intfObj" "Down"
fi
elif [ "$set_type" = "IP" -a "$detMode" = "ARP" ]; then
check_up_condition "$intfObj" "$detMode" "$obj"
elif [ "$set_type" = "OTHER" -a "$detMode" = "LINK" ]; then
if [ "$changedStatus" = "1" ]; then
if check_up_condition "$intfObj" "$detMode" "$obj"; then
handle_status_event "$intfObj" "Up"
else
handle_status_event "$intfObj" "Down"
fi
fi
fi
fi
;;
esac
}
ifmonitor_init() {
local objs startupTime val usr=""
cmclient SETE "Device.X_ADB_InterfaceMonitor.Group.Interface.OnlineStatus" "Down"
cmclient -u "$AH_NAME" SET "Device.X_ADB_InterfaceMonitor.Group.Interface.[DetectionMode=ARP].ARP.[DiagnosticsState!None].DiagnosticsState" "None"
cmclient DEL "Device.X_ADB_Time.Event.[Alias>Device.X_ADB_InterfaceMonitor.Group]"
cmclient -v objs GETV "Device.X_ADB_InterfaceMonitor.Group.[Enable=true].Interface.[Enable=true].MonitoredInterface"
cmclient -v val GETV "Device.DeviceInfo.X_ADB_BootDone"
[ "$val" = "false" ] && usr="boot"
for objs in $objs; do
toggle_enable_interface "$objs" "false" "$usr"
done
cmclient DEL "Device.X_ADB_Time.Event.[Alias>StartupTimeout]"
cmclient -v objs GETO "Device.X_ADB_InterfaceMonitor.Group.[Enable=true].Interface.[Enable=true].[StartupTimeout!0]"
for objs in $objs; do
cmclient SETE "$objs.AdminStatus" "NotOperational"
cmclient -v startupTime GETV "$objs.StartupTimeout"
create_aperiodic_timer "$objs" "$startupTime" "StartupTimeout" "$objs.AdminStatus" "Operational"
done
cmclient -v objs GETV "Device.X_ADB_InterfaceMonitor.Group.[Enable=true].Interface.[Enable=true].[AdminStatus=Operational].[ReferenceInterface=].MonitoredInterface"
for objs in $objs; do
toggle_enable_interface "$objs" "true"
done
exit 0
}
[ "$op" = s -a "$changedStatus" = 1 ] && . /etc/ah/helper_lastChange.sh && help_lastChange_set "$obj"
cmclient -v globEnable GETV Device.X_ADB_InterfaceMonitor.Enable
[ "$globEnable" = "false" ] && return
case "$op" in
s) service_config ;;
d) service_delete ;;
esac
exit 0
