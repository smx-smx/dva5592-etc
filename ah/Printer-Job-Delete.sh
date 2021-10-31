#!/bin/sh
AH_NAME="Printer-Job-Delete"
service_reconf() {
	if [ "$newEnable" = "true" ]; then
		cmclient -v prnJobProtocol GETV $obj.Protocol
		if [ "$prnJobProtocol" = "SMB" ]; then
			cmclient -v spoolStatus GETV Device.Services.X_ADB_PrinterService.SpoolEnabled
			cmclient -v lvObj GETV Device.Services.X_ADB_PrinterService.SpoolPartition
			if [ "$spoolStatus" = "true" ] && [ -n "$lvObj" ]; then
				cmclient -v lvName GETV $lvObj.Name
				lvBaseName=$(basename $lvName)
				cmclient -v prnJobId GETV $obj.JobId
				smbJobFileName=$(printf "smbprn.%.8d.*" $prnJobId)
				smbJobFileName=/mnt/$lvBaseName/$smbJobFileName
				[ -e $smbJobFileName ] && rm $smbJobFileName
			fi
			/etc/ah/Printer-Job-Delete-CM.sh "$obj" &
		elif [ "$prnJobProtocol" = "CUPS" ]; then
			cmclient -v prnJobId GETV $obj.JobId
			cancel $prnJobId
			/etc/ah/Printer-Job-Delete-CM.sh "$obj" &
		fi
	fi
}
service_config() {
	service_reconf
}
case "$op" in
s)
	service_config
	;;
esac
exit 0
