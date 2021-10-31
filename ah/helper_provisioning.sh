#!/bin/sh
help_post_provisioning_add() {
	local path="$1" value="$2" prio="$3" group="$4" cwmp_progress="" obj=""
	[ -z "$path" ] && return 0
	[ -z "$prio" ] && prio="Default"
	[ -z "$group" ] && group="false"
	cmclient -v cwmp_progress GETV Device.ManagementServer.X_ADB_CWMPState.SessionInProgress
	[ "$cwmp_progress" != "true" ] && return 0
	cmclient -v obj GETO "Device.ManagementServer.X_ADB_CWMPState.PostProvisioning.[Parameter=$path]"
	if [ -z "$obj" ]; then
		cmclient -v obj ADDS "Device.ManagementServer.X_ADB_CWMPState.PostProvisioning"
		obj="Device.ManagementServer.X_ADB_CWMPState.PostProvisioning.$obj"
		logger -t cwmp -p 5 "Provisioning scheduled: $path=$value ($prio priority)"
	fi
	cmclient SETM "$obj.Parameter=$path	$obj.Value=$value	$obj.Priority=$prio	$obj.Group=$group"
	return 1
}
help_post_provisioning_remove() {
	local path="$1" value="$2" elem="" cwmp_progress=""
	cmclient -v cwmp_progress GETV Device.ManagementServer.X_ADB_CWMPState.SessionInProgress
	if [ "$cwmp_progress" = "true" ]; then
		cmclient -v elem GETO "Device.ManagementServer.X_ADB_CWMPState.PostProvisioning.[Parameter=$path].[Value=$value]"
		if [ ${#elem} -gt 0 ]; then
			cmclient DEL "$elem"
			logger -t cwmp -p 5 "Provisioning removed: $path=$value"
			return 1
		else
			return 0
		fi
	fi
	return 0
}
