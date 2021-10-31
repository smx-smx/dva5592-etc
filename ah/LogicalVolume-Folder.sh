#!/bin/sh
AH_NAME="LogicalVolume-Folder"
[ "$user" = "$AH_NAME$obj" ] && exit 0
[ "$user" = "yacs" ] && exit 0
[ "$user" = "boot" ] && exit 0
[ "$user" = "dummy" ] && exit 0
[ -f /tmp/upgrading.lock ] && [ "$op" != "g" ] && exit 0
. /etc/ah/helper_serialize.sh && help_serialize_nowait "$AH_NAME" > /dev/null
. /etc/ah/helper_storage.sh
need_refresh() {
[ "$changedName" = "1" ]  && return 0
return 1
}
service_delete() {
local lvobj="${obj%%.Folder.*}"
local lvstatus
local mntpoint
check_path_traversal "$oldName" || return
cmclient -v mntpoint GETV $lvobj.X_ADB_MountPoint
cmclient -v lvstatus GETV $lvobj.Status
if [ "$lvstatus" = "Online" -a -n "$mntpoint" -a -n "$oldName" ]; then
rm -rf "$mntpoint/$oldName"
sync
fi
}
service_config() {
local lvobj="${obj%%.Folder.*}"
local lvstatus
local mntpoint
check_path_traversal "$oldName" || return
check_path_traversal "$newName" || exit 1
cmclient -v mntpoint GETV $lvobj.X_ADB_MountPoint
cmclient -v lvstatus GETV $lvobj.Status
if [ "$lvstatus" = "Online" -a -n "$mntpoint" ]; then
if [ -n "$newName" -a "$changedName" = "1" ]; then
if [ -h "$mntpoint/$newName" ]; then
exit 2
fi
if [ -n "$oldName" ]; then
mv "$mntpoint/$oldName" "$mntpoint/$newName"
[ $? -eq 0 ] || exit 2
else
if [ ! -d "$mntpoint/$newName" ]; then
mkdir -p "$mntpoint/$newName"
[ $? -eq 0 ] || exit 2
fi
fi
fi
fi
}
case "$op" in
"d")
service_delete
;;
"s")
need_refresh && service_config
;;
esac
exit 0
