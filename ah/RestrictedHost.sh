#!/bin/sh
AH_NAME="RestrictedHost"
[ "$user" = "${AH_NAME}" ] && exit 0
. /etc/ah/helper_restricted_host.sh
if [ "$1" = "init" ]; then
cmclient -v ena GETV X_ADB_ParentalControl.Enable
[ "$ena" = 'true' ] || exit 0
cmclient -v mac GETV X_ADB_ParentalControl.RestrictedHosts.Host.[Enable=true].[TypeOfRestriction=GUESTNETWORK].MACAddress
for mac in $mac; do
create_rules ADD GUESTNETWORK "$mac" true "1"
done
cmclient -v mac GETV X_ADB_ParentalControl.RestrictedHosts.Host.[Enable=true].[TypeOfRestriction=BLACKLIST].MACAddress
for mac in $mac; do
create_rules ADD BLACKLIST "$mac" true "1"
done
exit 0
fi
if [ "$1" = "enable" ]; then
help_iptables -t mangle -F RO_INPUT
cmclient -v default_restriction GETV X_ADB_ParentalControl.RestrictedHosts.DefaultRestriction
[ ! -f /sbin/cbpc-dnsp ] && \
[ "$default_restriction" = "PARENTALCONTROL" ] && help_iptables -t mangle -A RO -j PC
cmclient DEL X_ADB_Time.Event.[Alias=CheckRestrictedHost]
cmclient DEL X_ADB_Time.Event.[Alias=UpdateRestrictedHost]
cmclient -v index ADDE X_ADB_Time.Event
obj="X_ADB_Time.Event.$index"
cmclient -v act ADDE ${obj}.Action
setm="${obj}.Action.${act}.Path=X_ADB_ParentalControl.RestrictedHosts.Update"
setm="${setm}	${obj}.Action.${act}.Value=true"
setm="${setm}	${obj}.Alias=UpdateRestrictedHost"
setm="${setm}	${obj}.Type=Periodic"
setm="${setm}	${obj}.OccurrenceMinutes=0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,42,44,46,48,50,52,54,56,58"
setm_ena="${obj}.Enable=true"
cmclient -v newVerification GETV X_ADB_ParentalControl.RestrictedHosts.Verification
occ=$(compute_occurence $newVerification)
cmclient -v index ADDE X_ADB_Time.Event
obj="X_ADB_Time.Event.$index"
cmclient -v act ADDE ${obj}.Action
setm="${setm}	${obj}.Action.${act}.Path=X_ADB_ParentalControl.RestrictedHosts.Check"
setm="${setm}	${obj}.Action.${act}.Value=true"
setm="${setm}	${obj}.Alias=CheckRestrictedHost"
setm="${setm}	${obj}.Type=Periodic"
setm="${setm}	${obj}.OccurrenceMinutes=${occ}"
setm_ena="${setm_ena}	${obj}.Enable=true"
cmclient SETEM "${setm}"
cmclient SETM "${setm_ena}"
help_iptables -t mangle -I RO_INPUT 1 -p udp -m udp --dport 53 -j RETURN
help_iptables -t mangle -I RO_INPUT 1 -p udp -m udp --dport 67 -j RETURN
/etc/ah/UpdateRestrictedHost.sh
CHECK_USER="-u RestrictedHostEntry" /etc/ah/CheckRestrictedHost.sh
[ -f /sbin/cbpc-dnsp ] && go='' || go='[Enable=true].'
help_iptables -t filter -F ForwardDeny_TOD
cmclient -v RO GETO X_ADB_ParentalControl.RestrictedHosts.Host.$go
for RO in $RO; do
cmclient -v restriction GETV $RO.TypeOfRestriction
cmclient -v mac GETV $RO.MACAddress
cmclient -v blocked GETV $RO.Blocked
create_rules ADD "$restriction" "$mac" true "$blocked" "1"
done
exit 0
fi
if [ "$1" = "disable" ]; then
cmclient DEL X_ADB_Time.Event.[Alias=CheckRestrictedHost]
cmclient DEL X_ADB_Time.Event.[Alias=UpdateRestrictedHost]
ebtables -t nat -F RO
ebtables -t filter -F RO
ebtables -t filter -F RO_INPUT
help_iptables -t mangle -F RO_INPUT
help_iptables -t mangle -F RO
help_iptables -t filter -F ForwardDeny_TOD
exit 0
fi
if [ "$op" = "s" ]; then
[ "$changedVerification" = "1" ] && \
occ=$(compute_occurence $newVerification) && \
cmclient SET X_ADB_Time.Event.[Alias=CheckRestrictedHost].OccurrenceMinutes $occ
if [ "$changedDefaultRestriction" = "1" ]; then
if [ "$newDefaultRestriction" = "NONE" ]; then
help_iptables -t mangle -D RO -j PC
else
help_iptables -t mangle -A RO -j PC
fi
fi
elif [ "$op" = "g" ]; then
for arg; do
[ "$arg" != "TimeOfDayEnabled" ] && continue
cmclient -v tm_status GETV Time.Status
if [ "$tm_status" = "Synchronized" ]; then
echo true
else
echo false
fi
done
fi
