#!/bin/sh
AH_NAME="TR098_ADD_DHCPcReqOption"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098() {
	local client181obj=""
	local tr98ref=""
	local req_id=""
	client181obj="${obj%.ReqOption.*}"
	tr98ref=$(cmclient GETV "$client181obj.$PARAM_TR098")
	if [ -n "$tr98ref" ]; then
		req_id=$(help181_add_tr98obj "$tr98ref.DHCPClient.ReqDHCPOption" "$obj")
		cmclient SET "$obj.$PARAM_TR098" "$tr98ref.DHCPClient.ReqDHCPOption.$req_id" >/dev/null
	fi
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
