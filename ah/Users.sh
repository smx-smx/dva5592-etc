#!/bin/sh
USERS_DEBUG=0
AH_NAME="Users"
AH_VERSION="0.1"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$user" = "yacs" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_serialize.sh && help_serialize passwd.lock > /dev/null
DEFAULT_SHELL="/bin/clish"
DEFAULT_HOME="/root"
DEFAULT_BASEID=1000
DEFAULT_ADMIN_GID=100
DEFAULT_POWER_GID=200
DEFAULT_NORMAL_GID=300
DEFAULT_LOCAL=localaccess
DEFAULT_REMOTE=remoteaccess
PASSWDFILE=/etc/passwd
GROUPFILE=/etc/group
lecho() {
if [ $USERS_DEBUG = 1 ]; then
echo "$@"
fi
}
del_gui_sessions() {
local username="$1"
sid=`awk -F\; -v usr="$username" '{if ($1 == usr) print $4}' < /tmp/ui_session`
for sid in $sid; do
rm /tmp/ui_session_$sid
sed -i "/${sid}/d" /tmp/ui_session
done
}
del_from_unix_group() {
local UserGroup="$1"
local UserName="$2"
[ -z "$UserName" ] && return 1
local TMPFILE=`mktemp`
while read groupentry; do
groupname=${groupentry%%:*}
if [ "$groupname" = "$UserGroup" ]; then
IFS=":" read -r groupname x gid userslist <<-EOF
$groupentry
EOF
if help_is_in_list "$userslist" "$UserName"; then
set -f
IFS=,
set -- $userslist
unset IFS
set +f
unset userslist
for arg; do
[ "$arg" != "$UserName" ] && userslist="${userslist+$userslist,}$arg"
done
groupentry="$groupname:$x:$gid:$userslist"
fi
fi
echo "$groupentry" >> $TMPFILE
done < $GROUPFILE
cat $TMPFILE > $GROUPFILE
rm -f $TMPFILE
}
add_to_unix_group() {
local UserGroup="$1"
local UserName="$2"
[ -z "$UserName" ] && return 1
local TMPFILE=`mktemp`
while read -r groupentry; do
groupname=${groupentry%%:*}
if [ "$groupname" = "$UserGroup" ]; then
IFS=":" read -r groupname x gid userslist <<-EOF
$groupentry
EOF
if help_is_in_list "$userslist" "$UserName"; then
echo "$groupentry" >> $TMPFILE
else
if [ -z "$userslist" ]; then
echo "$groupname:$x:$gid:$UserName" >> $TMPFILE
else
echo "$groupentry,$UserName" >> $TMPFILE
fi
fi
else
echo "$groupentry" >> $TMPFILE
fi
done < $GROUPFILE
cat $TMPFILE > $GROUPFILE
rm -f $TMPFILE
}
is_unix_user() {
local UserName=$1 FileName=${2:-$PASSWDFILE} username passwdentry
[ -z "$UserName" ] && return 1
while read -r passwdentry; do
username=${passwdentry%%:*}
[ "$UserName" = "$username" ] && return 0
done < "$FileName"
return 1
}
verify_password() {
local UserName=$1
local Password=$2
local tmp rules
cmclient -v tmp GETV Device.Users.X_ADB_PasswordMinLength
[ ${#Password} -ge "$tmp" ] || return 1
cmclient -v rules GETV Device.Users.X_ADB_PasswordEnforcementRules
set -f
IFS=,
set -- $rules
unset IFS
set +f
for arg; do
case "$arg" in
NoUsername)
tmp=`help_lowercase "$Password"`
case "$tmp" in
*"`help_lowercase $UserName`"*) return 1
;;
esac
;;
OneSpecialCharacterSet1)
tmp=`echo "$Password" | tr -cd '!"$%^&*()\-_+=:;@~#?<>'`
[ ${#tmp} -eq 0 ] && tmp=`help_trcd "'" "$Password"`
[ ${#tmp} -eq 0 ] && return 1
;;
OneDigit)
tmp=`help_trcd "0123456789" "$Password"`
[ ${#tmp} -eq 0 ] && return 1
;;
OneUppercaseLetter)
tmp=`help_trcd "QWERTYUIOPASDFGHJKLZXCVBNM" "$Password"`
[ ${#tmp} -eq 0 ] && return 1
;;
OneLowercaseLetter)
tmp=`help_trcd "qwertyuiopasdfghjklzxcvbnm" "$Password"`
[ ${#tmp} -eq 0 ] && return 1
;;
esac
done
return 0
}
user_get_groupid() {
local UserName=$1
local UserRole=$2
local GroupId=$DEFAULT_NORMAL_GID
if [ -n "$UserName" ]; then
case "$UserRole" in
"AdminUser")
GroupId=$DEFAULT_ADMIN_GID
;;
"PowerUser")
GroupId=$DEFAULT_POWER_GID
;;
"NormalUser")
GroupId=$DEFAULT_NORMAL_GID
;;
*)
GroupId=$DEFAULT_NORMAL_GID
;;
esac
fi
echo -n "$GroupId"
}
user_create_if_not_unix() {
local UserName="$1"
local UserId="$2"
local GroupId="$3"
if [ -n "$UserName" ]; then
if ! is_unix_user "$UserName"; then
echo "$UserName:x:$UserId:$GroupId:$UserName:$DEFAULT_HOME:$DEFAULT_SHELL" >> $PASSWDFILE
add_to_unix_group "root" "$UserName"
fi
fi
}
user_delete() {
local UserName="$1"
if [ -n "$UserName" ] && is_unix_user "$UserName"; then
local tmp=`mktemp` line
while IFS=: read -r line; do
[ "${line%%:*}" != "$UserName" ] && \
printf "%s\n" "$line"
done < $PASSWDFILE > $tmp
cat $tmp > $PASSWDFILE
rm -f $tmp
fi
}
user_add() {
local UserName="$1"
local UserId="$2"
local UserRole="$3"
local UserPassword="$4"
local UserPasswordType="$5"
local UserPasswordSync="$6"
if [ -n "$UserName" ]; then
local GroupId=`user_get_groupid "$UserName" "$UserRole"`
user_delete "$UserName"
user_create_if_not_unix "$UserName" "$UserId" "$GroupId"
if [ -n "$UserPassword" ]; then
user_change_password "$UserName" "$UserPassword" "$UserPasswordType" "$UserPasswordSync"
fi
fi
}
user_change_password_crypt() {
local UserName="$1"
local UserPassword="$2"
local TMPFILE=`mktemp`
while read -r passwdentry; do
username=${passwdentry%%:*}
if [ "$username" = "$UserName" ]; then
IFS=":" read -r username userpassword uid gid usercomment userhome usershell <<-EOF
$passwdentry
EOF
echo "$username:$UserPassword:$uid:$gid:$usercomment:$userhome:$usershell" >> $TMPFILE
else
echo "$passwdentry" >> $TMPFILE
fi
done < $PASSWDFILE
cat $TMPFILE > $PASSWDFILE
rm -f $TMPFILE
}
get_user_password_from_passwd() {
local UserName="$1"
while read -r passwdentry; do
username=${passwdentry%%:*}
if [ "$username" = "$UserName" ]; then
IFS=":" read -r username userpassword uid gid usercomment userhome usershell <<-EOF
$passwdentry
EOF
break
fi
done < $PASSWDFILE
echo -n "$userpassword"
}
user_change_group() {
local UserName="$1"
local UserGroup="$2"
local TMPFILE=`mktemp`
while read -r passwdentry; do
username=${passwdentry%%:*}
if [ "$username" = "$UserName" ]; then
IFS=":" read -r username userpassword uid gid usercomment userhome usershell <<-EOF
$passwdentry
EOF
echo "$username:$userpassword:$uid:$UserGroup:$usercomment:$userhome:$usershell" >> $TMPFILE
else
echo "$passwdentry" >> $TMPFILE
fi
done < $PASSWDFILE
cat $TMPFILE > $PASSWDFILE
rm -f $TMPFILE
}
user_change_password() {
local UserName="$1"
local UserPassword="$2"
local PasswordType="$3"
local PasswordSync="$4"
if [ -n "$UserName" ]; then
if [ "$PasswordType" = "Crypt" -a -n "$PasswordSync" ]; then
user_change_password_crypt "$UserName" "$UserPassword"
else
cat | passwd $UserName > /dev/null 2>&1 << EOF
$UserPassword
$UserPassword
EOF
if [ "$PasswordType" = "Crypt" ]; then
cryptpasswd="`get_user_password_from_passwd $UserName`"
cmclient -u "${AH_NAME}${obj}" SET "$obj.Password" "$cryptpasswd"
fi
fi
fi
}
user_enable() {
local UserName="$1"
local UserEnable="$2"
local CLIEnable="$3"
local UserShell
[ -z "$UserName" ] && return 1
[ "$CLIEnable" = "true" ] && UserShell="$DEFAULT_SHELL" || UserShell="/bin/false"
if is_unix_user "$UserName"; then
if [ "$UserEnable" = "true" ]; then
passwd -s "$UserShell" -u $UserName > /dev/null 2>&1
else
passwd -s "$UserShell" -l $UserName > /dev/null 2>&1
fi
fi
[ "$UserEnable" = "true" ] && cmclient SETE "$obj".X_ADB_Status "Enabled" || cmclient SETE "$obj".X_ADB_Status "Disabled"
}
lecho "### $AH_NAME: Start AH <"$0" / "$#" / "$1" > ###"
do_delete() {
! is_unix_user "$newUsername" "$PASSWDFILE.orig" && is_unix_user "$oldUsername" && user_delete "$oldUsername"
cmclient DEL Device.UserInterface.X_ADB_FailLog.User.[Username="$oldUsername"]
del_gui_sessions "$newUsername"
return 0
}
do_add() {
local UserId=$((${obj##*.}+$DEFAULT_BASEID))
is_unix_user "$newUsername" && user_delete "$newUsername"
user_add "$newUsername" "$UserId" "$newX_ADB_Role" "$newPassword" "$newX_ADB_PasswordType" "$1"
user_enable "$newUsername" "$newEnable" "$newX_ADB_CLIAccessCapable"
return 0
}
do_set() {
if [ $changedPassword -eq 1 ]; then
verify_password "$newUsername" "$newPassword" || exit 7
fi
if [ $changedUsername -eq 1 ]; then
is_unix_user "$newUsername" && exit 7
! is_unix_user "$oldUsername" "$PASSWDFILE.orig" && user_delete "$oldUsername"
cmclient SET "Device.UserInterface.X_ADB_FailLog.User.[Username=$oldUsername].Username $newUsername"
fi
if is_unix_user "$newUsername" "$PASSWDFILE.orig"; then
[ "$newEnable" = "true" ] && cmclient SETE "$obj.X_ADB_Status" "Error" || cmclient SETE "$obj.X_ADB_Status" "Disabled"
return 0
fi
is_unix_user "$newUsername" || do_add sync
if [ $changedPassword -eq 1 -o $changedX_ADB_PasswordType -eq 1 ]; then
if [ $changedX_ADB_PasswordType -eq 1 -a "$oldX_ADB_PasswordType" = "Crypt" -a $changedPassword -eq 0 ]; then
exit 1
fi
if [ $newX_ADB_PasswordForm = "Crypt" ]; then
user_change_password_crypt "$newUsername" "$newPassword"
else
user_change_password "$newUsername" "$newPassword" "$newX_ADB_PasswordType"
fi
/etc/ah/CheckDefaultPassword.sh
fi
user_enable "$newUsername" "$newEnable" "$newX_ADB_CLIAccessCapable"
if [ $changedX_ADB_Role -eq 1 ]; then
local UserGroup=`user_get_groupid "$newUsername" "$newX_ADB_Role"`
user_change_group "$newUsername" "$UserGroup"
fi
if [ "$newX_ADB_LocalAccessCapable" = "true" -a "$newX_ADB_CLIAccessCapable" = "true" ]; then
add_to_unix_group "$DEFAULT_LOCAL" "$newUsername"
else
del_from_unix_group "$DEFAULT_LOCAL" "$newUsername"
fi
if [ "$newRemoteAccessCapable" = "true" -a "$newX_ADB_CLIAccessCapable" = "true" ]; then
add_to_unix_group "$DEFAULT_REMOTE" "$newUsername"
else
del_from_unix_group "$DEFAULT_REMOTE" "$newUsername"
fi
if [ "$newEnable" = "false" -o "$newX_ADB_GUIAccessCapable" = "false" ]; then
del_gui_sessions "$newUsername"
fi
return 0
}
case "$op" in
d)
do_delete
;;
s)
do_set
;;
esac
exit 0
