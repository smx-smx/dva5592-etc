#!/bin/sh
#bcm:*,reset,*
factory_mode=$(cmclient -t 6 GETV "Device.X_ADB_FactoryData.FactoryMode")
case "$OP" in
"shortpressed")
	for terminal in /dev/pts/*; do
		echo "reset button pressed shortly " 2>/dev/null >>$terminal
	done
	;;
"pressed")
	if [ "$factory_mode" = "true" ]; then
		for terminal in /dev/pts/*; do
			echo "reset button pressed enough but reboot skipped in factory mode" 2>/dev/null >>$terminal
		done
	else
		echo "reset button pressed enough - factory restore initiated"
		cmclient RESET >/dev/null
	fi
	;;
"longpressed")
	cmclient -v lbpe GETV Device.DeviceInfo.X_ADB_CustomerDefaultLongPressedEnabled
	if [ "$lbpe" = "true" ]; then
		echo "reset button pressed for long time" 2>/dev/null >>$terminal
		cmclient SET Device.DeviceInfo.X_ADB_CustomerDefault None
	else
		echo "reset button pressed enough - factory restore initiated"
		cmclient RESET >/dev/null
	fi
	;;
esac
exit 0
