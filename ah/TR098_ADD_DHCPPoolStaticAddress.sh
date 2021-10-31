#!/bin/sh
AH_NAME="TR098_ADD_DHCPPoolStaticAddress"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098() {
	local pool181obj=""
	local tr98ref=""
	local addr_id=""
	pool181obj="${obj%.StaticAddress.*}"
	tr98ref=$(cmclient GETV "$pool181obj.$PARAM_TR098")
	addr_id=$(help181_add_tr98obj "$tr98ref.DHCPStaticAddress" "$obj")
	cmclient -u "DHCPv4Server" SET "$obj.$PARAM_TR098" "$tr98ref.DHCPStaticAddress.$addr_id" >/dev/null
}
service_delete_tr098() {
	local tr98ref=""
	tr98ref="$newX_ADB_TR098Reference"
	if [ -n "$tr98ref" ]; then
		help181_del_tr98obj "$tr98ref"
	fi
}
case "$op" in
"a")
	service_align_tr098
	;;
"d")
	service_delete_tr098
	;;
esac
exit 0
