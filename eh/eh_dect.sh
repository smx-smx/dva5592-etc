#!/bin/sh
#bcm:*,dect,*
EH_NAME="EH DECT"
DECT_DEVICE="Device.Services.VoiceService.1.DECT.Base.1"
event=${OP%-*}
event=${event#-}
duration=${OP#*-}
duration=${duration%-}
for terminal in /dev/pts/*; do
	if [ "$event" = "pressed" ]; then
		echo "dect button pressed" 2>/dev/null >>$terminal
	fi
done
if [ "$event" = "$duration" ]; then
	duration=0
fi
if ! pidof voip; then
	exit 0
fi
if [ "$event" = "released" ]; then
	if [ "$duration" -ge "5000" ]; then
		echo "DECT Paging start" >/dev/console
		cmclient SET ${DECT_DEVICE}.X_ADB_PagingEnable true
	elif [ "$duration" -ge "2000" ]; then
		echo "DECT pairing start" >/dev/console
		cmclient SET ${DECT_DEVICE}.SubscriptionEnable true
	fi
fi
exit 0
