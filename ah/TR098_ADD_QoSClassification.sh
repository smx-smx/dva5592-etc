#!/bin/sh
AH_NAME="TR098_ADD_QoSClassification"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098() {
	local qos181obj= tr98ref= app_id= tbd=
	qos181obj="${obj%.Classification.*}"
	cmclient -v tr98ref GETV "$qos181obj.$PARAM_TR098"
	cmclient -v tbd GETO "$tr98ref.Classification.[X_ADB_TR181Name=$obj]"
	[ ${#tbd} -ne 0 ] && cmclient DELE "$tbd"
	app_id=$(help181_add_tr98obj "$tr98ref.Classification" "$obj")
	cmclient SET "$obj.$PARAM_TR098" "$tr98ref.Classification.$app_id" >/dev/null
}
service_delete_tr098() {
	local tr98ref=""
	local to_delete=""
	local queue181=""
	tr98ref="$newX_ADB_TR098Reference"
	if [ -n "$tr98ref" ]; then
		to_delete=1
		for queue181 in $(cmclient GETO "Device.QoS.Classification.*.[$PARAM_TR098=$tr98ref]"); do
			if [ "$queue181" != "$obj" ]; then
				to_delete=0
				break
			fi
		done
		if [ "$to_delete" -eq 1 ]; then
			help181_del_tr98obj "$tr98ref"
		fi
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
