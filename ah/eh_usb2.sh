#!/bin/sh
cmclient -v factory GETV "Device.X_ADB_FactoryData.FactoryMode"
[ "$factory" = "true" ] && exit 0
EH_NAME="USB Storage Handler"
. /etc/ah/helper_serialize.sh && help_serialize_nowait "eh_$EH_NAME$3" >/dev/null
. /etc/ah/helper_storage.sh
. /etc/ah/helper_autoshare.sh
DOM_STORAGESERVICE_PREFIX="Device.Services.StorageService.1"
MOUNT_DIR="/mnt/"
UNIT_1BLOCK_INBYTES=1024
UNIT_1MB_INBYTES=1000000
signal_samba() {
	local smblock
	if [ -x "/etc/ah/LogicalVolume-Samba.sh" ]; then
		smblock=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
	fi
}
wait_samba() {
	local smblock storageEnable printEnable
	if [ -x "/etc/ah/LogicalVolume-Samba.sh" ]; then
		smblock=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
		if [ $smblock -eq 0 ]; then
			cmclient -v storageEnable GETO "Device.Services.StorageService.NetworkServer.[SMBEnable=true]"
			cmclient -v printEnable GETV "Device.Services.X_ADB_PrinterService.Servers.SMB.Enable"
			[ -n "$storageEnable" -o "$printEnable" = "true" ] && cmclient SET "Device.Services.StorageService.NetworkServer.X_ADB_SambaRefresh" true
		fi
	fi
}
signal_ushare() {
	local usharelock
	if [ -x "/etc/ah/UPnPAV.sh" ]; then
		usharelock=$(help_sem_signal "$USHARE_CONF_FILE_SKIP")
	fi
}
wait_ushare() {
	local usharelock
	if [ -x "/etc/ah/UPnPAV.sh" ]; then
		usharelock=$(help_sem_wait "$USHARE_CONF_FILE_SKIP")
		[ $usharelock -eq 0 ] && cmclient SET "Device.X_ADB_UPnPAV.Status" Configuring
	fi
}
physicalMedium_bootLoading() {
	while [ 1 ]; do
		cmclient -v bootDone GETV "Device.DeviceInfo.X_ADB_BootDone"
		[ "$bootDone" = "true" ] && break
		sleep 1
	done
}
create_physical_disk() {
	local major minor blocks dname serialname vendor version fw_version sizemb="0" setm idx \
		absDevicePciPath="/sys/$devicepath" absDevName=/dev/$devicename
	local absSerialFileName="$absDevicePciPath/serial" absVendorFileName="$absDevicePciPath/manufacturer" \
		absVersionFileName="$absDevicePciPath/version" absVendorId="$absDevicePciPath/idVendor" \
		absProductId="$absDevicePciPath/idProduct"
	if [ -e "$absSerialFileName" ]; then
		read serialnum <$absSerialFileName
	else
		read vendorid <$absVendorId
		read productid <$absProductId
		serialnum="$vendorid$productid"
	fi
	serialnum=${serialnum%"${serialnum##*[! ]}"}
	cmclient -v obj GETO $DOM_STORAGESERVICE_PREFIX.PhysicalMedium.[SerialNumber="$serialnum"]
	if [ ${#obj} -ne 0 ]; then
		idx="${obj##*.}"
	else
		cmclient -v idx ADD "$DOM_STORAGESERVICE_PREFIX.PhysicalMedium"
		obj="$DOM_STORAGESERVICE_PREFIX.PhysicalMedium.$idx"
		cmclient SETE "$obj.SerialNumber" "$serialnum"
	fi
	read vendor <$absVendorFileName
	read version <$absVersionFileName
	if [ ${#vendor} -eq 0 ]; then
		if [ ${#serialnum} -ne 0 ]; then
			vendor="$serialnum"
		else
			vendor="unknown"
		fi
	fi
	case "$version" in
	1.*)
		version="USB 1.1"
		;;
	2.*)
		version="USB 2.0"
		;;
	3.*)
		version="X_ADB_USB 3.0"
		;;
	*)
		version="USB 1.1"
		;;
	esac
	while read major minor blocks dname; do
		[ "$dname" = "$devicename" ] && break
	done </proc/partitions
	[ -n "$blocks" ] && sizemb=$(($blocks * $UNIT_1BLOCK_INBYTES / $UNIT_1MB_INBYTES))
	read model </sys/block/$devicename/device/model
	read fw_version </sys/block/$devicename/device/rev
	setm="$obj.Status=X_ADB_Loading"
	setm="$setm	$obj.X_ADB_DeviceName=$absDevName"
	setm="$setm	$obj.Name=$vendor"
	setm="$setm	$obj.Vendor=$vendor"
	setm="$setm	$obj.ConnectionType=$version"
	setm="$setm	$obj.Removable=true"
	setm="$setm	$obj.HotSwappable=true"
	setm="$setm	$obj.Model=$model"
	setm="$setm	$obj.FirmwareVersion=$fw_version"
	setm="$setm	$obj.Capacity=$sizemb"
	setm="$setm	$obj.SMARTCapable=false"
	cmclient SETM "$setm"
}
if [ $# != 4 ]; then
	echo "Error! Wrong parameter's number. Expecting: <action> <subsystem> <devicename>" >/dev/console
	usage
	exit 1
fi
physicalMedium_bootLoading
action=$1
subsystem=$2
devicename=$3
devicepath=$4
echo "STORAGE $action $devicename" >/dev/console
absDevName=/dev/$devicename
case "$action" in
"add")
	create_physical_disk
	signal_samba
	signal_ushare
	cmclient -v listSupportedFS GETV $DOM_STORAGESERVICE_PREFIX.Capabilities.SupportedFileSystemTypes
	while read major minor LogVolSizeInBlocks LogVolName; do
		[ "$LogVolSizeInBlocks" = "1" ] && continue
		[ -z "$major" ] && continue
		[ "$major" = "major" ] && continue
		case "$LogVolName" in
		"$devicename"*) ;;

		*)
			continue
			;;
		esac
		if [ "$LogVolName" = "$devicename" ]; then
			count=0
			while read _ _ _ _devicename; do
				case "$_devicename" in
				"$devicename"*)
					count=$(($count + 1))
					;;
				esac
			done </proc/partitions
			[ $count -gt 1 ] && continue
		fi
		if [ ! -b "/dev/$LogVolName" ]; then
			rm -rf "/dev/$LogVolName"
			mknod "/dev/$LogVolName" b $major $minor
		fi
		probedFS=$(findfs "/dev/$LogVolName")
		supportedFS="no"
		IFS=","
		for elem in $listSupportedFS; do
			if [ "$elem" = "$probedFS" ]; then
				supportedFS="yes"
				fs="$elem"
				break
			fi
		done
		unset IFS
		absLogVolName="/dev/$LogVolName"
		read startSector <"/sys/class/block/$LogVolName/start"
		read sizeSectors <"/sys/class/block/$LogVolName/size"
		: ${startSector:=0}
		[ ${#LogVolSizeInBlocks} -ne 0 ] && LogVolSizeInMB=$(($LogVolSizeInBlocks * $UNIT_1BLOCK_INBYTES / $UNIT_1MB_INBYTES))
		cmclient -v lvobjs GETO "$DOM_STORAGESERVICE_PREFIX.LogicalVolume.[PhysicalReference=$obj].[X_ADB_StartSector=$startSector].[X_ADB_SizeSectors=$sizeSectors]"
		lvobj=""
		for lvobj in $lvobjs; do
			break
		done
		rootFlag=0
		setm=""
		if [ ${#lvobj} -eq 0 ]; then
			cmclient -v lvidx ADD "$DOM_STORAGESERVICE_PREFIX.LogicalVolume"
			lvobj="$DOM_STORAGESERVICE_PREFIX.LogicalVolume.$lvidx"
			[ -z "$setm" ] && setm="$lvobj.X_ADB_StartSector=$startSector" || setm="$setm	$lvobj.X_ADB_StartSector=$startSector"
			setm="$setm	$lvobj.X_ADB_SizeSectors=$sizeSectors"
			setm="$setm	$lvobj.PhysicalReference=$obj"
			cmclient ADD "$lvobj.Folder"
			cmclient SET "$lvobj.Folder.1.Name" "."
			if [ -x /etc/ah/UPnPAV.sh ]; then
				cmclient -v sharename GETV "$obj.Name"
				[ -z "$sharename" ] && getUniqueShareNameLetters "$lvobj.Folder.1" || cmclient SETE $lvobj.Folder.1.X_ADB_ShareName "$sharename"
				cmclient SET $lvobj.Folder.1.X_ADB_UPnPAVShareEnable "true"
			fi
			cmclient -v dlnastat GETV Device.DLNA.X_ADB_Device.AutoshareEnable
			[ "$dlnastat" = "true" ] && cmclient SET "$lvobj.X_ADB_DLNA.Enable" true
			rootFlag=1
		fi
		cmclient -v lv_enabled GETV $lvobj.Enable
		setm="${setm:+$setm	}$lvobj.Capacity=$LogVolSizeInMB"
		setm="$setm	$lvobj.Encrypted=false"
		setm="$setm	$lvobj.Name=$absLogVolName"
		setm="$setm	$lvobj.X_ADB_MountPoint=$MOUNT_DIR$LogVolName"
		if [ "$supportedFS" = "yes" ]; then
			setm="$setm	$lvobj.FileSystem=$fs"
		else
			local nam mod
			cmclient -v nam GETV $obj.Name
			cmclient -v mod GETV $obj.Model
			if [ ${#probedFS} -ne 0 ]; then
				setm="$setm	$lvobj.FileSystem=X_ADB_UnsupportedFS"
				logger -t storage -p daemon.warn "ARS 1 - Unsupported file system on device: $nam $mod ($LogVolSizeInMB MB)"
			else
				setm="$setm	$lvobj.FileSystem=X_ADB_Unknown"
				logger -t storage -p daemon.warn "ARS 2 - Unknown file system on device: $nam $mod ($LogVolSizeInMB MB)"
			fi
		fi
		local lockDir=$(help_serialize_nowait "$lockFolder" notrap)
		case "$probedFS" in
		X_ADB_EXT)
			label=$(blkid | grep ${absLogVolName}:)
			label=${label#*=\"}
			label=${label%*\" UUID*}
			;;
		NTFS)
			label=$(ntfslabel -f $absLogVolName) 2>/dev/null
			;;
		"FAT12" | "FAT16" | "FAT32" | "HFS+")
			label=$(blkid | grep ${absLogVolName}:)
			label=${label#*=\"}
			label=${label%\"*}
			label=${label%*\" UUID*}
			;;
		*)
			label=""
			;;
		esac
		[ -n "$label" ] && label=${label%%	*} && setm="$setm	$lvobj.X_ADB_PartitionLabel=$label"
		if [ "$supportedFS" = "yes" ]; then
			setm="$setm	$lvobj.Enable=true	$lvobj.Status=Online"
		elif [ "$lv_enabled" = "true" ]; then
			setm="$setm	$lvobj.Status=Online"
		else
			setm="$setm	$lvobj.Status=Offline"
		fi
		help_serialize_unlock "$lockFolder" 2>/dev/null
		cmclient SETM "$setm"
		setm=""
		[ "$rootFlag" -eq 1 ] && autoshare_usb_event "$lvobj"
	done </proc/partitions
	cmclient SET "$obj.Status" "Online"
	wait_ushare
	wait_samba
	[ -x /etc/ah/UPnPAV.sh ] && cmclient SET "$lvobj.Folder.1.X_ADB_RefreshUPnPAV" "true"
	cmclient -v ftpstat GETV "Device.Services.StorageService.$baseIdx.FTPServer.Enable"
	if [ "${ftpstat:-false}" != "false" ]; then
		cmclient SET Device.Services.StorageService.$baseIdx.FTPServer.Enable false
		cmclient SET Device.Services.StorageService.$baseIdx.FTPServer.Enable true
	fi
	;;
"remove")
	signal_samba
	signal_ushare
	cmclient -v obj GETO $DOM_STORAGESERVICE_PREFIX.PhysicalMedium.[X_ADB_DeviceName=$absDevName]
	if [ -n "$obj" ]; then
		setm="$obj.X_ADB_DeviceName="
		setm="$setm	$obj.Status=Offline"
		cmclient SETM "$setm"
		setm=""
		unsafe="false"
		cmclient -v lvobjs GETO $DOM_STORAGESERVICE_PREFIX.LogicalVolume.[PhysicalReference=$obj].[Status!Offline]
		cmclient -v spoolPartition GETV Device.Services.X_ADB_PrinterService.SpoolPartition
		for lvobj in $lvobjs; do
			setm="$lvobj.Status=Offline	$setm"
			unsafe="true"
			if [ "$spoolPartition" = "$lvobj" ]; then
				cmclient "SETM Device.Services.X_ADB_PrinterService.SpoolEnabled=false	Device.Services.X_ADB_PrinterService.SpoolPartition=\"\""
			fi
		done
		setm="$obj.X_ADB_UnsafeRemoval=$unsafe	$setm"
		cmclient SETM "$setm"
	fi
	wait_ushare
	wait_samba
	;;
*)
	echo "$action is not yet supported $2 $3 $4" >/dev/console
	;;
esac
cmclient SAVE
if [ -f /etc/ah/HTTPServer.sh ]; then
	cmclient SET "$DOM_STORAGESERVICE_PREFIX.HTTPServer.[Enable=true].X_ADB_Reset" "true"
fi
exit 0
