#!/bin/sh
AH_NAME="TR098_ADD_IPIfIPv4"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098() {
	local ip181obj=""
	local tr98ref=""
	local ipId=""
	ip181obj="${obj%.IPv4Address.*}"
	tr98ref=$(cmclient GETV "$ip181obj.$PARAM_TR098")
	case "$tr98ref" in
	*"LANHostConfigManagement"*)
		ipId=$(help181_add_tr98obj "$tr98ref.IPInterface" "$obj")
		cmclient SET "$obj.$PARAM_TR098" "$tr98ref.IPInterface.$ipId" >/dev/null
		;;
	*)
		if [ $newAddressingType = "DHCP"]; then
			cmclient SET "${ip181obj}.IPv4Address.[${PARAM_TR098}=${tr98ref}].${PARAM_TR098}" ""
			cmclient SET "$obj.$PARAM_TR098" "$tr98ref" >/dev/null
		else
			cmclient -v objectsWithReference GETO "${ip181obj}.IPv4Address.[${PARAM_TR098}=${tr98ref}]"
			if [ ${#objectsWithReference} = 0 ]; then
				cmclient SET "$obj.$PARAM_TR098" "$tr98ref" >/dev/null
			fi
		fi
		;;
	esac
}
service_delete_tr098() {
	local tr98ref=""
	tr98ref="$newX_ADB_TR098Reference"
	case "$tr98ref" in
	*"LANHostConfigManagement"*)
		help181_del_tr98obj "$tr98ref"
		;;
	*)
		ip181obj="${obj%.IPv4Address.*}"
		tr98refPHY=$(cmclient GETV "$ip181obj.$PARAM_TR098")
		if [ $oldX_ADB_TR098Reference = $tr98refPHY ]; then
			cmclient -v othersAddresses GETO "${ip181obj}.IPv4Address"
			if [ ${#IPv4objects} != 0 ]; then
				set -- $IPv4objects
				if [ $1 != $obj ]; then
					cmclient SET "$1.X_ADB_TR098Reference" "$tr98refPHY" >/dev/null
				else
					cmclient SET "$2.X_ADB_TR098Reference" "$tr98refPHY" >/dev/null
				fi
			fi
		fi
		;;
	esac
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
