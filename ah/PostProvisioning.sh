#!/bin/sh
AH_NAME="POSTPROVISIONING"
cwmp_state_exec() {
	. /etc/ah/helper_serialize.sh && help_serialize "$AH_NAME" 180
	local ppobj="" gobj="" glist="" pplist="" setm="" group_found="" path="" value="" prio="" cwmp_progress=""
	for prio in High Default Low; do
		cmclient -v pplist GETO "$obj.PostProvisioning.[Parameter!].[Priority=$prio]"
		[ -z "$pplist" ] && continue
		group_found='false'
		setm=''
		cmclient -v glist GETO "$obj.PostProvisioning.[Parameter!].[Priority=$prio].[Group=true]"
		for gobj in $glist; do
			cmclient -v path GETV "$gobj.Parameter"
			cmclient -v value GETV "$gobj.Value"
			setm="${setm:+$setm	}$path=$value"
		done
		for ppobj in $pplist; do
			cmclient -v cwmp_progress GETV Device.ManagementServer.X_ADB_CWMPState.SessionInProgress
			[ "$cwmp_progress" = "true" ] && break 2
			for gobj in $glist; do
				[ "$ppobj" != "$gobj" ] && continue
				[ "$group_found" = "true" ] && continue 2
				group_found="true"
				cmclient DEL "$obj.PostProvisioning.[Parameter!].[Priority=$prio].[Group=true]"
				cmclient -u "$AH_NAME" SETM "$setm"
				logger -t cwmp -p 5 "Provisioning done: $setm"
				continue 2
			done
			cmclient -v path GETV "$ppobj.Parameter"
			cmclient -v value GETV "$ppobj.Value"
			cmclient DEL "$ppobj"
			cmclient -u "$AH_NAME" SET "$path" "$value"
			logger -t cwmp -p 5 "Provisioning done: $path=$value"
		done
	done
}
case "$op" in
s)
	[ "$changedSessionInProgress" = 1 -a "$newSessionInProgress" = "false" ] && cwmp_state_exec &
	;;
esac
exit 0
