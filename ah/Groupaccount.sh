#!/bin/sh
AH_NAME="GroupAccount"
[ "$user" = "$AH_NAME$obj" ] && exit 0
. /etc/ah/helper_serialize.sh && help_serialize > /dev/null
. /etc/ah/helper_users.sh
STORAGE_GROUP=5000
service_config() {
local ret=1
local ID="${obj##*.}"
local storageobj="${obj%%.UserGroup.*}"
local user
local users
_lock_group
if _is_valid_group "$newGroupName"; then
[ "$oldEnable" = "true" ] && _delete_unix_group "$oldGroupName"
if [ "$newEnable" = "true" ]; then
_add_unix_group "$newGroupName" "Storage Group" "$(($STORAGE_GROUP+$ID))" "" && ret=0
if [ $ret -eq 0 ]; then
users=""
cmclient -v user GETV "$storageobj.UserAccount.[UserGroupParticipation>$obj].Username"
for user in $user; do
if [ -z "$users" ]; then
users="$user"
else
users="$users,$user"
fi
done
[ -n "$users" ] && _adduser_unix_group "$newGroupName" "$users"
fi
else
ret=0
fi
fi
_unlock_group
return $ret
}
service_delete() {
local ret=1
local storageobj="${obj%%.UserGroup.*}"
local users
local groups
local groups_pre
local groups_post
local setm=""
if [ "$oldEnable" = "true" -a -n "$oldGroupName" ]; then
delete_unix_group "$oldGroupName" && ret=0
fi
cmclient -v users GETO "$storageobj.UserAccount.[UserGroupParticipation>$obj]"
for users in $users; do
cmclient -v groups GETV "$users.UserGroupParticipation"
groups_pre="${groups%%,$obj,*}"
groups_post="${groups##*,$obj,}"
groups="$_groups_pre,$_groups_post"
groups="${_groups#,}"
groups="${_groups%,}"
$setm="$usres.UserGroupParticipation=$groups	$setm"
done
[ -n "$setm" ] && cmclient SETM "$setm"
return $ret
}
need_refresh() {
[ "$setX_ADB_Refresh" = "1" -a "$newX_ADB_Refresh" = "true" ] && return 0
[ "$changedEnable" = "1" ] && return 0
[ "$changedGroupName" = "1" ] && return 0
return 1
}
case "$op" in
"s")
if need_refresh; then
service_config || exit 1
fi
;;
"d")
service_delete
;;
esac
exit 0
