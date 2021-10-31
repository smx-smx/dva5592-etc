#!/bin/sh
AH_NAME="LogicalVolume"
DMS_PIPE="/tmp/dms_ipc"
[ "$user" = "yacs" ] && exit 0
[ "$user" = "boot" ] && exit 0
[ "$user" = "dummy" ] && exit 0
[ "$user" = "$AH_NAME$obj" ] && exit 0
[ -f /tmp/upgrading.lock ] && [ "$op" != "g" ] && exit 0
. /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_storage.sh
[ -e /etc/ah/helper_dlna.sh ] && . /etc/ah/helper_dlna.sh
. /etc/ah/helper_SystemLog.sh
NEWLINE='
'
service_mount_lvol() {
	local lvol_name="$newName" lvol_fs="$newFileSystem" elem mDir modules \
		mount_ret opts="-o nodev,nosuid" \
		lockDir=$(help_serialize_nowait "$lockFolder" notrap)
	case "$lvol_fs" in
	"X_ADB_msdos")
		modules="msdos"
		lvol_fs="msdos"
		opts=
		;;
	"FAT16" | "FAT32")
		modules="fat vfat"
		lvol_fs="vfat"
		opts="-o utf8,umask=000"
		;;
	"NTFS")
		modules="fuse"
		lvol_fs="ntfs"
		opts="$opts,force,big_writes"
		;;
	"HFS")
		fsck.hfsplus -y $lvol_name
		lvol_fs="hfs"
		;;
	"HFS+")
		modules="hfsplus"
		fsck.hfsplus -y $lvol_name
		lvol_fs="hfsplus"
		;;
	"X_ADB_EXT")
		modules="mbcache jbd jbd2"
		lvol_fs="ext"
		;;
	"ext2")
		modules="ext2"
		lvol_fs="ext2"
		;;
	"ext3")
		modules="mbcache jbd jbd2 ext3"
		lvol_fs="ext3"
		;;
	"ext4")
		modules="mbcache jbd jbd2 ext4"
		lvol_fs="ext4"
		;;
	*)
		cmclient SETE $obj.Status Error
		cmclient SETE $obj.X_ADB_DLNA.Folder.Status Error
		help_serialize_unlock "$lockFolder"
		logger -t storage -p daemon.err "ARS 3 - Can't mount file system (type: $lvol_fs)"
		return
		;;
	esac
	for elem in $modules; do
		insmod $elem
	done
	mDir="/mnt/${lvol_name##*/}"
	mkdir $mDir
	case "$lvol_fs" in
	"ntfs")
		ntfs-3g $opts $lvol_name $mDir >/dev/console 2>&1
		;;
	"ext")
		for extfs in ext3 ext2; do
			insmod $extfs
			mount -t $extfs $opts $lvol_name $mDir >/dev/console 2>&1
			mount_ret=$?
			if [ "$mount_ret" = "0" ]; then
				cmclient SETE $obj.FileSystem $extfs
				break
			fi
			rmmod $extfs
		done
		;;
	"hfs")
		insmod hfsplus
		mount -t hfsplus $opts $lvol_name $mDir >/dev/console 2>&1
		mount_ret=$?
		if [ "$mount_ret" = "0" ]; then
			modules="hfsplus"
			lvol_fs="hfsplus"
			cmclient SETE $obj.FileSystem "HFS+"
			[ "$?" = "0" ] || {
				umount -l $mDir
				false
			}
		else
			rmmod hfsplus
			modules="hfs"
			insmod $modules
			mount -t $lvol_fs $opts $lvol_name $mDir >/dev/console 2>&1
		fi
		;;
	*)
		mount -t $lvol_fs $opts $lvol_name $mDir >/dev/console 2>&1
		;;
	esac
	mount_ret="$?"
	if [ "$mount_ret" != "0" ]; then
		for elem in $modules; do
			rmmod $elem
		done
		cmclient SETE $obj.Status Error
		cmclient SETE $obj.X_ADB_DLNA.Folder.Status Error
		help_serialize_unlock "$lockFolder"
		logger -t storage -p daemon.err "ARS 3 - Can't mount file system (type: $lvol_fs error: $mount_ret)"
		return
	fi
	local dev mountpoint type option capacity objfolders folder
	while read -r dev mountpoint type options _; do
		if [ "$dev" = "$lvol_name" ]; then
			case ",$options," in
			*",rw,"*) cmclient SETE $obj.X_ADB_Writable true ;;
			*",ro,"*) cmclient SETE $obj.X_ADB_Writable false ;;
			esac
			break
		fi
	done </proc/mounts
	{
		read -r _
		read -r _ capacity _ _ _
	} <<-EOF
		$(df -k $lvol_name)
	EOF
	cmclient SETE $obj.Capacity $((capacity / 1024))
	cd "$newX_ADB_MountPoint"
	cmclient -v objfolders GETV "$obj.Folder.Name"
	for folder in *; do
		[ ! -d "$newX_ADB_MountPoint/$folder" ] && continue
		[ -h "$newX_ADB_MountPoint/$folder" ] && continue
		case "$folder" in
		.trash | lost-found | . | "\$RECYCLE.BIN")
			continue
			;;
		esac
		case "$NEWLINE$objfolders$NEWLINE" in
		*"$NEWLINE$folder$NEWLINE"*)
			continue
			;;
		*)
			cmclient -v idxfolder ADD $obj.Folder
			objfolder="$obj.Folder.$idxfolder"
			cmclient SET $objfolder.Name "$folder"
			;;
		esac
	done
	cmclient -v objfolders GETV $obj.Folder.Name
	[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
	IFS=$NEWLINE
	for folder in $objfolders; do
		case "$folder" in
		.trash | lost-found | . | "*" | "\$RECYCLE.BIN")
			continue
			;;
		esac
		if ! check_path_traversal "$folder"; then
			logconsole "Cleanup path traversal folder \"$newX_ADB_MountPoint/$folder\""
			cmclient -u "$AH_NAME$obj" DEL "$obj.Folder.[Name=$folder]"
		fi
		if [ ! -d "$newX_ADB_MountPoint/$folder" ]; then
			logconsole "Cleanup orphaned folder \"$newX_ADB_MountPoint/$folder\""
			cmclient -u "$AH_NAME$obj" DEL "$obj.Folder.[Name=$folder]"
		fi
		if [ -h "$newX_ADB_MountPoint/$folder" ]; then
			logconsole "Cleanup symlink folder \"$newX_ADB_MountPoint/$folder\""
			cmclient -u "$AH_NAME$obj" DEL "$obj.Folder.[Name=$folder]"
		fi
	done
	[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
	cd -
	cmclient SETE "$obj.Status" "Online"
	[ -e /etc/ah/helper_dlna.sh ] && help_dlna_lvol_online $obj
	[ -e /etc/ah/helper_SystemLog.sh ] && help_systemlog_lvol_online_change $obj
	/usr/sbin/usb_hotplug_sw_upgrade.sh "$obj" &
	cmclient SET "Device.Services.StorageService.1.HTTPServer.[Enable=true].X_ADB_Reset" "true"
	cmclient SET "Device.Services.StorageService.1.HTTPSServer.[Enable=true].X_ADB_Reset" "true"
	cmclient SET "Device.Services.StorageService.1.X_ADB_HTTPServerRemote.[Enable=true].X_ADB_Reset" "true"
	cmclient SET "Device.Services.StorageService.1.X_ADB_HTTPSServerRemote.[Enable=true].X_ADB_Reset" "true"
	help_serialize_unlock "$lockFolder"
}
service_umount_lvol() {
	local flag lockDir lvobj lvobjs setm lvolPhyRef phyStatus
	cmclient -v spoolPartition GETV Device.Services.X_ADB_PrinterService.SpoolPartition
	if [ "$spoolPartition" = "$obj" ]; then
		cmclient "SETM Device.Services.X_ADB_PrinterService.SpoolEnabled=false	Device.Services.X_ADB_PrinterService.SpoolPartition="
	fi
	cmclient -v lvolPhyRef GETV $obj.PhysicalReference
	cmclient -v phyStatus GETV $lvolPhyRef.Status
	setm=${setm:+$setm	}$obj.Status=Offline
	[ "$phyStatus" != "Online" ] && setm=${setm:+$setm	}"$obj.X_ADB_MountPoint=	$obj.Name="
	[ -e /etc/ah/helper_dlna.sh ] && help_dlna_lvol_offline $obj
	cmclient -u dummy SETM "$setm"
	[ -e /etc/ah/helper_SystemLog.sh ] && help_systemlog_lvol_online_change $obj
	if [ -n "$oldName" ]; then
		sync
		lockDir=$(help_serialize_nowait "$lockFolder" notrap)
		umount -l "$oldX_ADB_MountPoint"
		case "$oldFileSystem" in
		"HFS+")
			rmmod hfsplus
			;;
		"NTFS")
			rmmod fuse
			;;
		"FAT16" | "FAT32")
			rmmod vfat
			rmmod fat
			;;
		"ext2")
			rmmod ext2
			;;
		"ext3")
			rmmod ext3
			;;
		"ext4")
			rmmod ext4
			;;
		esac
		help_serialize_unlock "$lockFolder"
	fi
	(cmclient SET "Device.Services.StorageService.1.UserAccount.[Enable=true].X_ADB_Refresh" "true") &
	if [ -e /etc/ah/HTTPServer.sh ]; then
		cmclient SET "Device.Services.StorageService.1.HTTPServer.[Enable=true].X_ADB_Reset" "true"
	fi
}
service_config() {
	local folder objs
	if [ "$setX_ADB_DeleteFolders" = "1" -a "$newX_ADB_DeleteFolders" = "true" ]; then
		cmclient -v objs GETO "$obj.Folder"
		for folder in $objs; do
			cmclient DEL "$folder"
		done
	else
		if [ $changedEnable -eq 1 ]; then
			local physStatus="Online"
			cmclient -v physStatus GETV "%($obj.PhysicalReference).Status"
			[ "$newEnable" = "true" ] && [ "$physStatus" = "Online" -o "$physStatus" = "X_ADB_Loading" ] && service_mount_lvol
			[ "$newEnable" = "false" -a "$newStatus" != "Offline" ] && service_umount_lvol
		elif [ $changedStatus -eq 1 -a "$newEnable" = "true" ]; then
			[ "$newStatus" = "Online" ] && service_mount_lvol
			[ "$newStatus" != "Online" ] && service_umount_lvol
		fi
	fi
}
case "$op" in
"s")
	service_config
	;;
esac
exit 0
