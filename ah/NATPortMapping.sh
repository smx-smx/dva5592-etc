#!/bin/sh
AH_NAME="NatPortMapping"
[ "$user" = "ah_PortMapping" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_ipcalc.sh
chain=NATPM.${obj##*.}
[ "$user" = "cwmp" ] && from="remote" || from="local"
case "$op" in
d)
[ -n "$newDescription" ] && logger -t "cm" -p 6 "Port mapping ${newDescription} removed (${from})"
cmclient -u ah_PortMapping SETM "$obj.Status=Disabled	$obj.X_ADB_ErrorReason="
cmclient SETE $obj.Enable false
help_iptables -t nat -D SnatMapping -j "SNAT_$chain"
help_iptables -t nat -D PortMapping -j "${chain}_SNAT"
help_iptables -t nat -D PortMapping -j "$chain"
help_iptables -t filter -D ForwardAllow_PortMapping -j "$chain"
help_iptables -t filter -F "$chain"
help_iptables -t filter -X "$chain"
help_iptables -t mangle -D PortMapping -j "$chain"
help_iptables -t mangle -F "$chain"
help_iptables -t mangle -X "$chain"
help_iptables -t mangle -D SnatMapping -j "SNAT_$chain"
help_iptables -t mangle -F "SNAT_$chain"
help_iptables -t mangle -X "SNAT_$chain"
help_iptables -t nat -F "SNAT_$chain"
help_iptables -t nat -X "SNAT_$chain"
help_iptables -t nat -F "${chain}_SNAT"
help_iptables -t nat -X "${chain}_SNAT"
help_iptables -t nat -F "$chain"
help_iptables -t nat -X "$chain"
. /etc/ah/helper_conflicts.sh
[ "$oldAllInterfaces" = "true" ] && help_reconfigure_nat_conflicts || \
help_reconfigure_nat_conflicts "$oldInterface"
exit 0
;;
a)
[ -n "$newDescription" ] && logger -t "cm" -p 6 "Port mapping ${newDescription} added (${from})"
help_iptables -t nat -N "$chain"
help_iptables -t nat -A PortMapping -j "$chain"
help_iptables -t nat -N "${chain}_SNAT"
help_iptables -t nat -A PortMapping -j "${chain}_SNAT"
help_iptables -t nat -N "SNAT_$chain"
help_iptables -t nat -A SnatMapping -j "SNAT_$chain"
help_iptables -t mangle -N "$chain"
help_iptables -t mangle -A PortMapping -j "$chain"
help_iptables -t mangle -N "SNAT_$chain"
help_iptables -t mangle -A SnatMapping -j "SNAT_$chain"
help_iptables -N "$chain"
help_iptables -A ForwardAllow_PortMapping -j "$chain"
exit 0
;;
esac
case "$1" in
init)
cmclient -v objs GETO Device.NAT.PortMapping
for i in $objs; do
i=NATPM.${i##*.}
help_iptables -t nat -N "$i"
help_iptables -t nat -A PortMapping -j "$i"
help_iptables -t nat -N "${i}_SNAT"
help_iptables -t nat -A PortMapping -j "${i}_SNAT"
help_iptables -t nat -N "SNAT_$i"
help_iptables -t nat -A SnatMapping -j "SNAT_$i"
help_iptables -t mangle -N "$i"
help_iptables -t mangle -A PortMapping -j "$i"
help_iptables -t mangle -N "SNAT_$i"
help_iptables -t mangle -A SnatMapping -j "SNAT_$i"
help_iptables -N "$i"
help_iptables -A ForwardAllow_PortMapping -j "$i"
done
exit 0
;;
refresh)
for x in mangle nat filter; do
help_iptables -t $x
done
cmclient -v objs GETO Device.NAT.PortMapping.[Enable=true]
for i in $objs; do
cmclient SET -u "${tmpiptablesprefix##*/}" $i.Enable true
done
exit 0
;;
esac
refresh=0
help_is_changed Interface AllInterfaces RemoteHost ExternalPort ExternalPortEndRange \
Protocol InternalClient InternalPort X_ADB_AdditionalExternalPort X_ADB_Hairpinning \
X_ADB_WanConnectionType X_ADB_ForwardingPolicy && refresh=1
if [ "$changedEnable" = "1" ]; then
status="enabled"
[ -n "$newDescription" ] && rule="$newDescription" || cmclient -v rule GETV "$obj".Description
[ "$newEnable" = "false" ] && status="disabled"
[ -n "$rule" ] && logger -t "cm" -p 6 "Port mapping ${rule} ${status} (${from})"
fi
[ $setEnable -eq 0 -a $refresh -eq 0 ] && exit 0
if [ $refresh -eq 1 -o "$changedEnable" = "1" ]; then
. /etc/ah/helper_conflicts.sh
[ "$newAllInterfaces" = "true" ] && help_reconfigure_nat_conflicts || \
help_reconfigure_nat_conflicts "$newInterface"
fi
checkAddExternalPortSyntaxOnPort() {
local __addExtPort="$1" ret=0 x dd bb cc ret
set -f
IFS=","
set -- $__addExtPort
unset IFS
set +f
for x; do
dd=""
bb=${x#*:}
cc=${bb%-*}
case $x in
*-* )
dd=${bb#*-}
;;
esac
if [ -n "$cc" -a "$cc" -gt "65535" ]; then
ret=2
break
fi
if [ -n "$dd" ] && [ "$cc" -gt "$dd" -o \
"$dd" -gt "65535" ]; then
ret=2
break
fi
done
return $ret
}
pm_conflict=0
if [ -n "$newInterface" ]; then
cmclient -v is_wan GETV "$newInterface.X_ADB_Upstream"
else
is_wan="false"
fi
entest=".[Enable=true].[X_ADB_AccessControlEnable=false]"
encwmptest=".[EnableCWMP=true]"
cmclient -v httpRemoteAccessIf GETV UserInterface.RemoteAccess.X_ADB_Interface
if [ "$newAllInterfaces" = "true" ]; then
cmclient -v httpRemoteAccessPort GETV Device.UserInterface.RemoteAccess$entest.[X_ADB_ProtocolsEnabled,HTTP].Port
cmclient -v httpsRemoteAccessPort GETV Device.UserInterface.RemoteAccess$entest.[X_ADB_ProtocolsEnabled,HTTPS].X_ADB_HTTPSPort
elif [ -z "$httpRemoteAccessIf" ] && [ "$is_wan" = "true" ]; then
cmclient -v httpRemoteAccessPort GETV Device.UserInterface.RemoteAccess$entest.[X_ADB_ProtocolsEnabled,HTTP].Port
cmclient -v httpsRemoteAccessPort GETV Device.UserInterface.RemoteAccess$entest.[X_ADB_ProtocolsEnabled,HTTPS].X_ADB_HTTPSPort
else
cmclient -v httpRemoteAccessPort GETV Device.UserInterface.RemoteAccess$entest.[X_ADB_ProtocolsEnabled,HTTP].[X_ADB_Interface="$newInterface"].Port
cmclient -v httpsRemoteAccessPort GETV Device.UserInterface.RemoteAccess$entest.[X_ADB_ProtocolsEnabled,HTTPS].[X_ADB_Interface="$newInterface"].X_ADB_HTTPSPort
fi
cmclient -v httpLocalAccessIf GETV Device.UserInterface.X_ADB_LocalAccess.Interface
if [ "$newAllInterfaces" = "true" ]; then
cmclient -v httpLocalAccessPort GETV Device.UserInterface.X_ADB_LocalAccess.[Enable=true].[X_ADB_ProtocolsEnabled,HTTP].Port
cmclient -v httpsLocalAccessPort GETV Device.UserInterface.X_ADB_LocalAccess.[Enable=true].[X_ADB_ProtocolsEnabled,HTTPS].HTTPSPort
elif [ -z "$httpLocalAccessIf" ] && [ "$is_wan" = "false" ]; then
cmclient -v httpLocalAccessPort GETV Device.UserInterface.X_ADB_LocalAccess.[Enable=true].[X_ADB_ProtocolsEnabled,HTTP].Port
cmclient -v httpsLocalAccessPort GETV Device.UserInterface.X_ADB_LocalAccess.[Enable=true].[X_ADB_ProtocolsEnabled,HTTPS].HTTPSPort
else
cmclient -v httpLocalAccessPort GETV Device.UserInterface.X_ADB_LocalAccess.[Enable=true].[X_ADB_ProtocolsEnabled,HTTP].[X_ADB_LocalAccess="$newInterface"].Port
cmclient -v httpsLocalAccessPort GETV Device.UserInterface.X_ADB_LocalAccess.[Enable=true].[X_ADB_ProtocolsEnabled,HTTPS].[X_ADB_LocalAccess="$newInterface"].HTTPSPort
fi
cmclient -v sshRemoteAccessIf GETV Device.X_ADB_SSHServer.RemoteAccess.Interfaces
if [ "$newAllInterfaces" = "true" ]; then
cmclient -v sshRemoteAccessPort GETV Device.X_ADB_SSHServer.RemoteAccess$entest.Port
elif [ -z "$sshRemoteAccessIf" ] && [ "$is_wan" = "true" ]; then
cmclient -v sshRemoteAccessPort GETV Device.X_ADB_SSHServer.RemoteAccess$entest.Port
else
cmclient -v sshRemoteAccessPort GETV Device.X_ADB_SSHServer.RemoteAccess$entest.[Interfaces="$newInterface"].Port
fi
cmclient -v sshLocalAccessIf GETV Device.X_ADB_SSHServer.LocalAccess.Interfaces
if [ "$newAllInterfaces" = "true" ]; then
cmclient -v sshLocalAccessPort GETV Device.X_ADB_SSHServer.LocalAccess.[Enable=true].Port
elif [ -z "$sshLocalAccessIf" ] && [ "$is_wan" = "false" ]; then
cmclient -v sshLocalAccessPort GETV Device.X_ADB_SSHServer.LocalAccess.[Enable=true].Port
else
cmclient -v sshLocalAccessPort GETV Device.X_ADB_SSHServer.LocalAccess.[Enable=true].[Interfaces="$newInterface"].Port
fi
cmclient -v telnetRemoteAccessIf GETV Device.X_ADB_TelnetServer.RemoteAccess.Interface
if [ "$newAllInterfaces" = "true" ]; then
cmclient -v telnetRemoteAccessPort GETV Device.X_ADB_TelnetServer.RemoteAccess$entest.Port
elif [ -z "$telnetRemoteAccessIf" ] && [ "$is_wan" = "true" ]; then
cmclient -v telnetRemoteAccessPort GETV Device.X_ADB_TelnetServer.RemoteAccess$entest.Port
else
cmclient -v telnetRemoteAccessPort GETV Device.X_ADB_TelnetServer.RemoteAccess$entest.[Interface="$newInterface"].Port
fi
cmclient -v telnetLocalAccessIf GETV Device.X_ADB_TelnetServer.LocalAccess.Interface
if [ "$newAllInterfaces" = "true" ]; then
cmclient -v telnetLocalAccessPort GETV Device.X_ADB_TelnetServer.LocalAccess.[Enable=true].Port
elif [ -z "$telnetLocalAccessIf" ] && [ "$is_wan" = "false" ]; then
cmclient -v telnetLocalAccessPort GETV Device.X_ADB_TelnetServer.LocalAccess.[Enable=true].Port
else
cmclient -v telnetLocalAccessPort GETV Device.X_ADB_TelnetServer.LocalAccess.[Enable=true].[Interface="$newInterface"].Port
fi
cmclient -v mgtConnectionRequestPortIf GETV Device.ManagementServer.X_ADB_ConnectionRequestInterface
if [ "$newAllInterfaces" = "true" ]; then
cmclient -v mgtConnectionRequestPort GETV Device.ManagementServer$encwmptest.X_ADB_ConnectionRequestPort
else
cmclient -v mgtConnectionRequestPort GETV Device.ManagementServer$encwmptest.[X_ADB_ConnectionRequestInterface="$newInterface"].X_ADB_ConnectionRequestPort
fi
checkPortRangeForServices() {
local servRemotePort="$1" servLocalPort="$2" extPort="$3" extPortEnd="$4" \
servType="$5" remoteServIf="" localServIf=""
case $servType in
"HTTP" | "HTTPS" )
[ -n "$httpRemoteAccessPort" -o -n "$httpsRemoteAccessPort" ] && \
remoteServIf="$httpRemoteAccessIf"
[ -n "$httpLocalAccessPort" -o -n "$httpsLocalAccessPort" ] && \
localServIf="$httpLocalAccessIf"
;;
"SSH" )
[ -n "$sshRemoteAccessPort" ] && remoteServIf="$sshRemoteAccessIf"
[ -n "$sshLocalAccessPort" ] && localServIf="$sshLocalAccessIf"
;;
"TELNET" )
[ -n "$telnetRemoteAccessPort" ] && remoteServIf="$telnetRemoteAccessIf"
[ -n "$telnetLocalAccessPort" ] && localServIf="$telnetLocalAccessIf"
;;
"TR69" )
if [ -n "$mgtConnectionRequestPort" ]; then
remoteServIf="$mgtConnectionRequestPortIf"
localServIf="$mgtConnectionRequestPortIf"
fi
;;
esac
srv_conflict=0
if [ "$newAllInterfaces" = "true" ]; then
if [ -n "$servRemotePort" ]; then
if [ $extPortEnd -ne 0 -a "$extPort" != "$extPortEnd" ]; then
if [ "$servRemotePort" -ge "$extPort" -a "$servRemotePort" -le "$extPortEnd" ]; then
srv_conflict=1
fi
else
if [ "$extPort" = "$servRemotePort" ]; then
srv_conflict=1
pm_conflict=1
fi
fi
if [ $srv_conflict -eq 1 ]; then
case $servRemotePort in
"$httpRemoteAccessPort" | "$httpsRemoteAccessPort" )
help_item_add_uniq_in_list errorReason "$errorReason" GUIRemote
;;
esac
[ "$servRemotePort" = "$sshRemoteAccessPort" ] && help_item_add_uniq_in_list errorReason "$errorReason" SSHRemote
[ "$servRemotePort" = "$telnetRemoteAccessPort" ] && help_item_add_uniq_in_list errorReason "$errorReason" TelnetRemote
[ "$servRemotePort" = "$mgtConnectionRequestPort" ] && help_item_add_uniq_in_list errorReason "$errorReason" TR069
return
fi
fi
if [ -n "$servLocalPort" ]; then
if [ $extPortEnd -ne 0 -a "$extPort" != "$extPortEnd" ]; then
if [ "$servLocalPort" -ge "$extPort" -a "$servLocalPort" -le "$extPortEnd" ]; then
srv_conflict=1
fi
else
if [ "$extPort" = "$servLocalPort" ]; then
pm_conflict=1
srv_conflict=1
fi
fi
if [ $srv_conflict -eq 1 ]; then
case $servLocalPort in
"$httpLocalAccessPort" | "$httpsLocalAccessPort" )
help_item_add_uniq_in_list errorReason "$errorReason" GUILocal
;;
esac
[ "$servLocalPort" = "$sshLocalAccessPort" ] && help_item_add_uniq_in_list errorReason "$errorReason" SSHLocal
[ "$servLocalPort" = "$telnetLocalAccessPort" ] && help_item_add_uniq_in_list errorReason "$errorReason" TelnetLocal
[ "$servLocalPort" = "$mgtConnectionRequestPort" ] && help_item_add_uniq_in_list errorReason "$errorReason" TR069
return
fi
fi
else
if [ -n "$newInterface" ]; then
if [ "$is_wan" = "true" ]; then
if [ -n "$servRemotePort" ]; then
if [ -z "$remoteServIf" -o \
"$remoteServIf" = "$newInterface" ]; then
if [ $extPortEnd -ne 0 -a "$extPort" != "$extPortEnd" ]; then
if [ "$servRemotePort" -ge "$extPort" -a "$servRemotePort" -le "$extPortEnd" ]; then
srv_conflict=1
fi
else
if [ "$extPort" = "$servRemotePort" ]; then
pm_conflict=1
srv_conflict=1
fi
fi
fi
if [ $srv_conflict -eq 1 ]; then
case $servRemotePort in
"$httpRemoteAccessPort" | "$httpsRemoteAccessPort" )
help_item_add_uniq_in_list errorReason "$errorReason" GUIRemote
;;
esac
[ "$servRemotePort" = "$sshRemoteAccessPort" ] && help_item_add_uniq_in_list errorReason "$errorReason" SSHRemote
[ "$servRemotePort" = "$telnetRemoteAccessPort" ] && help_item_add_uniq_in_list errorReason "$errorReason" TelnetRemote
[ "$servRemotePort" = "$mgtConnectionRequestPort" ] && help_item_add_uniq_in_list errorReason "$errorReason" TR069
fi
fi
else
if [ -n "$servLocalPort" ]; then
if [ -z "$localServIf" -o \
"$localServIf" = "$newInterface" ]; then
if [ $extPortEnd -ne 0 -a "$extPort" != "$extPortEnd" ]; then
if [ "$servLocalPort" -ge "$extPort" -a "$servLocalPort" -le "$extPortEnd" ]; then
srv_conflict=1
fi
else
if [ "$extPort" = "$servLocalPort" ]; then
pm_conflict=1
srv_conflict=1
fi
fi
fi
if [ $srv_conflict -eq 1 ]; then
case $servLocalPort in
"$httpLocalAccessPort" | "$httpsLocalAccessPort" )
help_item_add_uniq_in_list errorReason "$errorReason" GUILocal
;;
esac
[ "$servLocalPort" = "$sshLocalAccessPort" ] && help_item_add_uniq_in_list errorReason "$errorReason" SSHLocal
[ "$servLocalPort" = "$telnetLocalAccessPort" ] && help_item_add_uniq_in_list errorReason "$errorReason" TelnetLocal
[ "$servLocalPort" = "$mgtConnectionRequestPort" ] && help_item_add_uniq_in_list errorReason "$errorReason" TR069
return
fi
fi
fi
fi
fi
}
checkPortServicesConflict () {
local extPort="$1" extPortEnd="$2" protocol="$3"
if [ "$protocol" = "TCP" -o "$protocol" = "X_ADB_TCPUDP" ]; then
checkPortRangeForServices "$httpRemoteAccessPort" "$httpLocalAccessPort" "$extPort" "$extPortEnd" "HTTP"
checkPortRangeForServices "$httpsRemoteAccessPort" "$httpsLocalAccessPort" "$extPort" "$extPortEnd" "HTTPS"
checkPortRangeForServices "$sshRemoteAccessPort" "$sshLocalAccessPort" "$extPort" "$extPortEnd" "SSH"
checkPortRangeForServices "$telnetRemoteAccessPort" "$telnetLocalAccessPort" "$extPort" "$extPortEnd" "TELNET"
checkPortRangeForServices "$mgtConnectionRequestPort" "$mgtConnectionRequestPort" "$extPort" "$extPortEnd" "TR69"
fi
cmclient SETE "$obj.X_ADB_ErrorReason" "$errorReason"
}
isSameProtocol () {
[ "$1" = "$2" -o \
"$1" = "X_ADB_TCPUDP" -a \( "$2" = "TCP" -o "$2" = "UDP" \) -o \
"$2" = "X_ADB_TCPUDP" -a \( "$1" = "TCP" -o "$1" = "UDP" \) ]
}
checkPMconflict () {
local __x objs y proto bb cc dd remap extract_first first_proto rmproto p1 p2 otherPorts
if [ "$newEnable" = "true" -a "$newX_ADB_ForwardingPolicy" = "-1" ]; then
checkPortServicesConflict "$newExternalPort" "$newExternalPortEndRange" "$newProtocol"
y= proto= bb= cc= dd=
set -f
IFS=","
set -- $newX_ADB_AdditionalExternalPort
unset IFS
set +f
for y; do
proto=${y%%:*}
bb=${y#*:}
cc=${bb%-*}
dd=${bb#*-}
checkPortServicesConflict "$cc" "$dd" "$proto"
pm_conflict=0
done
fi
cmclient -v objs GETO "Device.NAT.PortMapping.[RemoteHost=$newRemoteHost].[Enable=true].[X_ADB_ForwardingPolicy=-1].[Status=Enabled]"
for __x in $objs; do
[ "$__x" = "$obj" ] && continue
if [ $pm_conflict -eq 1 ]; then
break
fi
cmclient -v enable GETV $__x.Enable
cmclient -v remoteIP GETV $__x.RemoteHost
cmclient -v protocol GETV $__x.Protocol
cmclient -v extPort GETV $__x.ExternalPort
cmclient -v extPortEnd GETV $__x.ExternalPortEndRange
cmclient -v addExtPort GETV $__x.X_ADB_AdditionalExternalPort
cmclient -v interface GETV $__x.Interface
cmclient -v allInterfaces GETV $__x.AllInterfaces
if [ "$newAllInterfaces" = "false" ] && [ "$allInterfaces" = "false" ] && \
[ "$newInterface" != "$interface" ]; then
continue
fi
cmclient -v X_ADB_ExternalIPAddress GETV $__x.X_ADB_ExternalIPAddress
[ "$newX_ADB_ExternalIPAddress" != "$X_ADB_ExternalIPAddress" ] && continue
if isSameProtocol "$protocol" "$newProtocol"; then
if [ "$newExternalPortEndRange" = 0 -a "$extPortEnd" = 0 ]; then
if [ "$newExternalPort" = "$extPort" ]; then
pm_conflict=1
fi
elif [ "$newExternalPortEndRange" != 0 -a "$extPortEnd" != 0 ]; then
if [ "$newExternalPort" -ge "$extPort" -a "$newExternalPort" -le "$extPortEnd" -o \
"$newExternalPortEndRange" -ge "$extPort" -a "$newExternalPortEndRange" -le "$extPortEnd" -o \
"$newExternalPort" -le "$extPort" -a "$newExternalPortEndRange" -ge "$extPortEnd" ]; then
pm_conflict=1
fi
elif [ "$newExternalPortEndRange" != 0 -a "$extPortEnd" = 0 ]; then
if [ "$newExternalPort" -le "$extPort" -a "$newExternalPortEndRange" -ge "$extPort" ]; then
pm_conflict=1
fi
else
if [ "$newExternalPort" -ge "$extPort" -a "$newExternalPort" -le "$extPortEnd" ]; then
pm_conflict=1
fi
fi
if [ $pm_conflict -eq 0 ]; then
checkPortServicesConflict "$newExternalPort" "$newExternalPortEndRange" "$newProtocol"
else
cmclient -u ah_PortMapping SET $obj.X_ADB_ErrorReason RuleConflict
break
fi
fi
if [ $pm_conflict -eq 0 ]; then
if [ -n "$addExtPort" ]; then
set -f
IFS=","
set -- $addExtPort
unset IFS
set +f
for y; do
proto=${y%%:*}
bb=${y#*:}
cc=${bb%-*}
dd=${bb#*-}
if isSameProtocol "$newProtocol" "$proto"; then
if [ "$newExternalPortEndRange" = 0 -a "$dd" = 0 ]; then
if [ "$newExternalPort" = "$cc" ]; then
pm_conflict=1
fi
elif [ "$newExternalPortEndRange" != 0 -a "$dd" != 0 ]; then
if [ "$newExternalPort" -ge "$cc" -a "$newExternalPort" -le "$dd" -o \
"$newExternalPortEndRange" -ge "$cc" -a "$newExternalPortEndRange" -le "$dd" -o \
"$newExternalPort" -le "$cc" -a "$newExternalPortEndRange" -ge "$dd" ]; then
pm_conflict=1
fi
else
if [ "$newExternalPortEndRange" != 0 -a "$dd" = 0 ]; then
if [ "$newExternalPort" -le "$cc" -a "$newExternalPortEndRange" -ge "$cc" ]; then
pm_conflict=1
fi
else
if [ "$newExternalPort" -ge "$cc" -a "$newExternalPort" -le "$dd" ]; then
pm_conflict=1
fi
fi
fi
if [ $pm_conflict -eq 1 ]; then
cmclient -u ah_PortMapping SET $obj.X_ADB_ErrorReason RuleConflict
break
fi
fi
done
if [ -n "$newX_ADB_AdditionalExternalPort" ]; then
set -f
IFS=","
set -- $newX_ADB_AdditionalExternalPort
unset IFS
set +f
for y; do
proto=${y%%:*}
bb=${y#*:}
cc=${bb%-*}
dd=${bb#*-}
if isSameProtocol "$protocol" "$proto"; then
if [ "$dd" = 0 -a "$extPortEnd" = 0 ]; then
if [ "$cc" = "$extPort" ]; then
pm_conflict=1
fi
elif [ "$dd" != 0 -a "$extPortEnd" != 0 ]; then
if [ "$cc" -ge "$extPort" -a "$cc" -le "$extPortEnd" -o \
"$dd" -ge "$extPort" -a "$dd" -le "$extPortEnd" -o \
"$cc" -le "$extPort" -a "$dd" -ge "$extPortEnd" ]; then
pm_conflict=1
fi
elif [ "$dd" != 0 -a "$extPortEnd" = 0 ]; then
if [ "$cc" -le "$extPort" -a "$dd" -ge "$extPort" ]; then
pm_conflict=1
fi
else
if [ "$cc" -ge "$extPort" -a "$cc" -le "$extPortEnd" ]; then
pm_conflict=1
fi
fi
if [ $pm_conflict -eq 0 ]; then
checkPortServicesConflict "$cc" "$dd" "$proto"
pm_conflict=0
else
cmclient -u ah_PortMapping SET $obj.X_ADB_ErrorReason RuleConflict
break
fi
fi
if [ $pm_conflict -eq 0 ]; then
set -f
IFS=","
set -- $addExtPort
unset IFS
set +f
for z; do
inner_proto=${z%%:*}
inner_bb=${z#*:}
inner_cc=${inner_bb%-*}
inner_dd=${inner_bb#*-}
if isSameProtocol "$proto" "$inner_proto"; then
if [ "$dd" = 0 -a "$inner_dd" = 0 ]; then
if [ "$cc" = "$inner_cc" ]; then
pm_conflict=1
fi
elif [ "$dd" != 0 -a "$inner_dd" != 0 ]; then
if [ "$cc" -ge "$inner_cc" -a "$cc" -le "$inner_dd" -o \
"$dd" -ge "$inner_cc" -a "$dd" -le "$inner_dd" -o \
"$cc" -le "$inner_cc" -a "$dd" -ge "$inner_dd" ]; then
pm_conflict=1
fi
elif [ "$dd" != 0 -a "$inner_dd" = 0 ]; then
if [ "$cc" -le "$inner_cc" -a "$dd" -ge "$inner_cc" ]; then
pm_conflict=1
fi
else
if [ "$cc" -ge "$inner_cc" -a "$cc" -le "$inner_dd" ]; then
pm_conflict=1
fi
fi
if [ $pm_conflict -eq 1 ]; then
cmclient -u ah_PortMapping SET $obj.X_ADB_ErrorReason RuleConflict
break
fi
fi
done
fi
done
fi
elif [ -n "$newX_ADB_AdditionalExternalPort" ] && [ $pm_conflict -eq 0 ]; then
set -f
IFS=","
set -- $newX_ADB_AdditionalExternalPort
unset IFS
set +f
for y; do
proto=${y%%:*}
bb=${y#*:}
cc=${bb%-*}
dd=${bb#*-}
if isSameProtocol "$proto" "$protocol"; then
if [ "$dd" = 0 -a "$extPortEnd" = 0 ]; then
if [ "$cc" = "$extPort" ]; then
pm_conflict=1
fi
elif [ "$dd" != 0 -a "$extPortEnd" != 0 ]; then
if [ "$cc" -ge "$extPort" -a "$cc" -le "$extPortEnd" -o \
"$dd" -ge "$extPort" -a "$dd" -le "$extPortEnd" -o \
"$cc" -le "$extPort" -a "$dd" -ge "$extPortEnd" ]; then
pm_conflict=1
fi
elif [ "$dd" != 0 -a "$extPortEnd" = 0 ]; then
if [ "$cc" -le "$extPort" -a "$dd" -ge "$extPort" ]; then
pm_conflict=1
fi
else
if [ "$cc" -ge "$extPort" -a "$cc" -le "$extPortEnd" ]; then
pm_conflict=1
fi
fi
if [ $pm_conflict -eq 0 ]; then
checkPortServicesConflict "$cc" "$dd" "$proto"
pm_conflict=0
else
cmclient -u ah_PortMapping SET $obj.X_ADB_ErrorReason RuleConflict
break
fi
fi
done
fi
fi
done
}
getOrder () {
local __o objs
idx=1
if [ "${newExternalPort:-0}" != "0" ]; then
if [ "${newExternalPortEndRange:-0}" != "0" ]; then
rangeSize=$(($newExternalPortEndRange - $newExternalPort))
else
rangeSize=1
fi
else
rangeSize=65536
fi
cmclient -v objs GETO Device.NAT.PortMapping.[Status=Enabled]
for __o in $objs; do
[ "$__o" = "$obj" ] && continue
cmclient -v rangeStart GETV $__o.ExternalPort
cmclient -v rangeEnd GETV $__o.ExternalPortEndRange
if [ $rangeStart -eq 0 ]; then
__rangeSize=65536
elif [ $rangeStart -eq 0 ]; then
__rangeSize=1
else
__rangeSize=$((rangeEnd - rangeStart))
fi
cmclient -v __remoteHost GETV $__o.RemoteHost
if [ -n "$newRemoteHost" ]; then
if [ -n "$__remoteHost" ]; then
if [ $__rangeSize -lt $rangeSize ]; then
idx=$((idx + 1))
fi
fi
else
if [ -n "$__remoteHost" ] || \
[ $__rangeSize -lt $rangeSize ]; then
idx=$((idx + 1))
fi
fi
done
}
flush_chains() {
local chain=$1
help_iptables -t nat -F "$chain"
help_iptables -t nat -F "SNAT_$chain"
help_iptables -t nat -F "${chain}_SNAT"
help_iptables -t mangle -F "$chain"
help_iptables -t mangle -F "SNAT_$chain"
help_iptables -F "$chain"
}
fail=0
if [ -n "$newRemoteHost" ]; then
help_is_valid_ip "$newRemoteHost" || fail=1
fi
if [ "$newExternalPort" != "0" ] && \
[ "$newExternalPortEndRange" != "0" ] && \
[ $newExternalPort -gt $newExternalPortEndRange ]; then
fail=1
fi
if [ "$changedX_ADB_WanConnectionType" = "1" -a "$newX_ADB_WanConnectionType" != "" ]; then
cmclient -v upifs GETO Device.IP.Interface.[X_ADB_ConnectionType\>$newX_ADB_WanConnectionType].[Status=Up]
for upif in $upifs; do
break
done
if [ -n "$upif" -a "$upif" != "$newInterface" ]; then
cmclient -u ah_PortMapping SET $obj.Interface "$upif"
oldInterface="$newInterface"
newInterface="$upif"
changedInterface=1
fi
fi
if [ "$newEnable" = "true" ]; then
if [ "$changedInternalClient" = "1" -a -z "$newInternalClient" ]; then
cmclient -u ah_PortMapping SET $obj.Status Error_Misconfigured
exit 0
fi
if ipcalc -b "$newInternalClient" > /dev/null 2>&1; then
newInternalClientIP="$newInternalClient"
else
active=0
case "$newInternalClient" in
*:*:*:*:*:*)
cmclient -v newInternalClientIP GETV Device.Hosts.Host.[Active=true].[PhysAddress="$newInternalClient"].IPAddress
[ ${#newInternalClientIP} -gt 0 ] && active=1 ||
cmclient -v newInternalClientIP GETV Device.Hosts.Host.[PhysAddress="$newInternalClient"].IPAddress
;;
*)
cmclient -v newInternalClientIP GETV Device.Hosts.Host.[Active=true].[HostName="$newInternalClient"].IPAddress
[ ${#newInternalClientIP} -gt 0 ] && active=1 ||
cmclient -v newInternalClientIP GETV Device.Hosts.Host.[HostName="$newInternalClient"].IPAddress
;;
esac
ipcount=0
for _newInternalClientIP in $newInternalClientIP; do
newInternalClientIP="$_newInternalClientIP"
ipcount=$((ipcount+1))
[ $ipcount -gt 1 ] && break
done
if [ $ipcount -eq 0 ]; then
cmclient -u ah_PortMapping SET $obj.Status Error
cmclient -u ah_PortMapping SET $obj.X_ADB_ErrorReason "ClientUnknown"
flush_chains "$chain"
exit 0
elif [ $ipcount -gt 1 -a $active -eq 1 ]; then
cmclient -u ah_PortMapping SET $obj.Status Error
cmclient -u ah_PortMapping SET $obj.X_ADB_ErrorReason "ClientDuplicated"
flush_chains "$chain"
exit 0
elif [ $active -eq 0 ]; then
cmclient -u ah_PortMapping SET $obj.Status Error
cmclient -u ah_PortMapping SET $obj.X_ADB_ErrorReason "ClientDisconnected"
flush_chains "$chain"
exit 0
fi
fi
if [ ${#newProtocol} -eq 0 ]; then
cmclient -u ah_PortMapping SET $obj.Status Error_Misconfigured
exit 0
fi
if [ -n "$newX_ADB_AdditionalExternalPort" ]; then
checkAddExternalPortSyntaxOnPort "$newX_ADB_AdditionalExternalPort"
[ "$?" -eq 2 ] && exit 1
fi
cmclient -v checkIp GETO "IP.Interface.+.IPv4Address.[Enable=true].[IPAddress=$newInternalClientIP]"
if [ -n "$checkIp" ]; then
cmclient -u ah_PortMapping SET $obj.Status Error
cmclient -u ah_PortMapping SET $obj.X_ADB_ErrorReason LocalIP
flush_chains "$chain"
fi
if [ "$newAllInterfaces" = "false" -a ${#newInterface} -eq 0 ]; then
cmclient -u ah_PortMapping SET $obj.Status Error_Misconfigured
flush_chains "$chain"
fi
if [ $newX_ADB_ForwardingPolicy -eq -1 ]; then
[ $pm_conflict -eq 0 ] && checkPMconflict
if [ $pm_conflict -eq 1 ]; then
if [ $pm_conflict -eq 1 -a $fail -ne 1 ]; then
cmclient -u ah_PortMapping SET $obj.Status Error
exit 0
fi
fi
fi
fi
if [ "$newEnable" = "false" ]; then
cmclient -u ah_PortMapping SETM "$obj.Status=Disabled	$obj.X_ADB_ErrorReason="
elif [ $fail -eq 1 ]; then
cmclient -u ah_PortMapping SET $obj.Status Error_Misconfigured
fi
[ "$oldEnable" = "true" -o $fail -eq 1 ] && flush_chains "$chain"
if [ "$newEnable" = "false" ] || [ $fail -eq 1 ]; then
exit 0
fi
if [ -n "$newX_ADB_ExternalIPAddress" ]; then
cmclient -v wanips GETV $newX_ADB_ExternalIPAddress".X_ADB_ExternalIPAddress"
cmclient -v mask GETV $newX_ADB_ExternalIPAddress".X_ADB_ExternalIPMask"
help_mask2cidr __mask "$mask"
wanips="$wanips/$__mask"
elif [ "$newAllInterfaces" = "false" ] && [ -n "$newInterface" ]; then
help_lowlayer_ifname_get ifname "$newInterface"
[ -z "$ifname" ] && exit 0
cmclient -v x GETO Device.NAT.InterfaceSetting.[Interface=$newInterface].[Enable=true]
if [ ${#x} -eq 0 ]; then
fail=1
else
[ ${newX_ADB_ForwardingPolicy:--1} -eq -1 ] && cmclient -v wanips GETV $newInterface.IPv4Address.[Enable=true].IPAddress || \
cmclient -v wanips GETV Device.QoS.Classification.[Enable=true].[ForwardingPolicy=$newX_ADB_ForwardingPolicy].DestIP
fi
cmd_if="-i $ifname"
else
if [ ${newX_ADB_ForwardingPolicy:--1} -eq -1 ]; then
fail=1
cmclient -v wanintf GETO Device.IP.Interface.[X_ADB_Upstream=true]
for wanintf in $wanintf; do
cmclient -v x GETO Device.NAT.InterfaceSetting.[Interface=$wanintf].[Enable=true]
[ ${#x} -eq 0 ] && continue
cmclient -v wanip GETV $wanintf.IPv4Address.[Enable=true].IPAddress
wanips="$wanips $wanip"
fail=0
done
else
cmclient -v wanips GETV Device.QoS.Classification.[Enable=true].[ForwardingPolicy=$newX_ADB_ForwardingPolicy].DestIP
[ -n "$wanips" ] || fail=1
fi
cmd_if=""
fi
if [ $fail -eq 1 ]; then
cmclient SETE $obj.Status Error_Misconfigured
flush_chains "$chain"
exit 0
fi
[ -n "$newRemoteHost" ] && cmd_src="-s $newRemoteHost" || cmd_src=""
cmd_mpdst_tcp=""
cmd_mpdst_udp=""
cmd_snat_mpsrc_tcp=""
cmd_snat_mpsrc_udp=""
arr_tcp=""
arr_udp=""
a=","
t_count=0
t_index=0
u_count=0
u_index=0
if [ "$newExternalPort" != "0" ] && [ "$newProtocol" = "UDP" -o "$newProtocol" = "TCP" -o "$newProtocol" = "X_ADB_TCPUDP" ]; then
cmd_pdst="--dport $newExternalPort"
cmd_snat_psrc="--sport $newExternalPort"
if [ "$newExternalPortEndRange" != "0" ]; then
cmd_pdst="$cmd_pdst:$newExternalPortEndRange"
cmd_snat_psrc="$cmd_snat_psrc:$newExternalPortEndRange"
fi
else
cmd_pdst=""
cmd_snat_psrc=""
fi
if [ -n "$newX_ADB_AdditionalExternalPort" ]; then
set -f
IFS=","
set -- $newX_ADB_AdditionalExternalPort
unset IFS
set +f
for x; do
proto=${x%%:*}
if [ -n "$proto" ]; then
if [ "$proto" = "TCP" -o "$proto" = "X_ADB_TCPUDP" ]; then
bb=${x#*:}
cc=`help_tr - : "$bb"`
eval arr_tcp=\${arr_tcp_${t_index}}
if [ -n "$cc" ]; then
p1=${cc#*:}
p2=${cc%:*}
if [ "$p1" = "$p2" ]; then
cc="$p1"
else
t_count=$((t_count + 1))
fi
if [ -n "$x" ]; then
arr_tcp=$arr_tcp$cc$a
else
arr_tcp=$cc$a
fi
fi
eval arr_tcp_${t_index}=$arr_tcp
t_count=$((t_count + 1))
if [ "$t_count" -gt 13 ]; then
t_count=0
t_index=$((t_index + 1))
fi
fi
if [ "$proto" = "UDP" -o "$proto" = "X_ADB_TCPUDP" ]; then
bb=${x#*:}
cc=`help_tr - : "$bb"`
eval arr_udp=\${arr_udp_${u_index}}
if [ -n "$cc" ]; then
p1=${cc#*:}
p2=${cc%:*}
if [ "$p1" = "$p2" ]; then
cc="$p1"
else
u_count=$((u_count + 1))
fi
if [ -n "$x" ]; then
arr_udp=$arr_udp$cc$a
else
arr_udp=$cc$a
fi
fi
eval arr_udp_${u_index}=$arr_udp
u_count=$((u_count + 1))
if [ "$u_count" -gt 13 ]; then
u_count=0
u_index=$((u_index + 1))
fi
fi
fi
done
t_index=0
while [ $t_index != 9999 ]; do
eval arr_tcp=\${arr_tcp_${t_index}}
if [ -n "$arr_tcp" ]; then
arr_tcp=${arr_tcp%,}
eval cmd_mpdst_tcp_${t_index}=\"-p tcp -m multiport --dports $arr_tcp\"
eval cmd_snat_mpsrc_tcp_${t_index}=\"-p tcp -m multiport --sports $arr_tcp\"
t_index=$((t_index + 1))
else
eval cmd_mpdst_tcp_${t_index}=""
t_index=9999
fi
done
u_index=0
while [ $u_index != 9999 ]; do
eval arr_udp=\${arr_udp_${u_index}}
if [ -n "$arr_udp" ]; then
arr_udp=${arr_udp%,}
eval cmd_mpdst_udp_${u_index}=\"-p udp -m multiport --dports $arr_udp\"
eval cmd_snat_mpsrc_udp_${u_index}=\"-p udp -m multiport --sports $arr_udp\"
u_index=$((u_index + 1))
else
eval cmd_mpdst_udp_${u_index}=""
u_index=9999
fi
done
fi
cmd_dst="--to-destination $newInternalClientIP"
cmd_allowdst="-d $newInternalClientIP"
cmd_allowport=""
for wanip in $wanips; do
[ -n "$__mask" ] && __wanip=${wanip%%/$__mask} || __wanip=$wanip
if help_is_valid_ip "$__wanip" ; then
[ "$newX_ADB_Hairpinning" = "true" ] && snat_enable="true"
help_item_add_uniq_in_list snat_cmd_allowdst "$snat_cmd_allowdst" "$wanip"
fi
done
snat_cmd_pdst=$cmd_pdst
snat_cmd_allowdst="${snat_cmd_allowdst:+-d $snat_cmd_allowdst}"
t_index=0
u_index=0
if [ "$newInternalPort" != "0" -a "$newInternalPort" != "" ]; then
snat_cmd_pdst="--dport $newInternalPort"
cmd_dst="$cmd_dst:$newInternalPort"
cmd_allowport="--dport $newInternalPort"
cmd_snat_psrc="--sport $newInternalPort"
while [ $t_index != 9999 ]; do
eval cmd_mpdst_tcp=\${cmd_mpdst_tcp_${t_index}}
eval snat_cmd_mpdst_tcp_${t_index}=\"$cmd_allowdst -p tcp --dport $newInternalPort\"
[ "$cmd_mpdst_tcp" != "" ] && t_index=$((t_index + 1)) || t_index=9999
done
while [ $u_index != 9999 ]; do
eval cmd_mpdst_udp=\${cmd_mpdst_udp_${u_index}}
eval snat_cmd_mpdst_udp_${u_index}=\"$cmd_allowdst -p udp --dport $newInternalPort\"
[ "$cmd_mpdst_udp" != "" ] && u_index=$((u_index + 1)) || u_index=9999
done
else
while [ $t_index != 9999 ]; do
eval cmd_mpdst_tcp=\${cmd_mpdst_tcp_${t_index}}
eval snat_cmd_mpdst_tcp_${t_index}=\"$cmd_allowdst $cmd_mpdst_tcp\"
[ "$cmd_mpdst_tcp" != "" ] && t_index=$((t_index + 1)) || t_index=9999
done
while [ $u_index != 9999 ]; do
eval cmd_mpdst_udp=\${cmd_mpdst_udp_${u_index}}
eval snat_cmd_mpdst_udp_${u_index}=\"$cmd_allowdst $cmd_mpdst_udp\"
[ "$cmd_mpdst_udp" != "" ] && u_index=$((u_index + 1)) || u_index=9999
done
fi
case "$newProtocol" in
TCP)
protos="tcp"
;;
UDP)
protos="udp"
;;
X_ADB_GRE)
protos="gre"
;;
X_ADB_TCPUDP)
protos="tcp udp"
;;
esac
getOrder
cmd_if_snat="-i br+"
cmd_out_snat="-o br+"
if [ "$protos" = "gre" ]; then
if [ ${newX_ADB_ForwardingPolicy:--1} -ne -1 ]; then
help_iptables -t nat -A $chain -m mark --mark 0x$newX_ADB_ForwardingPolicy/0xff -j CONNMARK --set-xmark 0x10/0x10
else
help_iptables -t nat -A $chain $cmd_if $snat_cmd_allowdst $cmd_src -p $protos $cmd_pdst -j CONNMARK --set-xmark 0x10/0x10
fi
fi
for cmd_proto in $protos; do
cmd_proto="-p $cmd_proto"
if [ ${newX_ADB_ForwardingPolicy:--1} -ne -1 ]; then
[ "$cmd_dst" = "${cmd_dst#*:}" ] && dnat_proto= || dnat_proto=$cmd_proto
help_iptables -t nat -A $chain $dnat_proto -m mark --mark 0x$newX_ADB_ForwardingPolicy/0xff -j DNAT $cmd_dst
else
help_iptables -t nat -A $chain $cmd_if $snat_cmd_allowdst $cmd_src $cmd_proto $cmd_pdst -j DNAT $cmd_dst
fi
if [ "$snat_enable" = "true" ]; then
help_iptables -t nat -A ${chain}_SNAT $cmd_if_snat $snat_cmd_allowdst $cmd_src $cmd_proto $cmd_pdst -j DNAT $cmd_dst
help_iptables -t nat -A SNAT_$chain $cmd_allowdst $cmd_proto $snat_cmd_pdst -m emark --mark 0x1/0x1 -m conntrack --ctstate DNAT -j MASQUERADE
fi
done
t_index=0
while [ $t_index != 9999 ]; do
eval snat_cmd_mpdst_tcp=\${snat_cmd_mpdst_tcp_${t_index}}
eval cmd_mpdst_tcp=\${cmd_mpdst_tcp_${t_index}}
if [ -n "$cmd_mpdst_tcp" ]; then
help_iptables -t nat -A $chain $cmd_if $snat_cmd_allowdst  $cmd_src $cmd_mpdst_tcp -j DNAT $cmd_dst
if [ "$snat_enable" = "true" ]; then
help_iptables -t nat -A ${chain}_SNAT $cmd_if_snat $snat_cmd_allowdst $cmd_src $cmd_mpdst_tcp -j DNAT $cmd_dst
help_iptables -t nat -A SNAT_$chain $snat_cmd_mpdst_tcp -m emark --mark 0x1/0x1 -m conntrack --ctstate DNAT -j MASQUERADE
fi
t_index=$((t_index + 1))
else
t_index=9999
fi
done
u_index=0
while [ $u_index != 9999 ]; do
eval snat_cmd_mpdst_udp=\${snat_cmd_mpdst_udp_${u_index}}
eval cmd_mpdst_udp=\${cmd_mpdst_udp_${u_index}}
if [ -n "$cmd_mpdst_udp" ]; then
help_iptables -t nat -A $chain $cmd_if $snat_cmd_allowdst $cmd_src $cmd_mpdst_udp -j DNAT $cmd_dst
if [ "$snat_enable" = "true" ]; then
help_iptables -t nat -A ${chain}_SNAT $cmd_if_snat $snat_cmd_allowdst $cmd_src $cmd_mpdst_udp -j DNAT $cmd_dst
help_iptables -t nat -A SNAT_$chain $snat_cmd_mpdst_udp -m emark --mark 0x1/0x1 -m conntrack --ctstate DNAT -j MASQUERADE
fi
u_index=$((u_index + 1))
else
u_index=9999
fi
done
help_iptables -t nat -D SnatMapping -j "SNAT_$chain"
help_iptables -t nat -D PortMapping -j "${chain}_SNAT"
help_iptables -t nat -D PortMapping -j "$chain"
help_iptables -t nat -I PortMapping $((2 * idx - 1)) -j "$chain"
help_iptables -t nat -I PortMapping $((2 * idx)) -j "${chain}_SNAT"
help_iptables -t nat -I SnatMapping $idx -j "SNAT_$chain"
cmclient -u ah_PortMapping SET $obj.Status Enabled
if [ "$snat_enable" = "true" ]; then
for cmd_proto in $protos; do
help_iptables -t mangle -A "SNAT_$chain" -s $newInternalClientIP $cmd_out_snat -p $cmd_proto $cmd_snat_psrc -m conntrack --ctstate DNAT -j SKIPFC
done
help_iptables -t mangle -A $chain $cmd_if_snat $snat_cmd_allowdst -j EMARK --set-mark 0x1/0x1
fi
cmd_state="-m conntrack --ctstate DNAT"
t_index=0
while [ $t_index != 9999 ]; do
eval cmd_mpdst_tcp=\${cmd_mpdst_tcp_${t_index}}
eval cmd_snat_mpsrc_tcp=\${cmd_snat_mpsrc_tcp_${t_index}}
if [ -n "$cmd_mpdst_tcp" ]; then
for t in filter; do
if [ "$snat_enable" = "true" ]; then
help_iptables -t $t -A $chain $cmd_if_snat $cmd_src $cmd_mpdst_tcp -j ACCEPT
fi
help_iptables -t $t -A $chain $cmd_if $cmd_src $cmd_state $cmd_mpdst_tcp -j ACCEPT
done
t_index=$((t_index + 1))
else
t_index=9999
fi
done
u_index=0
while [ $u_index != 9999 ]; do
eval cmd_mpdst_udp=\${cmd_mpdst_udp_${u_index}}
eval cmd_snat_mpsrc_udp=\${cmd_snat_mpsrc_udp_${u_index}}
if [ -n "$cmd_mpdst_udp" ]; then
for t in filter; do
if [ "$snat_enable" = "true" ]; then
help_iptables -t $t -A $chain $cmd_if_snat $cmd_src $cmd_mpdst_udp -j ACCEPT
fi
help_iptables -t $t -A $chain $cmd_if $cmd_src $cmd_state $cmd_mpdst_udp -j ACCEPT
done
u_index=$((u_index + 1))
else
u_index=9999
fi
done
for cmd_proto in $protos; do
if [ "$snat_enable" = "true" ]; then
help_iptables -t filter -A $chain $cmd_if_snat $cmd_src -p $cmd_proto $cmd_allowdst $cmd_allowport -j ACCEPT
fi
help_iptables -t filter -A $chain $cmd_if $cmd_src $cmd_state -p $cmd_proto $cmd_allowdst $cmd_allowport -j ACCEPT
done
exit 0
