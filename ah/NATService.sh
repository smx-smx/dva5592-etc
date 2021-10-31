#!/bin/sh
AH_NAME="NATService"
[ "$user" = "tr098" ] && exit 0
[ "$user" = "yacs" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
case "$op" in
s)
	if [ "$oldOrigin" = "User" -a "$newOrigin" = "User" ]; then
		:
	fi
	;;
d)
	if [ "$oldOrigin" = "User" ]; then
		:
	fi
	;;
esac
exit 0
