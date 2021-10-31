#!/bin/sh
#nl:add,module,adsldd
. /etc/ah/target.sh
(
	if [ -s /tmp/cfg/cache/xdslctl ]; then
		rm -f /tmp/cfg/cache/xdslctl
		exit 0
		while ! xdsl_get_state; do
			sleep 1
		done
		cp /etc/eh/delay/eh_dslup.sh /tmp/
		mv /tmp/eh_dslup.sh /tmp/eh/
		xtm_start_interface "allint"
		xtm_interface_state "0x01" "enable"
		/bin/sh /tmp/cfg/cache/xdslctl
	fi
) &
