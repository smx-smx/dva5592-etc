#!/bin/sh
AH_NAME="Spooling"
OBJ_PRINTER_SPOOL="X_ADB_PrinterService"
CUPSSPOOL="/cups-spool"
SMBSPOOL="/smb-spool"
OK=0
service_reconf() {
	local ret="$OK"
	enable_val=$(cmclient GETV $obj.SpoolEnabled)
	if [ "$enable_val" = "true" ]; then
		spPartitionObj=$(cmclient GETV $obj.SpoolPartition)
		if [ -n "$spPartitionObj" ]; then
			for lvObj in $(cmclient GETO Device.Services.StorageService.1.LogicalVolume.*.[Status="Online"]); do
				if [ "$spPartitionObj" = "$lvObj" ]; then
					lvFs=$(cmclient GETV $lvObj.FileSystem)
					if [ ! -n "$lvFs" ]; then
						return $ERR
					fi
					lvEnable=$(cmclient GETV $lvObj.Enable)
					if [ "$lvEnable" = "false" ]; then
						cmclient SET $lvObj.Enable true
						ret=$?
					fi
					lvName=$(cmclient GETV $lvObj.Name)
					if [ "$ret" = "$OK" ] && [ -n "$lvName" ]; then
						lvBaseName=$(basename $lvName 2>/dev/null)
						lvSpoolDir=/mnt/$lvBaseName
						lvCupsSpoolDir=$lvSpoolDir$CUPSSPOOL
						lvSmbSpoolDir=$lvSpoolDir$SMBSPOOL
						if [ ! -e $lvCupsSpoolDir ]; then
							mkdir -m 777 -p $lvCupsSpoolDir
							if [ ! -e $lvCupsSpoolDir/tmp ]; then
								mkdir -m a+rwxt -p $lvCupsSpoolDir/tmp 2>/dev/null
							fi
						fi
						if [ ! -e $lvSmbSpoolDir ]; then
							mkdir -m 777 -p $lvSmbSpoolDir
						fi
					fi
					break
				fi
			done
		fi
	fi
}
service_config() {
	if [ "$changedEnable" = "1" ]; then
		service_reconf
	fi
}
case "$op" in
a)
	: # service_add
	;;
d)
	: # service_delete
	;;
g)
	: # service_add
	;;
s)
	service_config
	;;
esac
exit 0
