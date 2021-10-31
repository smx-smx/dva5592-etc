#!/bin/sh
. /etc/clish/clish-permissions.sh
is_obj_visible() {
	local objAccess
	get_obj_access objAccess "$1"
	[ $objAccess -lt 1 ] && exit 1 || exit 0
}
is_subobj_visible() {
	local obj
	cmclient -v obj GETV "$1"
	[ -n "$obj" ] && is_obj_visible "$obj" || exit 0
}
is_page_visible() {
	local role perm
	get_user_role role
	[ -z "$role" ] && exit 0
	cmclient -v perm GETV "Device.UserInterface.X_ADB_AccessControl.Feature.*.[PagePath=$1].Permissions"
	[ -z "$perm" ] && exit 0
	case "$role" in
	"NormalUser")
		perm=${perm#?}
		perm=${perm%??}
		;;
	"PowerUser")
		perm=${perm#??}
		perm=${perm%?}
		;;
	*)
		perm=${perm%???}
		;;
	esac
	[ "2" = "$perm" ] && exit 0 || exit 1
}
case "$1" in
"is_subobj_visible")
	is_subobj_visible "$2"
	;;
"is_obj_visible")
	is_obj_visible "$2"
	;;
"is_page_visible")
	is_page_visible "$2"
	;;
*)
	exit 1
	;;
esac
