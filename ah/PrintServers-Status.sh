#!/bin/sh
AH_NAME="PrintServers"
CUPS_CONF_FILE=/tmp/cupsd/cupsd.conf
ipp_status() {
	cmclient -v psrvEnable GETV Device.Services.X_ADB_PrinterService.Enable
	cmclient -v ippEnable GETV Device.Services.X_ADB_PrinterService.Servers.IPP.Enable
	if [ "$psrvEnable" = "true" ] && [ "$ippEnable" = "true" ]; then
		echo "Enabled"
	else
		echo "Disabled"
	fi
}
smb_status() {
	cmclient -v psrvEnable GETV Device.Services.X_ADB_PrinterService.Enable
	cmclient -v smbEnable GETV Device.Services.X_ADB_PrinterService.Servers.SMB.Enable
	cmclient -v smbService GETV Device.Services.StorageService.1.NetworkServer.SMBEnable
	if [ "$psrvEnable" = "true" ] && [ "$smbEnable" = "true" ] && [ "$smbService" = "true" ]; then
		echo "Enabled"
	else
		echo "Disabled"
	fi
}
service_get() {
	param_name="${1##*.}"
	obj_path="${1%%.$param_name*}"
	if [ "$obj_path" = "Device.Services.X_ADB_PrinterService.Servers.IPP" ]; then
		[ "$param_name" = "Status" ] && ipp_status
	elif [ "$obj_path" = "Device.Services.X_ADB_PrinterService.Servers.SMB" ]; then
		[ "$param_name" = "Status" ] && smb_status
	fi
}
case "$op" in
g)
	for arg; do # Arg list as separate words
		service_get "$obj.$arg"
	done
	;;
esac
exit 0
