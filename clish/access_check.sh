#!/bin/sh
usr=${1:-AdminUser}
cmclient -v role GETV "Device.Users.User.*.[Username=$USER].X_ADB_Role"
IFS=","
for usr in $usr; do
	[ "$usr" = "$role" ] && exit 0
done
unset IFS
exit 1
