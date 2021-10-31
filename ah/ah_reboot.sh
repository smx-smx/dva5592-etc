#!/bin/sh
logger -t "reboot" -p 7 "Reboot"
echo "cmclient_reboot_occured" > /tmp/cfg/reboot_reason
cmclient STOP
reboot
exit 0
