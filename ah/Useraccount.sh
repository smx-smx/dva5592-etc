#!/bin/sh
AH_NAME="UserAccount"
[ "$user" = "$AH_NAME$obj" ] && exit 0
. /etc/ah/helper_serialize.sh && help_serialize >/dev/null
. /etc/ah/helper_users.sh
STORAGE_DESC="Storage User"
STORAGE_UID=5000
STORAGE_GUID=5000
_smbpasswd() {
	local smbpasswd_exe="$(which smbpasswd)"
	local ret=1
	if [ -n "$smbpasswd_exe" ]; then
		: >>/tmp/samba/smbpasswd
		$smbpasswd_exe "$@" && ret=0
	fi
	return $ret
}
_add_user() {
	local ret=0
	local username="$1"
	local password="$2"
	local id="$3"
	local userobj=""
	if ! _is_unix_user "$username"; then
		_add_unix_user "$username" "$password" "$(($STORAGE_UID + $id))" "$STORAGE_GUID" "$STORAGE_DESC" || ret=1
	fi
	if [ $ret = 0 ]; then
		_smbpasswd "$username" "$password"
	fi
	return $ret
}
_disable_user() {
	local ret=0
	local username="$1"
	local userobj
	cmclient -v userobj GETO "Device.Users.User.[Username=$username]"
	if [ -z "$userobj" ]; then
		_delete_unix_user "$username" || ret=1
	fi
	if [ $ret -eq 0 ]; then
		_smbpasswd -del "$username"
	fi
	return $ret
}
_add_to_groups() {
	local username="$1"
	local groups="$2"
	local groupobj
	local groupname
	local groupenable
	IFS=,
	for groupobj in $groups; do
		cmclient -v groupenable GETV "$groupobj.Enable"
		if [ "$groupenable" = "true" ]; then
			cmclient -v groupname GETV "$groupobj.GroupName"
			_adduser_unix_group "$groupname" "$username"
		fi
	done
	unset IFS
}
_remove_from_groups() {
	local username="$1"
	local groups="$2"
	local groupobj
	local groupname
	local groupenable
	IFS=,
	for groupobj in $groups; do
		cmclient -v groupenable GETV "$groupobj.Enable"
		if [ "$groupenable" = "true" ]; then
			cmclient -v groupname GETV "$groupobj.GroupName"
			_deluser_unix_group "$groupname" "$username"
		fi
	done
	unset IFS
}
service_config() {
	local ret=1
	local uid="${obj##*.}"
	_lock_passwd
	_lock_group
	if _is_valid_user "$newUsername"; then
		if [ "$oldEnable" = "true" ] && _is_valid_user "$oldUsername"; then
			_remove_from_groups "$oldUsername" "$oldUserGroupParticipation"
			_disable_user "$oldUsername"
		fi
		if [ "$newEnable" = "true" ]; then
			_add_user "$newUsername" "$newPassword" "$uid" && ret=0
			[ $ret -eq 0 ] && _add_to_groups "$newUsername" "$newUserGroupParticipation"
		else
			ret=0
		fi
	fi
	_unlock_group
	_unlock_passwd
	return $ret
}
service_delete() {
	_lock_passwd
	_lock_group
	if [ "$oldEnable" = "true" ] && _is_valid_user "$oldUsername"; then
		_remove_from_groups "$oldUsername" "$oldUserGroupParticipation"
		_disable_user "$oldUsername"
	fi
	_unlock_group
	_unlock_passwd
}
need_refresh() {
	[ "$changedUserGroupParticipation" = "1" ] && return 0
	[ "$changedEnable" = "1" ] && return 0
	[ "$changedPassword" = "1" ] && return 0
	[ "$changedUsername" = "1" ] && return 0
	[ "$setX_ADB_Refresh" = "1" -a "$newX_ADB_Refresh" = "true" ] && return 0
	return 1
}
case "$op" in
"d")
	service_delete
	;;
"s")
	if need_refresh; then
		service_config || exit 1
	fi
	;;
esac
exit 0
