#!/bin/sh
AH_NAME="QoSPolicer"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
. /etc/ah/helper_firewall.sh
if [ "$1" = init ]; then
for x in mangle filter; do
help_iptables -t $x
done
cmclient -v policers GETO Device.QoS.Policer.[Enable=true]
for i in $policers; do
cmclient SET -u "${tmpiptablesprefix##*/}" $i.Enable true >/dev/null
done
exit 0
fi
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize > /dev/null
service_get() {
local par="$1" redOffset=3 yellowOffset=3 ca
if [ "$meter" = "SimpleTokenBucket" ] && \
[ "$par" = "PartiallyConformingCountedPackets" -o "$par" = "PartiallyConformingCountedBytes" ]; then
echo 0
return 0
else
cmclient -v ca GETV "${obj}.NonConformingAction"
case "$ca" in
[0-9]*:[0-9]*)
yellowOffset=$((yellowOffset + 3))
;;
Drop|:[0-9]*|[0-9]*)
yellowOffset=$((yellowOffset + 2))
;;
Null)
yellowOffset=$((yellowOffset + 1))
;;
esac
fi
greenOffset=$yellowOffset
if [ "$meter" != "SimpleTokenBucket" ]; then
cmclient -v ca GETV "${obj}.PartialConformingAction"
case "$ca" in
[0-9]*:[0-9]*)
greenOffset=$((greenOffset + 3))
;;
Drop|:[0-9]*|[0-9]*)
greenOffset=$((greenOffset + 2))
;;
Null)
greenOffset=$((greenOffset + 1))
;;
esac
fi
if [ "$par" = "NonConformingCountedPackets" ]; then
iptables -xvt mangle -L "$obj" "$redOffset" | tr -s " " | cut -f2 -d' '
elif [ "$par" = "NonConformingCountedBytes" ]; then
iptables -xvt mangle -L "$obj" "$redOffset" | tr -s " " | cut -f3 -d' '
elif [ "$par" = "PartiallyConformingCountedPackets" ]; then
iptables -xvt mangle -L "$obj" "$yellowOffset" | tr -s " " | cut -f2 -d' '
elif [ "$par" = "PartiallyConformingCountedBytes" ]; then
iptables -xvt mangle -L "$obj" "$yellowOffset" | tr -s " " | cut -f3 -d' '
elif [ "$par" = "ConformingCountedPackets" ]; then
iptables -xvt mangle -L "$obj" "$greenOffset" | tr -s " " | cut -f2 -d' '
elif [ "$par" = "ConformingCountedBytes" ]; then
iptables -xvt mangle -L "$obj" "$greenOffset" | tr -s " " | cut -f3 -d' '
elif [ "$par" = "TotalCountedPackets" ]; then
a=`iptables -xvt mangle -L "$obj" "$redOffset" | tr -s " " | cut -f2 -d' ' | tr -d "\n"`
if [ $meter != "SimpleTokenBucket" ]; then
b=`iptables -xvt mangle -L "$obj" "$yellowOffset" | tr -s " " | cut -f2 -d' ' | tr -d "\n"`
else
b=0
fi
c=`iptables -xvt mangle -L "$obj" "$greenOffset" | tr -s " " | cut -f2 -d' ' | tr -d "\n"`
echo $((a + b + c))
elif [ "$par" = "TotalCountedBytes" ]; then
a=`iptables -xvt mangle -L "$obj" "$redOffset" | tr -s " " | cut -f3 -d' ' | tr -d "\n"`
if [ $meter != "SimpleTokenBucket" ]; then
b=`iptables -xvt mangle -L "$obj" "$yellowOffset" | tr -s " " | cut -f3 -d' ' | tr -d "\n"`
else
b=0
fi
c=`iptables -xvt mangle -L "$obj" "$greenOffset" | tr -s " " | cut -f3 -d' ' | tr -d "\n"`
echo $((a + b + c))
fi
}
case "$op" in
d)
echo "### $AH_NAME: DEL OPERATION $* ###"
cmclient -v pol GETO Device.**.[Policer="$obj"]
for i in $pol; do
cmclient SET "$i".Policer ""
done
cmclient -v pol GETO Device.**.[DefaultPolicer="$obj"]
for i in $pol; do
cmclient SET "$i".Policer ""
done
help_iptables -t mangle -F "$obj"
help_iptables -t mangle -X "$obj"
;;
g)
cmclient -v meter GETV $obj.MeterType
cmclient -v status GETV $obj.Status
for arg # Arg list as separate words
do
if [ "$status" != "Enabled" ]; then
echo 0
else
service_get "$arg"
fi
done
;;
s)
refresh=0
for i in CommittedRate CommittedBurstSize ExcessBurstSize PeakRate PeakBurstSize \
MeterType ConformingAction PartialConformingAction NonConformingAction; do
if eval [ \$changed${i} -eq 1 ]; then
refresh=1
break
fi
done
if [ $setEnable -eq 0 -a $refresh -eq 0 ]; then exit 0; fi
help_iptables -t mangle -F "$obj"
help_iptables -t mangle -N "$obj"
if [ "$newEnable" = "false" ]; then
cmclient SET -u "${AH_NAME}${obj}" "$obj".Status Disabled >/dev/null
exit 0
else
error=0
[ "$newCommittedRate" = 0 -o "$newCommittedBurstSize" = 0 ] && error=1
case "$newMeterType" in
SingleRateThreeColor)
[ "$newExcessBurstSize" = 0 ] && error=1
;;
TwoRateThreeColor)
[ "$newPeakRate" = 0 -o "$newPeakBurstSize" = 0 ] && error=1
;;
esac
if [ $error -eq 1 ]; then
cmclient SET -u "${AH_NAME}${obj}" "$obj".Status Error >/dev/null
exit 0
else
cmclient SET -u "${AH_NAME}${obj}" "$obj".Status Enabled >/dev/null
fi
fi
greenMark=0x100000
yellowMark=0x080000
redMark=0x180000
policerMask=0x180000	# Bits 20 to 19
help_iptables -t mangle -N "$obj"
case "$newNonConformingAction" in
Null)
redRule1=""
;;
Drop)
redRule1="help_iptables -t mangle -A $obj -m mark --mark $redMark/$policerMask -j DROP"
;;
[0-9]*:[0-9]*)
redRule1="help_iptables -t mangle -A $obj -m mark --mark $redMark/$policerMask -j DSCP --set-dscp ${newNonConformingAction%:*}"
redRule2="help_iptables -t mangle -A $obj -m mark --mark $redMark/$policerMask -j MARK --set-mark $(((${newNonConformingAction##*:}) * 2097152))/0x00E00000"
;;
:[0-9]*)
redRule1="help_iptables -t mangle -A $obj -m mark --mark $redMark/$policerMask -j MARK --set-mark $(((${newNonConformingAction##*:}) * 2097152))/0x00E00000"
;;
[0-9]*)
redRule1="help_iptables -t mangle -A $obj -m mark --mark $redMark/$policerMask -j DSCP --set-dscp ${newNonConformingAction%:*}"
;;
esac
redReturn="help_iptables -t mangle -A $obj -m mark --mark $redMark/$policerMask -j RETURN"
case "$newPartialConformingAction" in
Null)
yellowRule1=""
;;
Drop)
yellowRule1="help_iptables -t mangle -A $obj -m mark --mark $yellowMark/$policerMask -j DROP"
;;
[0-9]*:[0-9]*)
yellowRule1="help_iptables -t mangle -A $obj -m mark --mark $yellowMark/$policerMask -j DSCP --set-dscp ${newPartialConformingAction%:*}"
yellowRule2="help_iptables -t mangle -A $obj -m mark --mark $yellowMark/$policerMask -j MARK --set-mark $(((${newPartialConformingAction##*:}) * 2097152))/0x00E00000"
;;
:[0-9]*)
yellowRule1="help_iptables -t mangle -A $obj -m mark --mark $yellowMark/$policerMask -j MARK --set-mark $(((${newPartialConformingAction##*:}) * 2097152))/0x00E00000"
;;
[0-9]*)
yellowRule1="help_iptables -t mangle -A $obj -m mark --mark $yellowMark/$policerMask -j DSCP --set-dscp ${newPartialConformingAction%:*}"
;;
esac
yellowReturn="help_iptables -t mangle -A $obj -m mark --mark $yellowMark/$policerMask -j RETURN"
case "$newConformingAction" in
Null)
greenRule1=""
;;
Drop)
greenRule1="help_iptables -t mangle -A $obj -j DROP"
;;
[0-9]*:[0-9]*)
greenRule1="help_iptables -t mangle -A $obj -j DSCP --set-dscp ${newConformingAction%:*}"
greenRule2="help_iptables -t mangle -A $obj -j MARK --set-mark $(((${newConformingAction##*:}) * 2097152))/0x00E00000"
;;
:[0-9]*)
greenRule1="help_iptables -t mangle -A $obj -j MARK --set-mark $(((${newConformingAction##*:}) * 2097152))/0x00E00000"
;;
[0-9]*)
greenRule1="help_iptables -t mangle -A $obj -j DSCP --set-dscp ${newConformingAction%:*}"
;;
esac
[ -e /proc/net/yatta ] && skipFC="help_iptables -t mangle -A $obj -j SKIPFC"
[ -x /bin/fcctl ] && skipLog="help_iptables -t mangle -A $obj -j SKIPLOG"
greenReturn="help_iptables -t mangle -A $obj -j RETURN"
[ -n "$skipFC" ] && $skipFC
[ -n "$skipLog" ] && $skipLog
if [ "$newMeterType" = "SimpleTokenBucket" ]; then
help_iptables -t mangle -A "$obj" -j POLICER --stb --rate1 "$((newCommittedRate/8))" --burst1 "$newCommittedBurstSize" --m-red $redMark/$policerMask --m-green $greenMark/$policerMask
$redRule1
$redRule2
$redReturn
$greenRule1
$greenRule2
$greenReturn
else
if [ "$newMeterType" = "SingleRateThreeColor" ]; then
tcMeter="--srtc"
newBurst2="$newExcessBurstSize"
else
tcMeter="--trtc"
newBurst2="$newPeakBurstSize"
newRate2="$newPeakRate"
fi
help_iptables -t mangle -A "$obj" -j POLICER $tcMeter --rate1 "$((newCommittedRate/8))" --burst1 "$newCommittedBurstSize" --rate2 "$((newRate2/8))" --burst2 "$newBurst2" --m-red $redMark/$policerMask --m-green $greenMark/$policerMask --m-yellow $yellowMark/$policerMask
$redRule1
$redRule2
$redReturn
$yellowRule1
$yellowRule2
$yellowReturn
$greenRule1
$greenRule2
$greenReturn
fi
;;
esac
exit 0
