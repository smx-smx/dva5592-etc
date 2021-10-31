#!/bin/sh
usbdevices="/proc/bus/usb/devices"
levVirtHub=0
createUSBPort() {
	local n=$1 std=$2 rate=$3 i=0 setp
	while [ $i -lt $n ]; do
		i=$((i + 1))
		cmclient -v port GETO "Device.USB.Port.$i"
		[ ${#port} -ne 0 ] && continue
		cmclient ADD "Device.USB.Port.$i"
		port="Device.USB.Port.$i"
		setp="${setp:+$setp	}$port.Name=USB Port $i"
		setp="$setp	$port.Standard=$std"
		setp="$setp	$port.Type=Host"
		setp="$setp	$port.Receptacle=Standard-A"
		setp="$setp	$port.Rate=$rate"
		setp="$setp	$port.Power=Unknown"
	done
	[ ${#setp} -ne 0 ] && cmclient SETM "$setp"
}
parse_usb_bus() {
	local usbData=$1 \
		rbus lev parent port dev spd mxch rate vrhusbver \
		usbclass usbsubclass usbdevproto \
		vid pid rel relmaj relmin \
		serial manufacturer product name type
	op=${usbData%%:*}
	opt="$op:  "
	arg=${usbData#$opt*}
	case "$op" in
	"D")
		usbver=${arg#*Ver=}
		usbclass=${usbver#*Cls=}
		usbsubclass=${usbclass#*) Sub=}
		usbdevproto=${usbsubclass#*Prot=}
		usbver=${usbver%% Cls*}
		usbver=${usbver# }
		setm="$objDev.DeviceClass=${usbclass%%(*}	$setm"
		setm="$objDev.DeviceSubClass=${usbsubclass%% Prot*}	$setm"
		setm="$objDev.DeviceProtocol=${usbdevproto%% MxPS*}	$setm"
		setm="$objDev.USBVersion=$usbver	$setm"
		[ -n "$objHost" ] && setm="$objHost.USBVersion=$usbver	$setm"
		;;
	"C")
		act=${usbData##C:  *}
		cfn=${arg#*Cfg\#=}
		cfn=${cfn%% Atr=*}
		cfn=${cfn# }
		cmclient -v cfidx ADD "$objDev.Configuration"
		objConf="$objDev.Configuration.$cfidx"
		[ ${#act} -ne 0 ] && setm="$objConf.X_ADB_Active=true	$setm"
		setm="$objConf.ConfigurationNumber=$cfn	$setm"
		;;
	"I")
		act=${usbData##I:  *}
		ifn=${arg#*If\#=}
		usbclass=${ifn#*Cls=}
		usbsubclass=${usbclass#*) Sub=}
		usbdevproto=${usbsubclass#*Prot=}
		usbdriver=${usbdevproto#*Driver=}
		ifn=${ifn%% Alt=*}
		ifn=${ifn# }
		cmclient -v ifidx ADD "$objConf.Interface"
		objIntf="$objConf.Interface.$ifidx"
		[ ${#act} -ne 0 ] && setm="$objIntf.X_ADB_Active=true	$setm"
		setm="$objIntf.InterfaceNumber=$((ifn + 1))	$setm"
		setm="$objIntf.InterfaceClass=${usbclass%%(*}	$setm"
		setm="$objIntf.InterfaceSubClass=${usbsubclass%% Prot*}	$setm"
		setm="$objIntf.InterfaceProtocol=${usbdevproto%% Driver*}	$setm"
		setm="$objIntf.X_ADB_InterfaceDriver=${usbdriver}	$setm"
		;;
	"P")
		vid=${arg#*Vendor=}
		vid=$(printf "%d" 0x${vid%% Prod*})
		setm="$objDev.VendorID=$vid	$setm"
		pid=${arg#*ProdID=}
		pid=$(printf "%d" 0x${pid%% Rev*})
		setm="$objDev.ProductID=$pid	$setm"
		rel=${arg#*Rev= }
		rel=${rel#*Rev=}
		rel=${rel%.*}${rel##*.}
		[ "$rel" = "${rel##*[a-f,A-F]*}" -a ${rel:0:1} != 0 ] && setm="$objDev.DeviceVersion=$rel	$setm"
		;;
	"S")
		serial=${arg##SerialNumber=*}
		if [ -z "$serial" ]; then
			serial=${arg#SerialNumber=*}
			setm="$objDev.SerialNumber=$serial	$setm"
		fi
		manufacturer=${arg##Manufacturer=*}
		if [ -z "$manufacturer" ]; then
			manufacturer=${arg#Manufacturer=*}
			setm="$objDev.Manufacturer=$manufacturer	$setm"
		fi
		product=${arg##Product=*}
		if [ -z "$product" ]; then
			product=${arg#Product=*}
			setm="$objDev.ProductClass=$product	$setm"
		fi
		if [ "$usbhost" = "true" ]; then
			product=${arg##Product=*}
			if [ -z "$product" ]; then
				name=${arg#Product=*}
				pre="${arg%[EOUx]HCI*}"
				type=${arg#$pre}
				type=${type%% *}
				setm="$objHost.Name=$name	$setm"
				setm="$objHost.Type=$type	$setm"
				usbhost="false"
			fi
		fi
		;;
	"T")
		rbus=${arg#*Bus=}
		lev=${rbus#*Lev=}
		parent=${lev#*Prnt=}
		port=${parent#*Port=}
		dev=${port#*Dev\#=}
		spd=${dev#*Spd=}
		mxch=${spd#*MxCh=}
		rbus=${rbus%% Lev*}
		rbus=${rbus#0}
		lev=${lev%% Prnt*}
		parent=${parent%% Port*}
		parent=${parent#0}
		port=${port%% Cnt*}
		port=${port#0}
		dev=${dev%% Spd*}
		dev=${dev# }
		dev=${dev# }
		spd=${spd%% MxCh*}
		spd=${spd%% }
		spd=${spd%% }
		mxch=${mxch# }
		usbhost="false"
		if [ $lev -eq 0 ]; then
			if [ "$mode" = "probe" ]; then
				cmclient -v objHost GETO "Device.USB.USBHosts.Host.$rbus"
				[ ${#objHost} -ne 0 ] && return
			fi
			usbhost="true"
			objHost="Device.USB.USBHosts.Host"
			cmclient -v idxhost ADD "$objHost.$rbus"
			objHost="$objHost.$idxhost"
		fi
		haveToSkip="0"
		objDev="Device.USB.USBHosts.Host.$rbus.Device"
		cmclient -v idxdev ADD "$objDev"
		objDev="$objDev.$idxdev"
		case $spd in
		1.5) rate=Low ;;
		12) rate=Full ;;
		480) rate=High ;;
		5000) rate=Super ;;
		esac
		cmclient -v parent GETO "Device.USB.USBHosts.Host.$rbus.Device.[DeviceNumber=$parent]"
		[ "$usbhost" = "false" ] && port=$((port + 1))
		setm="$objDev.DeviceNumber=$dev"
		cmclient -v vrh GETV "Device.USB.USBHosts.Host.$rbus.X_ADB_VirtualRootHub"
		if [ ${#vrh} -ne 0 ]; then
			if [ "$parent" = "$vrh" ]; then
				cpePort="Device.USB.Port.$port"
			else
				cmclient -v cpePort GETV "$parent.USBPort"
			fi
			setm="$objDev.USBPort=$cpePort	$setm"
		fi
		setm="$objDev.Port=$port	$setm"
		setm="$objDev.Rate=$rate	$setm"
		setm="$objDev.Parent=$parent	$setm"
		setm="$objDev.MaxChildren=$mxch	$setm"
		if [ $lev -eq $levVirtHub ]; then
			cmclient SET "USB.USBHosts.Host.$rbus.X_ADB_VirtualRootHub $objDev"
			createUSBPort "$mxch" "2.0" "$rate"
		fi
		;;
	esac
}
help_setUSBDeviceData() {
	local i="$1" irbus="${1:--1}" idev="${2:--1}" found=0 mode= usbData
	haveToSkip="1"
	[ $# -eq 0 ] && mode=probe
	while read usbData; do
		if [ -n "$usbData" ]; then
			if [ "$mode" != "probe" ]; then
				[ "$haveToSkip" = "1" ] &&
					case "$usbData" in
					T:\ \ Bus=*$irbus*Dev#=*$idev\ Spd*)
						found=1
						;;
					*)
						continue
						;;
					esac
				parse_usb_bus "$usbData" "$i" "$irbus" "$idev"
			else
				[ "$haveToSkip" = "1" ] &&
					case "$usbData" in
					T:*) ;;

					*)
						continue
						;;
					esac
				parse_usb_bus "$usbData"
			fi
		else
			if [ -n "$setm" ]; then
				cmclient SETM "$setm" >/dev/null
				setm=""
			fi
			[ $found -eq 1 ] && return
		fi
	done <$usbdevices
	if [ -n "$setm" ]; then
		cmclient SETM "$setm" >/dev/null
	fi
}
