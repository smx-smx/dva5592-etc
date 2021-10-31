#!/bin/sh
AH_NAME="TR098_LogicalVolume"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_get() {
	local obj98="$1"
	local param98="$2"
	local value98=""
	case "$param98" in
	"PhysicalReference")
		tr181obj=$(cmclient GETV "${obj#"InternetGateway"*}.$param98")
		value98="InternetGateway$tr181obj"
		;;
	*) ;;

	esac
	echo "$value98"
}
service_set_param() {
	local obj98="$1"
	local param98="$2"
	local _val="$3"
	case "$param98" in
	"PhysicalReference")
		[ -z "$setm_params" ] &&
			setm_params="${obj98#"InternetGateway"*}.$param98=${_val#"InternetGateway"*}" ||
			setm_params="$setm_params	${obj98#"InternetGateway"*}.$param98=${_val#"InternetGateway"*}"
		;;
	*) ;;

	esac
}
service_config() {
	setm_params=""
	for i in PhysicalReference; do
		if eval [ \${set${i}:=0} -eq 1 ]; then
			eval service_set_param "$obj" "$i" \"\$new${i}\"
		fi
	done
	if [ -n "$setm_params" ]; then
		cmclient -u "tr098" SETM "$setm_params" >/dev/null
	fi
}
case "$op" in
"g")
	for arg; do # Arg list as separate words
		service_get "$obj" "$arg"
	done
	;;
"s")
	service_config
	;;
esac
exit 0
