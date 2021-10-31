#!/bin/sh
#nl:*,usb_device,*
#sync:skipcycles
. /etc/ah/helper_usbdevices.sh
mode="$1"
if [ "$mode" = "probe" ]; then
	help_setUSBDeviceData
else
	case $TYPE in
	"usb_device")
		devnum=${OBJ##*/}
		devnum=${devnum##0}
		devnum=${devnum##0}
		busnum=${OBJ%/*}
		busnum=${busnum##*/}
		busnum=${busnum##0}
		busnum=${busnum##0}
		cmclient -v obj GETO "Device.USB.USBHosts.Host.$busnum.Device.[DeviceNumber=$devnum]"
		case $OP in
		"add")
			[ ! -e "$OBJ" -a -n "$MAJOR" -a -n "$MINOR" ] && mkdir -p "${OBJ%/*}" && mknod "$OBJ" c $MAJOR $MINOR
			if [ -z "$obj" ]; then
				help_setUSBDeviceData $busnum $devnum
			fi
			;;
		"remove")
			[ -c "$OBJ" ] && rm "$OBJ"
			if [ -n "$obj" ]; then
				cmclient -v port GETV "$obj.Port"
				cmclient SET "Device.USB.USBHosts.Host.Device.[Parent=$obj].Parent" ""
				cmclient DEL "$obj"
				[ $port -eq 0 ] && cmclient DEL "${obj%.Device.*}"
			fi
			;;
		esac
		;;
	esac
fi
exit 0
