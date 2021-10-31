#!/bin/sh
AH_NAME="QoSQueue"
[ "$user" = "${AH_NAME}" ] && exit 0
init() {
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh  && help_serialize "${AH_NAME}"
nestingLevel=0
parentDir=/tmp/QoS.Queue
mkdir -p $parentDir
}
buildQueueRED() {
cmclient -v thisREDThreshold GETV "$1.REDThreshold"
cmclient -v thisREDProbability GETV "$1.REDPercentage"
thisREDLimit=62500
if [ $thisREDThreshold -eq 0 ]; then
thisREDThreshold=$((thisREDLimit * 5))
thisREDThreshold=$((thisREDLimit / 100))
else
thisREDThreshold=$((thisREDLimit * thisREDThreshold))
thisREDThreshold=$((thisREDThreshold/100))
fi
thisREDMax=$((thisREDThreshold*5))
if [ $thisREDProbability -eq 0 ]; then
thisREDProbability="0.02"
elif [ $thisREDProbability -eq 100 ]; then
thisREDProbability="1.0"
else
thisREDProbability="0.$thisREDProbability"
fi
thisREDBurst=$((thisREDThreshold*2))
thisREDBurst=$((thisREDBurst+thisREDMax))
thisREDBurst=$((thisREDBurst/3000))
$TC qdisc add dev "$2" parent "$3" red limit $thisREDLimit min $thisREDThreshold max $thisREDMax avpkt 1000 burst $thisREDBurst ecn probability "$thisREDProbability"
}
buildChildren() {
local q=$1 hnd=$2 phnd
cmclient -v queueGroupChildren GETO "Device.QoS.Queue.[X_ADB_Parent=$q].[Enable=true]"
[ "$parentHandle" != "$hnd" ] && echo $parentHandle > $parentDir/"$hnd"".parent"
if [ ${#queueGroupChildren} -eq 0 ]; then
cmclient -v thisRate GETV "$q.ShapingRate"
if [ "$thisRate" != "-1" ]; then
cmclient -v thisBurst GETV "$q.ShapingBurstSize"
[ -n "$thisBurst" ] && [ $thisBurst -gt 0 ] && \
$TC qdisc add dev "$ifName" parent "$hnd" handle "$nextMajor": fbd rate $thisRate burst $thisBurst || \
$TC qdisc add dev "$ifName" parent "$hnd" handle "$nextMajor": fbd rate $thisRate
cmclient -v dropPolicy GETV "$q.DropAlgorithm"
if [ "$dropPolicy" = "DT" ]; then
cmclient -v thisLatency GETV "$q.X_ADB_TargetLatency"
$TC qdisc add dev "$ifName" parent "$nextMajor": lbfifo latency "$thisLatency"
elif [ "$dropPolicy" = "RED" ]; then
buildQueueRED "$q" "$ifName" "$nextMajor:"
fi
cmclient SETE $q.X_ADB_Handle "$ifName $nextMajor:"
nextMajor=$((nextMajor+1))
else
cmclient -v dropPolicy GETV "$q.DropAlgorithm"
if [ "$dropPolicy" = "DT" ]; then
cmclient -v thisLatency GETV "$q.X_ADB_TargetLatency"
$TC qdisc add dev "$ifName" parent "$hnd" lbfifo latency "$thisLatency"
elif [ "$dropPolicy" = "RED" ]; then
buildQueueRED "$q" "$ifName" "$hnd"
fi
cmclient SETE $q.X_ADB_Handle "$ifName $hnd"
fi
else
cmclient -v thisRate GETV "$q.ShapingRate"
if [ "$thisRate" != "-1" ]; then
cmclient -v thisBurst GETV "$q.ShapingBurstSize"
[ -n "$thisBurst" ] -a [ $thisBurst -gt 0 ] && \
$TC qdisc add dev "$ifName" parent "$hnd" handle "$nextMajor": fbd rate $thisRate burst $thisBurst || \
$TC qdisc add dev "$ifName" parent "$hnd" handle "$nextMajor": fbd rate $thisRate
nextMajor="$((nextMajor+1))" buildQueue "$q" "$nextMajor:"
cmclient SETE $q.X_ADB_Handle "$ifName $nextMajor:"
else
buildQueue "$q" "$hnd"
cmclient SETE $q.X_ADB_Handle "$ifName $hnd"
fi
fi
cmclient -v theseTrafficClasses GETV "$q.TrafficClasses"
IFS=','
set -- $theseTrafficClasses
unset IFS
for i; do
$TC filter add dev "$ifName" protocol all parent "${hnd%%:*}": prio 1 handle "$((i*16777216))/0xff000000" fw flowid "$hnd"
read phnd < $parentDir/"$hnd.parent"
while [ "$phnd" != "1:" -a  -n "$phnd" -a  "$phnd" != "$hnd" -a -f "$parentDir/$phnd.parent" ]; do
newprecHandle=${phnd%%:*}
$TC filter add dev "$ifName" protocol all parent "$newprecHandle"":" prio 1 handle "$((i*16777216))/0xff000000" fw flowid "$phnd"
read phnd < $parentDir/"$phnd.parent"
done
done
}
update_min_max_cnt() {
local p
cmclient -v p GETV "$1.Precedence"
[ $p -lt $minPrec ] && minPrec=$p
[ $p -gt $maxPrec ] && maxPrec=$p
if ! help_is_in_list "$precList" $p; then
precCount=$((precCount+1))
precList="$precList,$p"
fi
}
buildQueue() {
local parentHandle="$2" parent=$1 thisIfQueues="" allIfQueues prec1 prec2
[ ${#parent} -gt 0 ] && \
cmclient SETE "Device.QoS.Queue.[Interface!$interface].[X_ADB_Parent=$parent].[Enable=true].Interface" "$interface"
for a in $interface $ip_interfaces; do
cmclient -v a GETO "Device.QoS.Queue.[Interface=$a].[X_ADB_Parent=$1].[Enable=true]"
thisIfQueues="$thisIfQueues $a"
done
cmclient -v allIfQueues GETO "Device.QoS.Queue.[AllInterfaces=true].[X_ADB_Parent=$parent].[Enable=true]"
local minPrec=65535 maxPrec=0 precCount=0 precList=""
for queue in $thisIfQueues $allIfQueues; do
if [ "$queue" != "$objectDeleted" ]; then
[ "$newEnable" = "true" ] && cmclient SETE "$queue".Status Enabled
update_min_max_cnt $queue
fi
done
if [ $precCount -gt 1 ]; then
$TC qdisc add dev "$ifName" parent "$parentHandle" handle "$nextMajor" sp queues "$precCount"
local precHandle="$nextMajor:"
nextMajor="$((${nextMajor%:*}+1))"
else
local precHandle="$parentHandle"
fi
nestingLevel=$((nestingLevel+1))
local minorCount=0 thisPrec=$minPrec thisPrecQueues thisSchedulerMajor thisSchedulerMinor wrr_nbr wfq_nbr
while [ $thisPrec -le $maxPrec ]; do
[ $precCount -eq 1 ] && minorCount="" || minorCount=$((minorCount+1))
unset b
for a in $interface $ip_interfaces; do
cmclient -v a GETO "Device.QoS.Queue.[Interface=$a].[Precedence=$thisPrec].[X_ADB_Parent=$parent].[Enable=true]"
[ ${#a} -eq 0 ] && continue
b="$b${b:+ }$a"
[ ${#parent} -gt 0 ] && break
done
thisPrecQueues=$b
[ ${#thisPrecQueues} -eq 0 ] && \
cmclient -v thisPrecQueues GETO "Device.QoS.Queue.[AllInterfaces=true].[Precedence=$thisPrec].[X_ADB_Parent=$1].[Enable=true]"
if [ ${#thisPrecQueues} -eq 0 ]; then
thisPrec=$((thisPrec+1))
[ $minorCount -gt 0 ] && minorCount=$((minorCount-1))
continue
fi
for queue in $thisPrecQueues; do
cmclient -v queueGroupAlgo GETV "$queue.SchedulerAlgorithm"
done
thisSchedulerMinor=0
if [ "$queueGroupAlgo" = "SP" ]; then
buildChildren "$thisPrecQueues" "$precHandle$minorCount"
elif [ "$queueGroupAlgo" = "WRR" ]; then
buf="$TC qdisc add dev $ifName parent $precHandle$minorCount handle $nextMajor: wrr weights"
wrr_nbr=0
for queue in $thisPrecQueues; do
cmclient -v thisWeight GETV "$queue.Weight"
buf="$buf $thisWeight"
wrr_nbr=$((wrr_nbr+1))
done
[ $wrr_nbr -gt 1 ] && $buf || nextMajor=$((nextMajor-1))
thisSchedulerMajor=$nextMajor
nextMajor=$((nextMajor+1))
for a in $thisPrecQueues; do
thisSchedulerMinor=$((thisSchedulerMinor+1))
buildChildren "$a" "$thisSchedulerMajor:$thisSchedulerMinor"
done
elif [ "$queueGroupAlgo" = "WFQ" ]; then
buf="$TC qdisc add dev $ifName parent $precHandle$minorCount handle $nextMajor: wfq weights"
wfq_nbr=0
for queue in $thisPrecQueues; do
cmclient -v thisWeight GETV "$queue.Weight"
buf="$buf $thisWeight"
wfq_nbr=$((wfq_nbr+1))
done
[ $wfq_nbr -gt 1 ] && $buf || nextMajor=$((nextMajor-1))
thisSchedulerMajor=$nextMajor
nextMajor=$((nextMajor+1))
for a in $thisPrecQueues; do
thisSchedulerMinor=$((thisSchedulerMinor+1))
buildChildren "$a" "$thisSchedulerMajor:$thisSchedulerMinor"
done
fi
thisPrec=$((thisPrec+1))
done
}
get_phy_obj() {
local _o
case $2 in
atm*)
cmclient -v _o GETO Device.ATM.Link.*.[Name="$2"]
;;
ptm*)
cmclient -v _o GETO Device.PTM.Link.*.[Name="$2"]
;;
br*)
cmclient -v _o GETO Device.Bridging.Bridge.**.[Name="$2"]
;;
wl*)
cmclient -v _o GETO Device.WiFi.SSID.*.[Name="$2"]
;;
dsl*)
cmclient -v _o GETO Device.DSL.Line.*.[Name="$2"]
;;
eth*)
cmclient -v _o GETO Device.Ethernet.Interface.*.[Name="$2"]
;;
esac
eval $1='$_o'
}
check_old_interface() {
local newIf="$1" oldIfName
[ "$newIf" = "dsl0" ] || return 0
cmclient -v oldIfName GETV "${2}.Name"
case $oldIfName in
atm*|ptm*)
return 1
;;
*)
return 0
;;
esac
}
get_lower_phy_obj() {
local chan_layer line_layer
if [ "${interface%.*}" = "Device.IP.Interface" ]; then
help_lowest_ifname_get ifName $interface
get_phy_obj interface $ifName
fi
case $ifName in
ptm*)
cmclient -v chan_layer GETV "${interface}.LowerLayers"
cmclient -v line_layer GETV "${chan_layer}.LowerLayers"
eval $1='$line_layer'
;;
*)
eval $1=$interface
;;
esac
}
setHwBackend() {
local hwQoS _interface=$interface
get_lower_phy_obj _interface $interface
cmclient -v hwQoS GETV "${_interface}.X_ADB_HwBasedQos.[Capable=true].Enable"
if [ -z "$hwQoS" -o "$hwQoS" = "false" ]; then
$TC hw disable dev "$ifName"
fi
}
update_control_tc() {
local defaultTcUser="$user"
[ "$defaultTcUser" = "QoSControlClassification" ] || defaultTcUser="conf_up"
cmclient -u "${defaultTcUser}" SET "QoS.X_ADB_DefaultClassification.[Enable=true].Enable" "true"
}
buildQueueTree() {
local phy
update_control_tc
. /etc/ah/helper_tc.sh
TC="help_tc"
interface="$1"
cmclient -v ifName GETV "${interface}.Name"
setHwBackend
help_ip_interface_get ip_interfaces $interface
[ -d /sys/class/net/"$ifName" ] || return
$TC qdisc del dev "$ifName" root
if [ "$ifName" = "dsl0" ]; then
cmclient -v ATMInterfaces GETV "Device.**.[Name>atm].[Status=Up].Name"
cmclient -v PTMInterfaces GETV "Device.**.[Name>ptm].[Status=Up].Name"
for i in $ATMInterfaces $PTMInterfaces; do
read _ pfifoRoot _ <<-EOF
`tc qdisc show dev "$i"`
EOF
[ "$pfifoRoot" = "pfifo_fast" ] && $TC qdisc add dev "$i" root fbd
done
fi
anyRemainingQueue=0
for a in $interface $ip_interfaces; do
cmclient -v a GETO "Device.QoS.Queue.[Interface=$a].[Enable=true]"
for a in $a; do
[ "$a" != "$objectDeleted" ] && anyRemainingQueue=$((anyRemainingQueue+1))
done
done
cmclient -v a GETO "Device.QoS.Queue.[AllInterfaces=true].[Enable=true]"
for a in $a; do
[ "$a" != "$objectDeleted" ] && anyRemainingQueue=$((anyRemainingQueue+1))
done
cmclient -v rootShaper GETO "Device.QoS.Shaper.[Interface=$interface].[Enable=true]"
if [ -n "$rootShaper" ] && [ "$rootShaper" != "$objectDeleted" ]; then
cmclient -v rootShaperRate GETV "$rootShaper.ShapingRate"
cmclient -v rootShaperBurst GETV "$rootShaper.ShapingBurstSize"
[ -n "$rootShaperBurst" ] && rootShaperBurst=" burst $rootShaperBurst"
if [ "$rootShaperRate" != "-1" ]; then
$TC qdisc add dev "$ifName" root handle 1: fbd rate "$rootShaperRate" $rootShaperBurst
[ $anyRemainingQueue -eq 0 ] && $TC qdisc add dev "$ifName" parent 1: pfifo limit 75
else
$TC qdisc add dev "$ifName" root handle 1: fbd $rootShaperBurst
fi
else
[ $anyRemainingQueue -gt 0 ] && $TC qdisc add dev "$ifName" root handle 1: fbd
fi
[ $anyRemainingQueue -gt 0 ] && nextMajor="2" buildQueue "" "1:"
}
update_multi_status() {
local _intf=$1 _obj _enable intf_obj parent_obj
cmclient -v _obj GETO "QoS.Queue.[Interface=$obj].[AllInterfaces=false]"
for _obj in $_obj; do
cmclient -v _enable GETV $_obj.Enable
if [ "$_enable" = "true" ]; then
cmclient -v parent_obj GETO "%($_obj.X_ADB_Parent)"
while [ -n "$parent_obj" ]; do
cmclient -v _enable GETV $parent_obj.Enable
if [ "$_enable" = "false" ]; then
cmclient SETE $_obj.Status "Error"
continue 2
fi
cmclient -v parent_obj GETO "%($parent_obj.X_ADB_Parent)"
done
cmclient -v intf_obj GETO "%($_obj.Interface)"
[ -z "$intf_obj" ] && \
cmclient SETE $_obj.Status "Error_Misconfigured" || \
cmclient SETE $_obj.Status "Enabled"
else
cmclient SETE $_obj.Status "Disabled"
fi
done
cmclient -v _obj GETO "QoS.Queue.[Interface=$obj].[AllInterfaces=true]"
for _obj in $_obj; do
cmclient -v _enable GETV $_obj.Enable
[ "$_enable" = "true" ] && cmclient SETE $_obj.Status "Enabled" || cmclient SETE $_obj.Status "Disabled"
done
}
parent=""
case "$obj" in
"Device.QoS.Queue"* | "Device.QoS.Shaper"*)
interface="$newInterface"
[ "$changedInterface" = "1" ] && old_interface="$oldInterface"
allInterfaces="$newAllInterfaces"
[ "$changedAllInterfaces" = "1" ] && old_allInterfaces="$oldAllInterfaces"
parent="$newX_ADB_Parent"
[ -n "$parent" ] && cmclient -v parentInterface GETV "$parent.Interface"
;;
*".X_ADB_HwBasedQos")
[ "$changedEnable" = "1" ] || exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/target.sh
init
buildQueueTree "${obj%.X_ADB_HwBasedQos*}"
update_multi_status "${obj%.X_ADB_HwBasedQos*}"
exit 0
;;
*)
[ "$changedStatus" = "1" -a "$newStatus" = "Up" ] || exit 0
cmclient -v i GETO QoS.Queue.[Interface=$obj].[X_ADB_Parent=].[Enable=true].[AllInterfaces=false]
[ ${#i} -eq 0 ] && cmclient -v i GETO QoS.Queue.[X_ADB_Parent=].[Enable=true].[AllInterfaces=true]
[ ${#i} -eq 0 ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/target.sh
init
buildQueueTree "$obj"
update_multi_status "$obj"
exit 0
;;
esac
[ "$setEnable" = "0" -a "$newEnable" = "false" ] && exit 0
[ "$changedInterface" = "0" -a "$changedAllInterfaces" = "0" -a "$changedX_ADB_Parent" = "0" -a "$setEnable" = "0" -a "$op" != "d" ] && \
exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/target.sh
init
if [ "$op" = "d" ]; then
objectDeleted="$obj"
cmclient -v objs GETO "Device.**.[Queue=$objectDeleted]"
for i in $objs; do
cmclient SET "$i.Queue" ""
done
cmclient -v objs GETO "Device.**.[DefaultQueue=$objectDeleted]"
for i in $objs; do
cmclient SET "$i.DefaultQueue" ""
done
else
if [ "$newEnable" = "true" ]; then
[ -n "$interface" ] && cmclient -v intf_obj GETO $interface
[ -n "$parent" ] && cmclient -v parent_obj GETO $parent
[ "$allInterfaces" != "true" -a -z "$intf_obj" -a -z "$parent_obj" ] && \
cmclient SETE $obj.Status "Error_Misconfigured" || \
cmclient SETE $obj.Status "Enabled"
case "$obj" in
"Device.QoS.Queue"*)
cmclient -v __sch_algo GETV "${obj}.SchedulerAlgorithm"
if [ "$__sch_algo" != "SP" ]; then
cmclient -v __Weight GETV "${obj}.Weight"
if [ "$__Weight" = 0 ]; then
cmclient SETE $obj.Status "Error_Misconfigured"
exit 1
fi
fi
cmclient -v __Precedence GETV "${obj}.Precedence"
cmclient -v __Parent GETV "${obj}.X_ADB_Parent"
case "$__sch_algo" in
"WRR"|"WFQ")
cmclient -v __qp GETO "Device.QoS.Queue.[Enable=true].[X_ADB_Parent=${__Parent}].[Precedence=${__Precedence}].[SchedulerAlgorithm!$__sch_algo]"
;;
"SP")
cmclient -v __qp GETO "Device.QoS.Queue.[Enable=true].[X_ADB_Parent=${__Parent}].[Precedence=${__Precedence}]"
;;
*)
__qp=""
;;
esac
for q in $__qp; do
if [ "$q" != "$obj" ]; then
cmclient SETE $obj.Status "Error_Misconfigured"
exit 1
fi
done
esac
else
cmclient SETE $obj.Status "Disabled"
fi
if [ -n "$parentInterface" -a "$newInterface" != "$parentInterface" ]; then
cmclient SETE $obj.Interface "${parentInterface}"
interface=$parentInterface
fi
fi
if [ -n "$allInterfaces" ] && [ "$allInterfaces" = "true" -o "$old_allInterfaces" = "true" ]; then
for i in Ethernet.Interface DSL.Line WiFi.SSID ATM.Link PTM.Link PPP.Interface \
"Bridging.Bridge.[Name>br]" X_ADB_VPN.Client.L2TP; do
cmclient -v i GETO "Device.$i"
for j in $i; do
buildQueueTree "$j"
done
done
else
buildQueueTree "$interface"
[ ${#old_interface} -gt 0 ] && check_old_interface "$ifName" "$old_interface" && buildQueueTree "$old_interface"
fi
exit 0
