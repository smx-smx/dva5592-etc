#!/bin/sh
. /etc/clish/clish-commons.sh
res=""
get_user_role role
case "$1" in
"set")
	obj="$2"
	get_obj_access_for_role objAccess "$obj" 3 "$role" && [ $objAccess -lt 2 ] && die "Operation not permitted!"
	cmclient -v res SET "$obj.$3" "$4"
	;;
"add")
	get_obj_access_for_role objAccess "$2" 3 "$role" && [ $objAccess -lt 2 ] && die "Operation not permitted!"
	cmclient -v res ADD "$2"
	name=$(printf "%d\n" $res 2>/dev/null)
	if [ "$name" != "0" ]; then
		cmclient -v alias_name GETV "$2.$res.Alias"
		[ -n "$alias_name" ] && echo "INFO: $alias_name created"
	fi
	;;
"add_with_alias")
	alias_name=$3
	obj=$2
	get_obj_access_for_role objAccess "$obj" 3 "$role" && [ $objAccess -lt 2 ] && die "Operation not permitted!"
	[ -n "$alias_name" ] && alias_sufix=".[Alias=$alias_name]"
	cmclient -v res ADD "$2${alias_sufix}"
	name=$(printf "%d\n" $res 2>/dev/null)
	if [ "$name" != "0" ]; then
		cmclient -v alias_name GETV "$2.$res.Alias"
		[ -n "$alias_name" ] && echo "INFO: $alias_name created"
	fi
	;;
"list_"*)
	get_obj_access_for_role objAccess "${2%.*}" 3 "$role" && [ $objAccess -lt 2 ] && die "Operation not permitted!"
	setm="$(handle_list_actions $2 ${1#list_} $3)"
	[ -n "$setm" ] && cmclient -v res SETM "$setm"
	;;
"del")
	get_obj_access_for_role objAccess "$2" 3 "$role" && [ $objAccess -lt 3 ] && die "Operation not permitted!"
	cmclient -v res DEL "$2"
	;;
"setm")
	IFS=$(printf '\t')
	for o in $2; do
		obj=${o%.*=*}
		get_obj_access_for_role objAccess "$obj" 3 "$role" && [ $objAccess -lt 2 ] && die "Operation not permitted!"
	done
	cmclient -v res SETM "$2"
	;;
*)
	die "Unknown command: $1"
	;;
esac
cm_err_maybe_die "$res" "ERROR: failed to execute command"
