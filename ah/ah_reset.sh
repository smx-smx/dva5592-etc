#!/bin/sh
AH_NAME="ah_reset"
CFG_DIRS="/tmp/cfg/main /tmp/cfg/notify /tmp/cfg/recovery /tmp/cfg/cache /tmp/cfg/FactoryData.xml /tmp/cfg/main_override /tmp/cfg/httpd /tmp/cfg/current_version /tmp/cfg/conf_upgrade.sh"
rmdirs_check() {
local cfg_dirs="$1"
for d in $cfg_dirs; do
[ -d "$d" ] && return 1
done
return 0
}
cmclient SET Device.DeviceInfo.X_ADB_ResetInProgress true
_count=0 _ret=1 _mtd=""
ls -l /tmp/cfg > /tmp/yaffs_running &
sleep 1
while [ ! -e /tmp/yaffs_running -a $_count -lt 10 ]; do
sleep 1
_count=$((_count+1))
done
[ $_count -lt 10 ] && _ret=$(wc -c /tmp/yaffs_running | cut -d ' ' -f1)
if [ $_count -ge 10 -o $_ret -eq 0 ]; then
_mtd=$(cat /proc/mtd | grep conf_fs | cut -f1 -d ':')
if [ ${#_mtd} -gt 0 ]; then
if [ -e "/usr/sbin/flash_eraseall" ]; then
/usr/sbin/flash_eraseall -j -p 0 -l 8 /dev/$_mtd >> /dev/console
else
mtd erase /dev/$_mtd >> /dev/console
fi
fi
reboot
exit 0
fi
cmclient -v factory_mode GETV "Device.X_ADB_FactoryData.FactoryMode"
if [ "$factory_mode" = "true" ]; then
if [ -x /sbin/yaff ]; then
cmclient SET Device.X_ADB_FactoryData.FactoryMode false
cmclient DUMPDM FactoryData /tmp/deviceinfo.xml
gzip -c /tmp/deviceinfo.xml > /tmp/conf_factory.temp
cat /tmp/conf_factory.temp | yaff w conf_factory
rm /tmp/conf_factory.temp
rm /tmp/deviceinfo.xml
else
if [ -e /tmp/cfg/FactoryData.xml -a ! -e /tmp/factory/deviceinfo.xml ]; then
cp /tmp/cfg/FactoryData.xml /tmp/factory/deviceinfo.xml
else
cmclient SET Device.X_ADB_FactoryData.FactoryMode false
cmclient DUMPDM FactoryData /tmp/factory/deviceinfo.xml
fi
fi
fi
if [ "$1" != "NO_BOOTSTRAP" ]; then
EXTRA_DIR="/tmp/cfg/CWMP"
[ -x /etc/ah/CWMP2.sh ] && EXTRA_DIR="$EXTRA_DIR /tmp/cfg/CWMP2"
fi
logger -t "SYSTEM" -p 4 "ARS 4 - User-initiated reset to factory default"
echo "cmclient_reset_occured" > /tmp/cfg/reboot_reason
cmclient STOP
[ "$factory_mode" != "true" ] && sleep 5 || sleep 2
CFG_DIRS="$CFG_DIRS $EXTRA_DIR"
rm -rft /tmp/cfg $CFG_DIRS
if rmdirs_check "$CFG_DIRS"; then
logger -t "SYSTEM" -p 4 "ARS 4 - Reset to factory default ok"
echo "$AH_NAME: Reset to factory default ok" > /dev/console
return
fi
logger -t "SYSTEM" -p 4 "ARS 4 - Running configuration does not correcly removed. Trying again"
echo "$AH_NAME: Running configuration does not correcly removed. Trying again" > /dev/console
rm -rft /tmp/cfg $CFG_DIRS
if rmdirs_check "$CFG_DIRS"; then
logger -t "SYSTEM" -p 4 "ARS 4 - Reset to factory default ok"
echo "$AH_NAME: Reset to factory default ok" > /dev/console
return
fi
logger -t "SYSTEM" -p 4 "ARS 4 - Reset to factory default failed."
echo "$AH_NAME: Reset to factory default failed" > /dev/console
if [ "$factory_mode" = "true" ]; then
cmclient START
cmclient SET Device.X_ADB_FactoryData.FactoryMode true
cmclient SAVE
cmclient DUMPDM FactoryData /tmp/factory/deviceinfo.xml
nvramUpdate Feature 0x2 > /dev/null
fi
