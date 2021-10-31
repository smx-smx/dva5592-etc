#!/bin/sh
AH_NAME="bootAlignment"
align_PhysicalMedium_status()
{
local plug_o=""
local sn=""
local query=""
for plug_o in /sys/bus/usb/devices/*-*; do
[ -e $plug_o/serial ] && read sn < $plug_o/serial && \
case "$sn" in
:* | *: | *:* )
;;
* )
[ -z "$query" ] && query="[SerialNumber!$sn]" || query="$query.[SerialNumber!$sn]"
;;
esac
done
cmclient SET "Device.Services.StorageService.PhysicalMedium.$query.Status" "Offline" > /dev/null
}
align_PhysicalMedium_status
exit 0
