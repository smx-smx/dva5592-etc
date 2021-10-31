#!/bin/sh
AH_NAME="VoIPSLICMeasures"
VOIP_CTRLIF_ADDR="local:/tmp/voip_socket"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
phyObj="${obj%.*}"
phyId="${obj##*.PhyInterface.}"
phyId="${phyId%%.*}"
lineId=$((phyId-1))
testId="3"
testState="None"
case "$op" in
g)
;;
s)
case "$newTestSelector" in
Requested)
cmclient SET "$obj".TestState "Requested"
case "$phyId" in
1|2) #FXS
cmclient -v pstn_in GETV "$phyObj.X_TELECOMITALIA_IT_SwitchToPSTNIn"
if [ "$pstn_in" = "true" ]; then
testState="Error_TestNotSupported"
else
testId="8" #LT-API "All GR-909" test
testState="Requested"
fi
;;
3|4) #DECT,FXO
testState="Error_TestNotSupported"
;;
esac
;;
PhoneConnectivityTest)
cmclient SET "$obj".TestState "Requested"
case "$phyId" in
1|2) #FXS
cmclient -v pstn_in GETV "$phyObj.X_TELECOMITALIA_IT_SwitchToPSTNIn"
if [ "$pstn_in" = "true" ]; then
testState="Error_TestNotSupported"
else
testId="3" #LT-API "Ringers Equivalence Number" test
testState="Requested"
fi
;;
3|4) #DECT,FXO
testState="Error_TestNotSupported"
;;
esac
;;
esac
cmclient SET "$obj".TestState "$testState"
if [ "$testState" = "Requested" ]; then
echo MEASURES $lineId $testId | nc $VOIP_CTRLIF_ADDR
fi
;;
esac
exit 0
