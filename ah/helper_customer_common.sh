#!/bin/sh
help_custom_print_upgrade_log() {
	tail -f /tmp/upgrade.log | grep -i -e reboot -e Signature -e "Writing boot"
}
help_custom_settings() {
	eval $1='-b'
}
