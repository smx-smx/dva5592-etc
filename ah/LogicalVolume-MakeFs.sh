#!/bin/sh
service_format() {
	local phyRef="$1"
	local lvol_list="$2"
	local lvol_name=""
	local filesystem_val=""
	local newPartId=""
	local oldPartId=""
	local phyName=""
	local setm_b=""
	cmclient -v lvol_name GETV "$obj.Name"
	cmclient -v filesystem_val GETV "$obj.X_ADB_Format"
	case "$filesystem_val" in
	ext2)
		newPartId="83"
		mkfs.ext2 $lvol_name >/dev/null 2>&1
		;;
	ext3)
		newPartId="83"
		mkfs.ext3 $lvol_name >/dev/null 2>&1
		;;
	ext4)
		newPartId="83"
		mkfs.ext4 $lvol_name >/dev/null 2>&1
		;;
	NTFS)
		newPartId="7"
		mkntfs -f $lvol_name >/dev/null 2>&1
		;;
	X_ADB_msdos)
		newPartId="b"
		mkdosfs $lvol_name >/dev/null 2>&1
		;;
	FAT16)
		newPartId="b"
		mkfs.vfat $lvol_name -F 16 >/dev/null 2>&1
		;;
	FAT32)
		newPartId="b"
		mkfs.vfat $lvol_name -F 32 >/dev/null 2>&1
		;;
	HFS+)
		newPartId="af"
		mkfs.hfsplus $lvol_name >/dev/null 2>&1
		;;
	HFS)
		newPartId="af"
		mkfs.hfsplus -h $lvol_name >/dev/null 2>&1
		;;
	*)
		exit 0
		;;
	esac
	if [ "$?" -eq 0 ] && [ -n "$newPartId" ]; then
		cmclient -v phyName GETV "$phyRef.X_ADB_DeviceName"
		lvolBaseName=$(basename $lvol_name 2>/dev/null)
		lvolIndex=$(echo -n $lvolBaseName | sed 's/sd[a-z]*//g')
		oldPartId=$(fdisk -l $phyName | grep $lvol_name | tr -s ' ' | cut -d ' ' -f5)
		if [ "$oldPartId" != "$newPartId" ]; then
			fdisk $phyName >/dev/null 2>&1 <<EOF
t
${lvolIndex}
${newPartId}
w
EOF
		fi
	fi
	cmclient SET $obj.X_ADB_DeleteFolders true >/dev/null
	setm_b="$obj.FileSystem=$filesystem_val	$obj.Status=Offline"
	cmclient SETM "$setm_b" >/dev/null
	setm_b=""
	cmclient -u "dummy" ADD $obj.Folder >/dev/null
	cmclient -u "dummy" SET $obj.Folder.1.Name "." >/dev/null
	for lvolObj in $lvol_list; do
		if [ "$lvolObj" = "$obj" ]; then
			continue
		else
			[ -z "$setm_b" ] && setm_b="$lvolObj.Enable=true	$lvolObj.Status=Online" ||
				setm_b="$setm_b	$lvolObj.Enable=true	$lvolObj.Status=Online"
		fi
	done
	if [ -n "$setm_b" ]; then
		setm_b="$setm_b	$obj.Status=Online	$obj.Enable=true"
	else
		setm_b="$obj.Status=Online	$obj.Enable=true"
	fi
	cmclient SETM "$setm_b" >/dev/null
	cmclient SET $obj.Folder.1.X_ADB_SambaRefresh "true" >/dev/null
}
[ -n "$1" ] && service_format "$1" "$2"
cmclient -u "dummy" SET "$obj.Status" "Online" >/dev/null
exit 0
