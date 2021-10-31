#!/bin/sh
AH_NAME="TR098_ADD_DHCPc"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098() {
	local ipref_new=""
	local ipref_old=""
	local tr98ref=""
	ipref_new="$newInterface"
	ipref_old="$oldInterface"
	if [ "$ipref_new" = "$ipref_old" ]; then
		return
	fi
	tr98ref=$(cmclient GETV "$ipref_new.$PARAM_TR098")
	case "$tr98ref" in
	*"WANConnectionDevice"*)
		cmclient SET "$obj.$PARAM_TR098" "$tr98ref" >/dev/null
		;;
	*) ;;

	esac
}
case "$op" in
"s")
	service_align_tr098
	;;
esac
exit 0
