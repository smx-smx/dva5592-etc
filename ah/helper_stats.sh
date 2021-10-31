#!/bin/sh
. /etc/ah/helper_ifname.sh
help_reset_stats() {
	local statsObject ifname param_paths single_param_path currentVal
	statsObject=$1
	help_lowlayer_ifname_get ifname "${statsObject%%.Stats}"
	if [ -n "$ifname" -a -d /sys/class/net/"$ifname" ]; then
		cmclient -v param_paths GETN ${statsObject}. 0
		for single_param_path in $param_paths; do
			if [ "${single_param_path%X_ADB_Reset}" = "$single_param_path" ]; then
				help_get_base_stats_core $single_param_path $ifname currentVal
				[ -n "$currentVal" ] && cmclient SETE $single_param_path $currentVal
			fi
		done
	fi
}
