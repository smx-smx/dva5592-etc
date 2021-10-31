#!/bin/sh

. /etc/ipsec/helper_ph1.sh

l2tp_config() {
	local ev_msg="$1" spd_action

	case "$ev_msg" in
		"phase1_up")	spd_action="spdadd"	;;
		"phase1_down")	spd_action="spddelete"	;;
		*) return ;;
	esac

	helper_l2tp_policy "$LOCAL_ADDR" "$REMOTE_ADDR" "$spd_action"
}

pure_config() {
	# We currently support RW ipsec with assigned remote addresses only
	[ -z "$INTERNAL_ADDR4" ] && return

	local ev_msg="$1" gsp
	### gen policy?
	cmclient -v gsp GETV ${filter_obj}.X_ADB_SPGeneration
	[ "$gsp" = "Script" ] && helper_dynamicsp "$ev_msg" "$LOCAL_ADDR" "$REMOTE_ADDR" "$INTERNAL_ADDR4" "$filter_obj"

	helper_restricted_subnet "$ev_msg" "$REMOTE_ID"

	### Client triggers creation of SP
}

xauth_config() {
	local ev_msg="$1"
	pure_config "$ev_msg"

	### XAuth per user access rules here
}
