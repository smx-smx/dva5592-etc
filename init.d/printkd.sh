#!/bin/sh /etc/rc.common

exec 1>/dev/null
exec 2>/dev/null

START=94

start() {
	printf '[\033[1;34m*\033[m] \033[36m%s\033[m\n' "Starting Printk Dump" >/dev/console
	while read -r major; do
		case "$major" in
		*printk_dump_dev) break ;;
		esac
	done </proc/devices

	set -- $major
	major=$1
	mknod /dev/printk_dump_dev c $major 0

	cmclient SET Device.X_ADB_SystemLog.Service.[Identity=printkd].Enable true
	echo "[Printk Dump ready]" >/dev/console
}
