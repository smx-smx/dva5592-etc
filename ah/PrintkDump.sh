#!/bin/sh
AH_NAME="PrintkDump"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
create_timer() {
	local i eventObj
	cmclient -v i ADDS "Device.X_ADB_Time.Event.[Alias=PrintkDumpTimer].[Type=Periodic].[DeadLine=30]"
	eventObj="Device.X_ADB_Time.Event.$i"
	cmclient ADDS "$eventObj.Action.[Operation=Set].[Path=${obj}.Enable].[Value=true]"
	cmclient SET $eventObj.Enable true
}
stop_service() {
	cmclient DEL "Device.X_ADB_Time.Event.[Alias=PrintkDumpTimer]"
	exit 0
}
service_config() {
	local ret
	cmclient -v ret GETO Device.X_ADB_SystemLog.Service.[Identity=printkd]
	[ "$obj" != "$ret" ] && exit 0
	[ "$newEnable" = "false" -a $changedEnable -eq 1 ] && stop_service
	[ ! -c /dev/printk_dump_dev ] && stop_service
	create_timer
	while read -r ret; do
		logger -t "printkd" -p 3 "$ret"
	done </dev/printk_dump_dev
}
case "$op" in
s)
	service_config
	;;
esac
exit 0
