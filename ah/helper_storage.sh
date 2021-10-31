#!/bin/sh
LOCK_FOLDERNAME="foldername"
SAMBA_CONF_FILE_SKIP="smb.conf.skip"
USHARE_CONF_FILE_SKIP="ushare.conf.skip"
lockFolder="storage_usbehlock"
logconsole() {
	echo "STORAGE: " "$@" >/dev/console
}
getUniqueShareName() {
	local folderobj="$1"
	local foldername="$2"
	local found=""
	local folderobjs="${folderobj%.*}"
	local volumeobj="${folderobj%.Folder.*}"
	local storageobj="${volumeobj%.LogicalVolume.*}"
	local i
	local lockdir=$(help_serialize_nowait "$LOCK_FOLDERNAME" notrap)
	foldername="${foldername##*/}"
	if [ "$foldername" = "." ]; then
		disk="$(cmclient GETV $volumeobj.PhysicalReference)"
		foldername="$(cmclient GETV $disk.Name)"
	fi
	i=1
	shareName="$foldername"
	while :; do
		folderName="$(cmclient GETO $storageobj.LogicalVolume.Folder.[X_ADB_ShareName=$shareName])"
		if [ -z "$folderName" ]; then
			found="$shareName"
			break
		fi
		shareName="$shareName$i"
		i=$(($i + 1))
	done
	cmclient -u dummy SET "$folderobj.X_ADB_ShareName" "$shareName"
	help_serialize_unlock "$LOCK_FOLDERNAME" 2>/dev/null
}
getUniqueShareNameLetters() {
	local folder="$1" alpha="ABCDEFGHIJKLMNOPQRSTUVWXYZ" name="A" cut=0 tmp
	help_serialize_nowait "$LOCK_FOLDERNAME" notrap
	while :; do
		cmclient -v tmp GETO "Device.Services.StorageService.LogicalVolume.Folder.[X_ADB_ShareName=$name]"
		[ ${#tmp} -eq 0 ] && break
		while [ ${#name} -ne 0 ]; do
			if [ "${name##${name%?}}" != "Z" ]; then
				tmp="${alpha#*${name##${name%?}}}"
				name="${name%?}${tmp%%${tmp#?}}"
				break
			else
				cut=$((cut + 1))
				name="${name%?}"
			fi
		done
		[ ${#name} -eq 0 ] && name="A"
		while [ $cut -gt 0 ]; do
			name="${name}A"
			cut=$((cut - 1))
		done
	done
	cmclient -u dummy SET "${folder}.X_ADB_ShareName $name"
	help_serialize_unlock "$LOCK_FOLDERNAME"
}
_findfs() {
	local harddisk=${1}
	local offset=${2}
	local value=${3}
	[ -z "${offset}" -o -z "${value}" ] && return 1
	local size=$((($(echo -n "${value}" | wc -c) + 1) / 2))
	[ "$(hexdump -v -e '1/1 "%X"' -s "$((${offset}))" -n "${size}" "${harddisk}" 2>/dev/null)" = "${value}" ]
	return $?
}
findfs() {
	if [ ! -r "${1}" ]; then
		echo "Cannot read ${1}." >&2
		exit 1
	fi
	while read x; do
		local offset="$(echo "${x}" | cut -d : -f 2)"
		local value="$(echo "${x}" | cut -d : -f 3)"
		if _findfs "${1}" "${offset}" "${value}"; then
			local fs="$(echo "${x}" | cut -d : -f 1)"
			echo "${fs}"
			return 0
		fi
	done <<EOF
UFS2:0x1055C:1915419
X_ADB_EXT:0x438:53EF
FAT16:54:4641543136202020
FAT32:82:4641543332202020
X_ADB_msdos:54:4641543132202020
NTFS:3:4E54465320202020
XFS:0:42534658
REISER:0x10034:5265497345724673
REISER:0x10034:526549734572324673
HFS+:0x400:482B
HFS:0x400:4244
EOF
	return 1
}
check_path_traversal() {
	case "/$1/" in
	*/../*)
		return 1
		;;
	esac
	return 0
}
