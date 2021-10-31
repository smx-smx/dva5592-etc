#!/bin/sh
. /etc/ah/VoIPCommon.sh
[ "$user" = "stats" ] && exit 0
[ "$user" = "voipline" ] && exit 0
if [ "$op" = "s"  -a "$changedPacketizationPeriod" = "1" ]; then
cmclient -v codec GETV ${obj}.Codec
cmclient -v cap GETO Services.VoiceService.1.Capabilities.Codecs.[Codec=${codec}]
[ "$cap" = "" ] && exit 8
cmclient -v pktper GETV ${cap}.PacketizationPeriod
[ "$pktper" = "" ] && exit 8
case ,"${pktper}", in
*,"${newPacketizationPeriod}",* )
;;
*)
exit 8
;;
esac
fi
AH_NAME="VoIPLine"
serviceId="${obj##*.VoiceService.}"
serviceId="${serviceId%%.*}"
VOIP_SERVICE="Services.VoiceService.${serviceId}"
VOIP_PROFILE="${VOIP_SERVICE}.VoiceProfile"
if [ "$op" = "r" ]; then
profileId="$2"
vlineId="$3"
else
profileId="${obj##*.VoiceProfile.}"
profileId="${profileId%%.*}"
vlineId="${obj##*.Line.}"
vlineId="${vlineId%%.*}"
fi
tabIdx=""
lineobj=""
service_reload_line() {
: > /etc/voip/reload
}
service_reload_line_now() {
: > /etc/voip/reload_now
}
map_obj() {
local par="$1"
tabIdx=""
lineobj="$1"
lineobj="${lineobj#*Line.}"
sublineobj=${lineobj#*.}
if [ "$lineobj"	= "$sublineobj" ]; then
lineobj="Line"
else
lineobj="${sublineobj%%.*}"
fi
case "$lineobj" in
"SIP" )
tabIdx=""
idsubs="${par##*SIP.EventSubscribe.}"
if [ "$par" != "$idsubs" ]; then
tabIdx="$idsubs"
lineobj="SIP.EventSubscribe"
fi
;;
"Codec" )
codecObj="${par##*.Codec.}"
codecObj=${codecObj%%.*}
case "$codecObj" in
"List" )
tabIdx="${par##*.Codec.List.}";;
"X_ADB_CodecFeatures" )
tabIdx="";;
* )
;;
esac;;
* )
;;
esac
}
service_add() {
local num=0 total_num_lines=0 numOfLines="" maxLines="" scodecs="" cparams="" sipevents="" event="" subscr_id="" list_idx=""
map_obj "$obj"
case "$lineobj" in
"Line")
cmclient -v numOfLines GETV ${VOIP_PROFILE}.NumberOfLines
for num in $numOfLines; do
total_num_lines=$((total_num_lines+num))
done
cmclient -v maxLines GETV ${VOIP_SERVICE}.Capabilities.MaxLineCount
if [ $total_num_lines -gt $maxLines ]; then
cmclient -u voipline DEL "$obj"
return 4
fi
cmclient -v scodecs GETO ${VOIP_SERVICE}.Capabilities.Codecs
for scodecs in $scodecs
do
params=""
sci="${scodecs##*${VOIP_SERVICE}.Capabilities.Codecs.}"
cmclient -u voipline -v list_idx ADD ${obj}.Codec.List
cmclient -v cparams GET ${VOIP_SERVICE}.Capabilities.Codecs.$sci.
for cparams in $cparams
do
set -f
IFS=";"
set -- $cparams
unset IFS
set +f
paramName=$1
paramVal=$2
paramName="${paramName##*.}"
if [ "$paramName" = "PacketizationPeriod" ]; then
paramVal="${paramVal##*,}"
fi
params="$params""${obj}.Codec.List.$list_idx.$paramName=$paramVal	"
done
cmclient -u voipline SETM "$params"
done
cmclient -v sipevents GETO ${VOIP_PROFILE}.${profileId}.SIP.EventSubscribe
for sipevents in $sipevents
do
cmclient -u voipline -v subscr_id ADD ${obj}.SIP.EventSubscribe
cmclient -v event GETV ${sipevents}.Event
cmclient -u voipline SET ${obj}.SIP.EventSubscribe.${subscr_id}.Event "${event}"
done
cmclient -v exclude GETEXCLUDE
if [ "$exclude" = "0" ]; then
service_reload_line
fi
;;
"SIP.EventSubscribe")
[ "$user" != "voip" ] && return 8
service_reload_line
;;
esac
return 0
}
service_delete() {
map_obj "$obj"
case "$lineobj" in
"Line")
cmclient -u "voipline" SET ${VOIP_PROFILE}.${profileId}.Line.${vlineId}.Status Disabled
cmclient -u "voipline" SET ${VOIP_PROFILE}.${profileId}.Line.${vlineId}.Enable Disabled
reconf_voip_iptables
;;
esac
service_reload_line
}
check_allow_config() {
local MessageWaiting=""
if [ "$lineobj" = "SIP.EventSubscribe" ]; then
if [ "$changedEvent" = "1"  -a "$user" != "voip" ]; then
deny_set="1"
fi
fi
if [ "$changedCallForwardOnNoAnswerRingCount" = "1" ]; then
length=${#newCallForwardOnNoAnswerRingCount}
if [ "$length" = "0" ]; then
deny_set="1"
fi
if [ "$newCallForwardOnNoAnswerRingCount" -lt "1" ]; then
deny_set="1"
fi
if [ "$newCallForwardOnNoAnswerRingCount" -gt "20" ]; then
deny_set="1"
fi
fi
}
service_config() {
deny_set="0"
map_obj "$obj"
check_allow_config
if [ "$deny_set" = "1" ]; then
return 8
fi
if [ "$changedMWIEnable" = 1 -a "$newMWIEnable" = false ] ; then
cmclient SETE ${VOIP_PROFILE}.${profileId}.Line.${vlineId}.CallingFeatures.[MessageWaiting!false].MessageWaiting "false"
fi
service_reload_line
[ "$changedEnable" = "1" ] && reconf_voip_iptables
return 0
}
ret=0
case "$op" in
a)
service_add
ret=$?
;;
d)
service_delete
ret=$?
;;
s)
service_config
ret=$?
;;
esac
exit $ret
