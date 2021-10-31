#!/bin/sh
printer_job_delete() {
	local obj="$1" cancelVal
	if [ -n "$obj" ]; then
		cmclient -v cancelVal GETV $obj.Cancel
		[ "$cancelVal" = "true" ] && cmclient DEL $obj
	fi
}
