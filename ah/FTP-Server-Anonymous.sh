#!/bin/sh
AH_NAME="FTP-Server-Anonymous"
[ "$user" = "yacs" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
. /etc/ah/FTP-Server-Common.sh
needRefresh() {
	[ "$setEnable" = "1" -a "$newEnable" = "true" ] && return 0
	[ "$changedStartingFolder" = "1" ] && return 0
	[ "$changedReadOnlyAccess" = "1" ] && return 0
	[ "$setX_ADB_Refresh" = "1" -a "$newX_ADB_Refresh" = "true" ] && return 0
	[ "$changedReadOnlyAccess" = "1" ] && return 0
	[ "$changedX_ADB_OnlyAnonymousUser" = "1" ] && return 0
	return 1
}
fillenv() {
	[ -z "$obj" ] && return 1
	newEnable="$(cmclient GETV $obj.Enable)"
	newStartingFolder="$(cmclient GETV $obj.StartingFolder)"
	newReadOnlyAccess="$(cmclient GETV $obj.ReadOnlyAccess)"
	return 0
}
updatepasswd() {
	. /etc/ah/helper_serialize.sh
	help_serialize passwd.lock notrap >/dev/null
	sed -i "/^$FTPUSER:/d" /tmp/passwd
	if [ "$newEnable" = "true" ]; then
		if [ -z "$newStartingFolder" ]; then
			pobj="${obj%.*}"
			newStartingFolder="$(cmclient GETV $pobj.X_ADB_StartingFolder)"
		fi
		local logicalVolume="${newStartingFolder%%.Folder.*}"
		local logicalVolumeName="$(cmclient GETV $logicalVolume.X_ADB_MountPoint)"
		local newStartingFolderName="$(cmclient GETV $newStartingFolder.Name)"
		logicalVolumeName="${logicalVolumeName%%/}/"
		newStartingFolderName="$logicalVolumeName${newStartingFolderName##$logicalVolumeName}"
		case "$newStartingFolderName" in
		*/../*) ;;

		/mnt/sd*)
			if [ "$newReadOnlyAccess" = "true" ]; then
				echo "$FTPUSER:x:65534:65534::$newStartingFolderName:/bin/false"
			else
				echo "$FTPUSER:x:0:0::$newStartingFolderName:/bin/false"
			fi >>/tmp/passwd
			;;
		esac
	fi
	help_serialize_unlock passwd.lock >/dev/null
}
case "$op" in
s)
	if needRefresh; then
		updatepasswd
		if [ "$changedEnable" = "1" -o "$changedReadOnlyAccess" = "1" -o "$changedX_ADB_OnlyAnonymousUser" = "1" ]; then
			pobj="${obj%.*}"
			cmclient SET "$pobj".X_ADB_Refresh true
		fi
	fi
	;;
refresh)
	fillenv && updatepasswd
	;;
esac
exit 0
