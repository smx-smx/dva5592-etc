#!/bin/sh
busnum="${obj#Device.USB.USBHosts.Host.}"
busnum="${busnum%%.*}"
cmclient -v devnum GETV "$obj.DeviceNumber"
for p in /sys/bus/usb/devices/usb$busnum /sys/bus/usb/devices/$busnum-*; do
[ -e $p/devnum ] && read x < $p/devnum && [ $x -eq $devnum ] && usbpath=$p && break
done
for arg in $@; do
case $arg in
X_ADB_Urbnum)	attr=urbnum ;;
X_ADB_Urbres)	attr=urbres ;;
*) attr= ;;
esac
cat "$usbpath/$attr" 2>/dev/null || echo
done
true
