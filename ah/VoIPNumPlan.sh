#!/bin/sh
AH_NAME="VoIPNumPlan"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
cmclient -v single_numplan -u voip GETV Device.Services.VoiceService.1.Capabilities.X_ADB_NumberingPlan
if [ "$single_numplan" = "true" ]; then
OBJNUMP="Device.Services.VoiceService.X_ADB_NumberingPlan"
if [ "$1" = "r" ]; then
if [ "$2" != "" ]; then
exit 2
fi
else
case $obj in
*NumberingPlan)
;;
*)
lobj="${obj##*VoiceProfile.}"
if [ "$lobj" != "$obj" ]; then
exit 2
fi
;;
esac
fi
else
if [ "$1" = "r" ]; then
profileId="$2"
else
case $obj in
*NumberingPlan)
profileId="dummy"
;;
*)
lobj="${obj##*VoiceProfile.}"
if [ "$lobj" = "$obj" ]; then
exit 2
fi
profileId="${lobj%%.NumberingPlan*}"
;;
esac
fi
OBJNUMP="Device.Services.VoiceService.1.VoiceProfile.${profileId}.NumberingPlan"
fi
check_PrefixRange() {
noSpacePrefix=`echo $newPrefixRange | sed 's/ //g'`
lenNoSpace=${#noSpacePrefix}
length=${#newPrefixRange}
if [ "$length" = "0" ]; then
return 1
fi
if [ "$lenNoSpace" -lt "$length" ]; then
return 1
fi
if [ "${newPrefixRange:0:1}" = "-" ]; then
return 1
fi
if [ "${newPrefixRange:$((length-1)):1}" = "-" ]; then
return 1
fi
count="0"
findhyphen="0"
while [ $count -le $length ];
do
char=${newPrefixRange:$count:1}
if [ "${char}" = "-" ]; then
findhyphen="1"
break
fi
count=$((count+1))
done
if [ $findhyphen = "1" ];then
From=${newPrefixRange:0:$((count))}
To=${newPrefixRange:$((count+1)):$((length-count))}
lastFromdigit=${newPrefixRange:$((count-1)):1}
if [ $To -gt "9" -o $To -le "$lastFromdigit" ]; then
return 1
fi
fi
return 0
}
if [ "$1" != "r" ]; then
case $obj in
*NumberingPlan)
;;
*)
if [ "$op" = "a" ]; then
cmclient -v maxEntries -u voip GETV  ${OBJNUMP}.PrefixInfoMaxEntries
if [ "$maxEntries" = "" ]; then
maxEntries=0
fi
cmclient -v numEntries -u voip GETV  ${OBJNUMP}.PrefixInfoNumberOfEntries
if [ "$numEntries" = "" ]; then
numEntries=0
fi
if [ "$numEntries" -gt "$maxEntries" ]; then
cmclient -u "${AH_NAME}${obj}" DEL $obj
exit 4
fi
fi
if [ "$op" = "s" ]; then
case $obj in
*PrefixRange*)
check_PrefixRange
if [ "$?" = "1" ]; then
exit 2
fi
;;
esac
fi
;;
esac
: > /etc/voip/reload
fi
exit 0
