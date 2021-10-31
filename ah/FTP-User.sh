#!/bin/sh
AH_NAME="FTP-User"
OBJ_FTPUSER="UserAccount"
. /etc/ah/helper_serialize.sh && help_serialize > /dev/null
. /etc/ah/FTP-Server-Common.sh
needRefresh() {
[ "$setX_ADB_AllowFTPAccessRefresh" = "1" -a \
"$newX_ADB_AllowFTPAccessRefresh" = "true" ] && return 0
[ "$setX_ADB_AllowRemoteFTPAccess" = "1" -a \
"$newX_ADB_AllowRemoteFTPAccess" = "true" ] && return 0
[ "$setAllowFTPAccess" = "1" -a \
"$newAllowFTPAccess" = "true" ] && return 0
[ "$changedUsername" = "1" ] && return 0
[ "$changedPassword" = "1" ] && return 0
[ "$changedEnable" = "1" ] && return 0
[ "$changedX_ADB_RemoteFTPStartingFolder" = "1" ] && return 0
[ "$changedX_ADB_FTPStartingFolder" = "1" ] && return 0
return 1
}
service_reconf() {
[ -n "$oldUsername" ] && ftpdeluser "$oldUsername" Remote
[ -n "$oldUsername" ] && ftpdeluser "$oldUsername" Local
if [ "$newX_ADB_AllowRemoteFTPAccess" = "true" -a "$newEnable" = "true" -a -n "$newUsername" ]; then
if [ -z "$newX_ADB_RemoteFTPStartingFolder" ]; then
local ftpobj="Services.StorageService.1.X_ADB_FTPServerRemote"
newX_ADB_RemoteFTPStartingFolder="`cmclient GETV $ftpobj.X_ADB_StartingFolder`"
fi
if [ -n "$newX_ADB_RemoteFTPStartingFolder" ]; then
local logicalVolume="${newX_ADB_RemoteFTPStartingFolder%%.Folder.*}"
local logicalVolumeName="`cmclient GETV $logicalVolume.X_ADB_MountPoint`"
local ftpStartingFolderName="`cmclient GETV $newX_ADB_RemoteFTPStartingFolder.Name`"
logicalVolumeName="${logicalVolumeName%%/}/"
ftpStartingFolderName="$logicalVolumeName${ftpStartingFolderName##$logicalVolumeName}"
ftpadduser "$newUsername" "$newPassword" "$ftpStartingFolderName" Remote
fi
fi
if [ "$newAllowFTPAccess" = "true" -a "$newEnable" = "true" -a -n "$newUsername" ]; then
if [ -z "$newX_ADB_FTPStartingFolder" ]; then
local ftpobj="Services.StorageService.1.FTPServer"
newX_ADB_FTPStartingFolder="`cmclient GETV $ftpobj.X_ADB_StartingFolder`"
fi
if [ -n "$newX_ADB_FTPStartingFolder" ]; then
local logicalVolume="${newX_ADB_FTPStartingFolder%%.Folder.*}"
local logicalVolumeName="`cmclient GETV $logicalVolume.X_ADB_MountPoint`"
local ftpStartingFolderName="`cmclient GETV $newX_ADB_FTPStartingFolder.Name`"
logicalVolumeName="${logicalVolumeName%%/}/"
ftpStartingFolderName="$logicalVolumeName${ftpStartingFolderName##$logicalVolumeName}"
ftpadduser "$newUsername" "$newPassword" "$ftpStartingFolderName" Local
fi
fi
}
case "$op" in
d)
[ -n "$oldUsername" ] && ftpdeluser "$oldUsername" Remote
[ -n "$oldUsername" ] && ftpdeluser "$oldUsername" Local
;;
s)
needRefresh && service_reconf
;;
esac
exit 0
