#!/bin/sh
. /etc/clish/clish-commons.sh
. /etc/ah/helper_ifname.sh
ifname="$1"
command="$2"
setm=""
ppp_obj=$(cli_or_tr_alias_to_tr_obj "$ifname")
[ -z "$ppp_obj" ] && die "Interface ${ifname} does not exist"
case "$command" in
"authentication_show")
	setm="$(handle_list_actions $ppp_obj.AuthenticationProtocol show)"
	echo
	if [ -z "$setm" ]; then
		echo "Authentication protocol list is empty"
	else
		printf "Authentication protocol list:\n$setm\n"
	fi
	echo
	setm=""
	;;
"show")
	. /etc/clish/interface-show.sh ppp "${ifname}"
	;;
*)
	echo "Unknown command $command"
	;;
esac
[ -n "$setm" ] && cm_err_maybe_die "$(cmclient SETM \"$setm\")" "ERROR: Failed to execute $command"
