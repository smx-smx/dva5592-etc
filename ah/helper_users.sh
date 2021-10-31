#!/bin/sh
command -v help_serialize >/dev/null || . /etc/ah/helper_serialize.sh
PASSWD_FILE="/etc/passwd"
PASSWD_FILE_ORIG="/etc/passwd.orig"
PASSWD_FILE_LOCK="passwd.lock"
GROUP_FILE="/etc/group"
GROUP_FILE_ORIG="/etc/group.orig"
GROUP_FILE_LOCK="group.lock"
_protect() {
if [ -n "$2" ]; then
eval "$1() { local ret=1 ; _lock_$2 ; _$1 \"\$@\" && ret=0 ; _unlock_$2 ; return \$ret ; }"
else
eval "$1() { _$1 \"\$@\" ; }"
fi
}
_lock_passwd() {
local lockdir="`help_serialize_nowait $PASSWD_FILE_LOCK notrap`"
}
_unlock_passwd() {
help_serialize_unlock $PASSWD_FILE_LOCK
}
_lock_group() {
local lockdir="`help_serialize_nowait $GROUP_FILE_LOCK notrap`"
}
_unlock_group() {
help_serialize_unlock $GROUP_FILE_LOCK
}
_is_valid_user() {
local _name
local _ret=0
[ -z "$1" ] && return 1
IFS=:
while read _name _; do
if [ "$_name" = "$1" ]; then
_ret=1
break
fi
done < $PASSWD_FILE_ORIG
unset IFS
return $_ret
}
_is_valid_group() {
local _name
local _ret=0
[ -z "$1" ] && return 1
IFS=:
while read _name _; do
if [ "$_name" = "$1" ]; then
_ret=1
break
fi
done < $GROUP_FILE_ORIG
unset IFS
return $_ret
}
_is_unix_user() {
local username="$1"
local _username
local _
local found=1
IFS=:
while read _username _ _ _ _ _ _; do
if [ "$_username" = "$username" ]; then
found=0
break
fi
done < $PASSWD_FILE
unset IFS
return $found
}
_password_unix_user() {
local username="$1"
local password="$2"
printf "%s\n%s\n" "$password" "$password" | passwd $username
}
_delete_unix_user() {
local username="$1"
local tempfile
local ret=1
local _username
local _password
local _uid
local _guid
local _desc
local _home
local _shell
_is_valid_user "$username" || return $ret
tempfile="`mktemp`"
IFS=:
while read _username _password _uid _guid _desc _home _shell; do
if [ "$_username" != "$username" ]; then
echo "$_username:$_password:$_uid:$_guid:$_desc:$_home:$_shell" >> $tempfile
else
ret=0
fi
done < $PASSWD_FILE
unset IFS
cat $tempfile > $PASSWD_FILE
rm $tempfile
return $ret
}
_add_unix_user() {
local username="$1"
local password="$2"
local uid="$3"
local guid="$4"
local desc="$5"
local home="${6:-/tmp/nohome}"
local shell="${7:-/bin/false}"
local nopass="$8"
_is_valid_user "$username" || return 1
mkdir -p "$home"
echo "$username:x:$uid:$guid:$desc:$home:$shell" >> $PASSWD_FILE
[ -z "$nopass" ] && _password_unix_user "$username" "$password"
return 0
}
_enable_unix_user() {
local username="$1"
local enable="$2"
local ret=1
_is_valid_user "$username" || return $ret
if _is_unix_user "$username"; then
if [ "$enable" = "true" ]; then
passwd -u $username > /dev/null 2>&1
else
passwd -l $username > /dev/null 2>&1
fi
ret=0
fi
return $ret
}
_changename_user_unix() {
local username="$1"
local newusername="$2"
local tempfile
local found=1
local _username
local _password
local _uid
local _guid
local _desc
local _home
local _shell
[ -n "$username" ] && _is_valid_user "$username" || return $found
_is_valid_user "$newusername" || return $found
tempfile="`mktemp`"
IFS=:
while read _username _password _uid _guid _desc _home _shell; do
if [ "$_username" != "$username" ]; then
echo "$_username:$_password:$_uid:$_guid:$_desc:$_home:$_shell" >> $tempfile
else
echo "$newusername:$_password:$_uid:$_guid:$_desc:$_home:$_shell" >> $tempfile
found=0
fi
done < $PASSWD_FILE
unset IFS
cat $tempfile > $PASSWD_FILE
rm $tempfile
return $found
}
_is_unix_group() {
local groupname="$1"
local _groupname
local _
local found=1
IFS=:
while read _groupname _ _; do
if [ "$_groupname" = "$groupname" ]; then
found=0
break
fi
done < $GROUP_FILE
unset IFS
return $found
}
_delete_unix_group() {
local groupname="$1"
local _groupname
local _desc
local _users
local found=1
local tmpfile
_is_valid_group "$groupname" || return $found
tmpfile="`mktemp`"
IFS=:
while read _groupname _desc _users; do
if [ "$_groupname" != "$groupname" ]; then
echo "$_groupname:$_desc:$_users" >> $tmpfile
else
found=0
fi
done < $GROUP_FILE
unset IFS
cat $tmpfile > $GROUP_FILE
rm $tmpfile
return $found
}
_add_unix_group() {
local groupname="$1"
local desc="$2"
local guid="$3"
local users="$4"
_is_valid_group "$groupname" || return 1
_delete_unix_group "$groupname"
echo "$groupname:$desc:$guid:$users" >> $GROUP_FILE
return 0
}
_adduser_unix_group() {
local groupname="$1"
local found=1
local _groupname
local _desc
local _guid
local _users
_is_valid_group "$groupname" || return $found
tmpfile="`mktemp`"
IFS=:
while read _groupname _desc _guid _users; do
if [ "$_groupname" != "$groupname" ]; then
echo "$_groupname:$_desc:$_guid:$_users" >> $tmpfile
else
shift
while [ -n "$1" ]; do
if [ -z "$_users" ]; then
_users="$1"
else
_users="$_users,$1"
fi
shift
done
echo "$_groupname:$_desc:$_guid:$_users" >> $tmpfile
found=0
fi
done < $GROUP_FILE
unset IFS
cat $tmpfile > $GROUP_FILE
rm $tmpfile
return $found
}
_deluser_unix_group() {
local groupname="$1"
local found=1
local _groupname
local _desc
local _guid
local _users
local _users_pre
local _users_post
_is_valid_group "$groupname" || return $found
tmpfile="`mktemp`"
IFS=:
while read _groupname _desc _guid _users; do
if [ "$_groupname" != "$groupname" ]; then
echo "$_groupname:$_desc:$_guid:$_users" >> $tmpfile
else
shift
_users=",$_users,"
while [ -n "$1" -a -n "$_users" ]; do
_users_pre="${_users%%,$1,*}"
_users_post="${_users##*,$1,}"
_users="$_user_pre,$_users_post"
_users="${_users#,}"
_users="${_users%,}"
shift
done
echo "$_groupname:$_desc:$_guid:$_user" >> $tmpfile
found=0
fi
done < $GROUP_FILE
unset IFS
cat $tmpfile > $GROUP_FILE
rm $tmpfile
return $found
}
_protect is_valid_user
_protect is_unix_user passwd
_protect password_unix_user passwd
_protect delete_unix_user passwd
_protect add_unix_user passwd
_protect enable_unix_user passwd
_protect changename_user_unix passwd
_protect is_valid_group group
_protect is_unix_group group
_protect delete_unix_group group
_protect add_unix_group group
_protect adduser_unix_group group
_protect deluser_unix_group group
