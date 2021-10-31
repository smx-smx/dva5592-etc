# Get appropriate byte from the X_ADB_Permissions for the object specified in
get_obj_access_for_role() {
	local perms_ offset_ obj_ default_ userRole_
	obj_=$2
	default_=$3
	userRole_=$4
	cmclient -v perms_ GETV "${obj_}.X_ADB_Permissions"
	case "$userRole_" in
	"SuperUser")
		eval "$1=3"
		return
		;;
	"AdminUser")
		offset_=1
		;;
	"PowerUser")
		offset_=3
		;;
	"NormalUser")
		offset_=2
		;;
	*)
		offset_=2
		;;
	esac
	eval "$1=$(expr substr "${perms_}${default_}${default_}${default_}" $offset_ 1)"
}
get_user_role() {
	local role_
	if [ -n "$USER_ROLE" ]; then
		eval "$1='$USER_ROLE'"
	else
		cmclient -v role_ GETV "Device.Users.User.*.[Username=$USER].X_ADB_Role"
		eval "$1='$role_'"
	fi
}
get_obj_access() {
	local obj_=$2
	local default_=${3:-0}
	local userRole_
	get_user_role userRole_
	get_obj_access_for_role "$1" "$obj_" "$default_" "$userRole_"
}
perm_str_to_num() {
	local res_=""
	case "$2" in
	"Hidden")
		res_=0
		;;
	"Read")
		res_=1
		;;
	"ReadWrite")
		res_=2
		;;
	"ReadWriteDelete")
		res_=3
		;;
	*)
		die "Error: unknown permission: $1"
		;;
	esac
	eval "$1='$res_'"
}
cmclient_GETO_Access() {
	local userRole_ objs_ obj_ perm_ sep_ reqPerm_ ret_
	reqPerm_=$3
	userRole_="$4"
	ret_=""
	[ -z "$userRole_" ] && get_user_role userRole_
	for arg in $2; do
		cmclient -v objs_ GETO "$arg"
		for obj_ in $objs_; do
			get_obj_access_for_role perm_ "$obj_" 3 "$userRole_"
			[ $perm_ -ge $reqPerm_ ] && ret_=${ret_:+$ret_	}${obj_}
		done
	done
	eval "$1='$ret_'"
}
