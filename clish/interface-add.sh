#!/bin/sh
. /etc/clish/clish-commons.sh
TYPE="$1"
setm=""
new_iface_obj=""
case "$TYPE" in
ppp)
	parent="$2"
	alias_name="$3"
	ppp_interface_add "$parent" "$alias_name" >/dev/null 2>&1
	;;
ptm)
	parent="$2"
	dslChannel=$(. /etc/clish/clish-commons.sh && upper_interfaces_get "$parent" Device.DSL.Channel)
	[ -n "$dslChannel" ] && cmclient -v id ADD "Device.PTM.Link"
	cm_err_maybe_die "$id" "ERROR: cannot create new interface!"
	setm="Device.PTM.Link.${id}.LowerLayers=$dslChannel"
	new_iface_obj="Device.PTM.Link.$id"
	;;
atm)
	alias_name="$3"
	alias_sufix=
	if [ -n "$alias_name" ]; then
		cmclient -v id ADD "Device.ATM.Link.[LinkType=${2}].[LowerLayers=Device.DSL.Channel.1].[Alias=$alias_name]"
		cm_err_maybe_die "$id" "ERROR: cannot create new interface!"
	else
		cmclient -v id ADD "Device.ATM.Link"
		setm="Device.ATM.Link.${id}.LinkType=${2}"
		setm="$setm	Device.ATM.Link.${id}.LowerLayers=Device.DSL.Channel.1"
	fi
	new_iface_obj="Device.ATM.Link.$id"
	;;
*)
	die "Unknown interface type: $TYPE"
	;;
esac
[ -n "$setm" ] && cmclient SETM "$setm" >/dev/null 2>&1
if [ -n "$new_iface_obj" ]; then
	cmclient -v alias GETV "${new_iface_obj}.Alias" && echo "INFO: interface $alias was created successfuly"
fi
