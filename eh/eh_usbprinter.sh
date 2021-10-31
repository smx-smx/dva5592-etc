#!/bin/sh
#nl:*,usb,lp*
EH_NAME="PRINTER_Handler"
cmclient -v tmp GETV Device.X_ADB_FactoryData.FactoryMode
[ "$tmp" = "true" ] && exit 0
. /etc/ah/helper_serialize.sh && help_serialize ${EH_NAME}
. /etc/ah/helper_functions.sh
PRINTER_MAJOR_NUM="180"
PHY_CONNTYPE_USB_1_00_TRVAL="USB 1.1"
PHY_CONNTYPE_USB_2_00_TRVAL="USB 2.0"
PHY_CONNTYPE_USB_1_00_RAWVAL="1.10"
PHY_CONNTYPE_USB_2_00_RAWVAL="2.00"
LP_IEEE1248_TAG_MANUFACTURER="MFG"
LP_IEEE1248_TAG_MANUFACTURER1="MANUFACTURER"
LP_IEEE1248_TAG_MODEL="MDL"
LP_IEEE1248_TAG_MODEL1="MODEL"
LP_IEEE1248_TAG_SERIALNUM="SN"
MAX_RAW_PORTS="9"
P910D_BASE_NAME="p"
P910D_BASE_PORT_NUM="9100"
P910D_SUFFIX="d"
OK=0
echo "$EH_NAME: $OP $TYPE $OBJ $A1" >/dev/console
while true; do
	cmclient -v tmp GETV "Device.DeviceInfo.X_ADB_BootDone"
	[ "$tmp" = "true" ] && break
	sleep 1
done
devicename=$OBJ
devicepath=$A1
str_replace() {
	local tmp str ret=$2 sep=$4 old_ifs=$IFS
	IFS=$3
	set -- $1
	IFS=$old_ifs
	for tmp; do
		[ ${#str} -eq 0 ] && str=$tmp || str="$str$sep$tmp"
	done
	eval $ret='$str'
}
str_token() {
	local old_ifs=$IFS ret=$2 pos=$4
	IFS=$3
	set -- $1
	IFS=$old_ifs
	eval $ret='$'$pos
}
lpAbsDevicePciPath=/sys$devicepath
lpAbsDeviceName="/dev/usb$devicename"
lpAbsSerialFileName=$lpAbsDevicePciPath/serial
lpAbsVendorFileName=$lpAbsDevicePciPath/manufacturer
lpAbsVersionFileName=$lpAbsDevicePciPath/version
lpAbsModelFileName=$lpAbsDevicePciPath/idProduct
case "$OP" in
add)
	if [ ! -f "$lpAbsSerialFileName" ]; then
		echo $lpAbsSerialFileName not found >/dev/console
		exit 1
	fi
	read serialnum <$lpAbsSerialFileName
	read vendor <$lpAbsVendorFileName
	str_replace "$vendor" vendor " " ""
	read version <$lpAbsVersionFileName
	echo serialnum $serialnum vendor $vendor >/dev/console
	case "$version" in
	"$PHY_CONNTYPE_USB_1_00_RAWVAL")
		version=$PHY_CONNTYPE_USB_1_00_TRVAL
		;;
	"$PHY_CONNTYPE_USB_2_00_RAWVAL")
		version=$PHY_CONNTYPE_USB_2_00_TRVAL
		;;
	*)
		echo "$version is not yet supported" >/dev/console
		;;
	esac
	read model <$lpAbsModelFileName
	lpMajorNum=$PRINTER_MAJOR_NUM
	lpMinorNum=${devicename##lp}
	mknod -m 666 $lpAbsDeviceName c $lpMajorNum $lpMinorNum
	ret=$?
	if [ "$ret" = "$OK" ]; then
		lpAbsDevicePciIEEE1824Path=/sys$devicepath
		lpAbsDevicePciIEEE1824Path=$(find $lpAbsDevicePciIEEE1824Path -name ieee1284_id)
		if [ -n "$lpAbsDevicePciIEEE1824Path" ]; then
			read lpIeeeData <$lpAbsDevicePciIEEE1824Path
			IFS=";"
			for lpObj in $lpIeeeData; do
				IFS=":"
				read lpIeeeDataTagName lpIeeeDataTagValue tmp <<-EOF
					$lpObj
				EOF
				IFS=";"
				if [ -z "$lpIeeeDataTagName" ] || [ -z "$lpIeeeDataTagValue" ]; then
					continue
				fi
				lpIeeeDataTagNameFilter=${lpIeeeDataTagName%%$LP_IEEE1248_TAG_MANUFACTURER}
				lpIeeeDataTagNameFilter=${lpIeeeDataTagName##$lpIeeeDataTagNameFilter}
				[ "$lpIeeeDataTagNameFilter" = "$LP_IEEE1248_TAG_MANUFACTURER" ] &&
					lpIeeeDataTagName=$lpIeeeDataTagNameFilter
				case "$lpIeeeDataTagName" in
				$LP_IEEE1248_TAG_MANUFACTURER | $LP_IEEE1248_TAG_MANUFACTURER1)
					lpIeeeDataMfg=$lpIeeeDataTagValue
					;;
				$LP_IEEE1248_TAG_MODEL | $LP_IEEE1248_TAG_MODEL1)
					lpIeeeDataMdl=$lpIeeeDataTagValue
					;;
				$LP_IEEE1248_TAG_SERIALNUM)
					lpIeeeDataSn=$lpIeeeDataTagValue
					;;
				esac
			done
			unset IFS
			if [ -x /usr/lib/cups/backend/usb ]; then
				lpUsbUri=$(/usr/lib/cups/backend/usb)
				str_token "$lpUsbUri" lpUsbUri " " 2
			fi
			case "$lpUsbUri" in
			"usb://"*)
				lpIeeeDataDeviceUri="$lpUsbUri"
				;;
			*)
				if [ -n "$lpIeeeDataMfg" ] && [ -n "$lpIeeeDataMdl" ]; then
					if [ -n "$lpIeeeDataSn" ]; then
						lpIeeeDataDeviceUri="usb://$lpIeeeDataMfg/$lpIeeeDataMdl?serial=$lpIeeeDataSn"
					else
						lpIeeeDataDeviceUri="usb://$lpIeeeDataMfg/$lpIeeeDataMdl"
					fi
				else
					echo "Can not find printer device URI" >/dev/console
				fi
				;;
			esac
			if [ -n "$lpIeeeDataMfg" ] && [ -n "$lpIeeeDataMdl" ]; then
				str_replace "$lpIeeeDataMdl" lpIeeeDataMdl " " "_"
				str_replace "$lpIeeeDataMfg" lpIeeeDataMfg " " "_"
				lpName=$lpIeeeDataMfg\_$lpIeeeDataMdl
				str_replace $lpName lpDescription "_" " "
			fi
		else
			echo " Can not find IEEE 1284 data" >/dev/console
		fi
	fi
	cmclient -v objs GETO Device.Services.X_ADB_PrinterService.PrinterDevice.*.[SerialNumber=$serialnum]
	if [ ${#objs} -gt 0 ]; then
		for obj in $objs; do
			setm="$obj.DeviceName=$lpAbsDeviceName	$obj.Status=Online"
			cmclient SETM "$setm"
			str_token "$obj" idx "." 5
		done
	else
		cmclient -v idx ADD Device.Services.X_ADB_PrinterService.PrinterDevice
		obj="Device.Services.X_ADB_PrinterService.PrinterDevice.$idx"
		lpShareName="$vendor$model"
		cmclient -v defNameObj GETO Device.Services.X_ADB_PrinterService.PrinterDevice.*.[Name=$lpShareName]
		[ -n "$defNameObj" ] && lpShareName="$lpShareName-$idx"
		[ "${lpShareName}" != "${lpShareName#*,}" ] && lpShareName=$(help_tr "," "" "$lpShareName")
		setm="Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.Name=$lpShareName"
		setm="$setm	Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.DeviceName=$lpAbsDeviceName"
		setm="$setm	Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.SerialNumber=$serialnum"
		setm="$setm	Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.Description=$lpDescription"
		setm="$setm	Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.Status=Online"
		setm="$setm	Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.DeviceURI=$lpIeeeDataDeviceUri"
		setm="$setm	Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.ConnectionType=$version"
		setm="$setm	Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.Vendor=$vendor"
		setm="$setm	Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.Model=$model"
		cmclient SETM "$setm"
		cmclient -v printerstat GETV Device.Services.X_ADB_PrinterService.AutoshareEnable
		[ "$printerstat" = "true" ] && cmclient SET "Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.Enable" true
		rpnCount="0"
		rpnMax="-1"
		cmclient -v objs GETO Device.Services.X_ADB_PrinterService.PrinterDevice
		for lpRaw in $objs; do
			cmclient -v rpnVal GETV $lpRaw.RawPortNumber
			[ -z "$rpnVal" ] && continue
			rpnVal=$((rpnVal - $P910D_BASE_PORT_NUM))
			rpnCount=$((rpnCount + 1))
			[ "$rpnVal" -gt "$rpnMax" ] && rpnMax=$rpnVal
		done
		lpRawPortNumber=$((rpnMax + 1))
		if [ "$lpRawPortNumber" -ge "$MAX_RAW_PORTS" ] && [ "$rpnCount" -lt "$MAX_RAW_PORTS" ]; then
			chkPort="0"
			while [ "$chkPort" -le "$MAX_RAW_PORTS" ]; do
				found="true"
				cmclient -v objs GETO Device.Services.X_ADB_PrinterService.PrinterDevice
				for lpRaw in $objs; do
					cmclient -v rpnVal GETV $lpRaw.RawPortNumber
					[ -z "$rpnVal" ] && continue
					if [ "$chkPort" = "$rpnVal" ]; then
						found="false"
						break
					fi
				done
				if [ "$found" = "true" ]; then
					lpRawPortNumber=$chkPort
					break
				fi
				chkPort=$((chkPort + 1))
			done
		fi
		if [ "$lpRawPortNumber" -lt "$MAX_RAW_PORTS" ]; then
			lpRawPortNumber=$((P910D_BASE_PORT_NUM + $lpRawPortNumber))
			cmclient SET Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.RawPortNumber "$lpRawPortNumber"
		fi
	fi
	cmclient -v lpPrnService GETV Device.Services.X_ADB_PrinterService.Enable
	if [ "$lpPrnService" = "true" ]; then
		cmclient -v prnEnable GETV Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.Enable
		cmclient -v prnRawEnable GETV Device.Services.X_ADB_PrinterService.Servers.RAW.Enable
		cmclient -v prnRawPortNum GETV Device.Services.X_ADB_PrinterService.PrinterDevice.$idx.RawPortNumber
		if [ "$prnEnable" = "true" ] && [ "$prnRawEnable" = "true" ] && [ -n "$prnRawPortNum" ]; then
			p910ndName=$P910D_BASE_NAME$prnRawPortNum$P910D_SUFFIX
			pid=$(pidof $p910ndName)
			[ -n "$pid" ] && kill -9 $pid
			prnRawPortNum=$((prnRawPortNum - $P910D_BASE_PORT_NUM))
			p910nd -f $lpAbsDeviceName $prnRawPortNum &
		fi
	fi
	;;
remove)
	cmclient -v obj GETO Device.Services.X_ADB_PrinterService.PrinterDevice.*.[DeviceName=$lpAbsDeviceName]
	if [ -n "$obj" ]; then
		setm="$obj.DeviceName=\"\"	$obj.Status=Offline"
		cmclient SETM "$setm" >/dev/null
		cmclient -v rpnVal GETV $obj.RawPortNumber
		if [ -n "$rpnVal" ]; then
			p910ndName=$P910D_BASE_NAME$rpnVal$P910D_SUFFIX
			pid=$(pidof $p910ndName)
			[ -n "$pid" ] && kill -9 $pid
		fi
		cmclient -v objs GETO $obj.PrintJob
		for pJob in $objs; do
			cmclient SET $pJob.Cancel true
		done
	fi
	rm -f $lpAbsDeviceName
	ret=$?
	[ "$ret" != "$OK" ] && echo "Can not delete printer device file $lpAbsDeviceName" >/dev/console
	;;
*)
	echo "$OP is not yet supported" >/dev/console
	;;
esac
exit 0
