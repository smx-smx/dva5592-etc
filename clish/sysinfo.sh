#!/bin/sh
case "$1" in
uptime)
	IFS="." read sec _ </proc/uptime
	printf "Uptime: %d day(s), %d hour(s), %d minute(s), %d second(s)\n" \
		$((sec / 86400)) \
		$(($((sec % 86400)) / 3600)) \
		$(($((sec % 3600)) / 60)) \
		$(($((sec % 3600)) % 60))
	;;
cpu)
	top -b -n 1 | grep "^CPU"
	;;
esac
