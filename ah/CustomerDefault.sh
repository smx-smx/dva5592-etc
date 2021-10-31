#!/bin/sh
cmclient -v factory_mode GETV Device.X_ADB_FactoryData.FactoryMode
if [ "$factory_mode" = "true" ]; then
status="Error: unavailable in factory mode"
else
status="Successful"
cconf="/tmp/cfg/customer_conf"
case "$newX_ADB_CustomerDefault" in
"None")
rm -frt /tmp/cfg $cconf
cmclient RESET
;;
"Save")
[ -e $cconf ] || mkdir $cconf
rm -t /tmp/cfg $cconf/*.xml
cmclient PATHSAVE $cconf/default.xml Device. mangle
if [ -d "/tmp/cfg/CWMP" ]; then
rm -frt /tmp/cfg $cconf/CWMP
cp -a -f /tmp/cfg/CWMP $cconf/ > /dev/console
echo "saving CWMP certificate" > /dev/console
fi
if [ -d "/tmp/cfg/CWMP2" -a -x /etc/ah/CWMP2.sh ]; then
rm -frt /tmp/cfg $cconf/CWMP2
cp -a -f /tmp/cfg/CWMP2 $cconf/ > /dev/console
echo "saving CWMP2 certificate" > /dev/console
fi
;;
"Restore")
cmclient RESET
;;
esac
fi
cmclient SET Device.DeviceInfo.X_ADB_CustomerDefaultStatus "$status"
exit 0
