#!/bin/sh
case "$op" in
s)
[ "$changedEnable" = 1 ] && (sleep 10 && reboot) &
;;
esac
exit 0
