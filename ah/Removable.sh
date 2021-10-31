#!/bin/sh
AH_NAME="Removable"
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
removable_set() {
	local i
	cmclient -v usagecount GETV "$obj".X_ADB_UsageCount
	if [ "$newRemovable" = "true" ]; then
		if [ "$usagecount" -gt "0" ]; then
			i=$(($usagecount - 1))
			cmclient SET "$obj.X_ADB_UsageCount" "$i"
		fi
	elif [ "$newRemovable" = "false" ]; then
		i=$(($usagecount + 1))
		cmclient SET "$obj.X_ADB_UsageCount" "$i"
	fi
	return 1
}
removable_get() {
	cmclient -v usagecount GETV "$obj".X_ADB_UsageCount
	[ "$usagecount" -gt "0" ] && echo "false" || echo "true"
	return 1
}
case "$op" in
"s")
	removable_set
	;;
"g")
	removable_get
	;;
esac
exit 0
