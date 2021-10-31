#!/bin/sh
command -v help_iptables >/dev/null || . /etc/ah/helper_firewall.sh
lan_only() {
raw_mac=$1
arl_action=$2
ipt_action=$3
mac=$4
hw_action=$5
echo $raw_mac 0 1 100 $arl_action > /proc/hwswitch/default/arl
cmclient SET Bridging.X_ADB_HWSwitch.$hw_action RO_$raw_mac
ebtables -t filter -D RO_INPUT -s "$mac" -j DROP
cmclient -v wan GETO Device.Routing.Router.**.IPv4Forwarding.[DestIPAddress=].[Status=Enabled]
cmclient -v interface GETV $wan".Interface"
cmclient -v lowlayer GETV $interface".LowerLayers"
cmclient -v name_eth GETV $lowlayer".Name"
if [ "$ipt_action" = "-D" ]; then
iptables-save -t filter | grep -q -i "\-A ForwardDeny_TOD \-o $name_eth \-m mac \-\-mac\-source $mac -j DROP" || return
fi
help_iptables "$ipt_action" ForwardDeny_TOD -o $name_eth  -m mac --mac-source $mac -j DROP
}
del_rule_from_iptables() {
mac=$1
iptables-save -t mangle | grep -q -i "\-A RO \-m mac \-\-mac\-source $mac \-j PC" || return
help_iptables -t mangle -D RO -m mac --mac-source "$mac" -j PC
}
create_rules() {
action=$1
type=$2
mac=$3
enabled=$4
block=$5
changed_blocked=$6
raw_mac=$(echo $mac | tr -d :)
if [ ! -f /sbin/cbpc-dnsp ]; then
[ "$type" = "TIMEOFDAY" -a "$block" = "false" ] && return
[ "$enabled" = "false" ] && return
fi
if [ "$action" = "ADD" ]; then
ipt_action="-A"
arl_action=1
hw_action="DisableRequest"
else
ipt_action="-D"
arl_action=0
hw_action="EnableRequest"
fi
case "$type" in
BLACKLIST)
echo $raw_mac 0 1 100 $arl_action > /proc/hwswitch/default/arl
cmclient SET Bridging.X_ADB_HWSwitch.$hw_action RO_$raw_mac
ebtables -t filter $ipt_action RO_INPUT -s "$mac" -j DROP
ebtables -t nat $ipt_action RO -s "$mac" -j DROP
ebtables -t nat $ipt_action RO -d "$mac" -j DROP
;;
GUESTNETWORK)
echo $raw_mac 0 1 100 $arl_action > /proc/hwswitch/default/arl
cmclient SET Bridging.X_ADB_HWSwitch.$hw_action RO_$raw_mac
ebtables -t filter $ipt_action RO_INPUT -s "$mac" -p IPv4 --ip-protocol 2  -j DROP
ebtables -t filter $ipt_action RO -s "$mac" -j DROP
ebtables -t filter $ipt_action RO -d "$mac" -j DROP
help_iptables -t mangle $ipt_action RO_INPUT -m mac --mac-source "$mac" -j DROP
;;
TIMEOFDAY)
if [ -f /sbin/cbpc-dnsp ]; then
if [ "$enabled" = "true" ]; then
if [ "$block" = "false" ]; then
del_rule_from_iptables $mac
help_iptables -t mangle -A RO -m mac --mac-source "$mac" -j PC
lan_only $raw_mac 0 -D $mac EnableRequest
fi
if [ "$block" = "true" ]; then
del_rule_from_iptables $mac
lan_only $raw_mac 1 -A $mac DisableRequest
fi
else
del_rule_from_iptables $mac
help_iptables -t mangle -A RO -m mac --mac-source "$mac" -j PC
lan_only $raw_mac 0 -D $mac EnableRequest
fi
else
help_iptables -t mangle $ipt_action RO -m mac --mac-source "$mac" -j PC
fi
;;
esac
}
lookup() {
needle=$1
shift
for arg in $*; do
if [ "$needle" = "$arg" ]; then
return 0
fi
done
return 1
}
compute_occurence() {
verification=$(($1/60))
if [ $verification -lt 2 ]; then
verification=2
fi
incr=$verification
occurence=0
while [ "$verification" -lt 60 ]; do
occurence="$occurence,$verification"
verification=$((verification+$incr))
done
for secs in $(cmclient GETV X_ADB_ParentalControl.RestrictedHosts.TimeOfDayProfile.TimeOfDay.UsagePeriodBegin; \
cmclient GETV X_ADB_ParentalControl.RestrictedHosts.TimeOfDayProfile.TimeOfDay.UsagePeriodEnd); do
min=$(( ($secs/60) %60 ))
tok=$min
secs=$(( $secs % 60 ))
[ "$secs" != "0" ] && tok="$min:$secs"
if [ "$secs" != "0" -o $((min%$incr)) != "0" ]; then
lookup $tok $added_occurrence && continue
occurence="$occurence,$tok"
added_occurrence="$added_occurrence $tok"
fi
done
echo $occurence
}
