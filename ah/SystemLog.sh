#!/bin/sh
[ "$user" = "logd" ] && exit 0
. /etc/ah/helper_functions.sh
service_get()
{
local obj="$1" param="$2" enabled st
case "$obj" in
Device.X_ADB_SystemLog.FileLogging.* )
objid=${obj##*.}
if [ "$param" = "Status" ]; then
st=$(logc "g l ${objid}")
case "$st" in
*": 1 "* ) echo "Enabled" ;;
*": 2 "* ) echo "Done" ;;
*": 3 "* ) echo "Error" ;;
*": 4 "* ) echo "Overflow" ;;
* ) echo "Disabled" ;;
esac
fi
;;
esac
}
ext_service_config() {
case "$newIdentity" in
dns)
mkdir -p /tmp/dns
[ "$newEnable" = "false" ] && rm -f /tmp/dns/loglevel || echo "$newPriority" > /tmp/dns/loglevel
;;
cm)
mkdir -p /tmp/debug/cm
[ "$newEnable" = "false" ] && echo "0" > /tmp/debug/cm/loglevel || echo "$newPriority" > /tmp/debug/cm/loglevel
killall -SIGUSR2 cm
;;
esac
}
service_config()
{
case "$obj" in
Device.X_ADB_SystemLog )
if [ "$user" = "boot" ] || [ "$changedEnable" = "1" ]; then
if [ "$newEnable" = "false" ]; then
logc "s e 0"
cmclient SET Device.X_ADB_SystemLog.Service.Status Disabled
cmclient SETE "${obj}.Status" Disabled
else
logc "s e 1"
cmclient SET Device.X_ADB_SystemLog.Service.Status Enabled
cmclient SETE "${obj}.Status" Enabled
fi
fi
[ "$user" = "boot" -o "$changedNumberOfEntries" = "1" ] && logc "s s ${newNumberOfEntries}"
[ "$user" = "boot" ] && cmclient -u boot SET Device.X_ADB_SystemLog.Server.[Enable=true].Enable true
[ "$user" = "boot" ] && cmclient -u boot SET Device.X_ADB_SystemLog.FileLogging.[Enable=true].Enable true
;;
Device.X_ADB_SystemLog.Service.* )
if [ "$newEnable" = "false" ]; then
logc "s t ${newIdentity}*"
cmclient SETE "${obj}.Status" Disabled
else
case "${newRateLimitUnit}" in
"Seconds" ) newRateLimitUnit=0 ;;
"Minutes" ) newRateLimitUnit=60 ;;
"Hours" ) newRateLimitUnit=3600 ;;
"Days" ) newRateLimitUnit=3600 ;;
esac
logc "s t ${newIdentity}* ${newPriority} ${newRateLimit} ${newRateLimitUnit} 1 1 ${newFacility}"
cmclient SETE "${obj}.Status" Enabled
fi
ext_service_config
;;
Device.X_ADB_SystemLog.Server.* )
objid=${obj##*.}
if [ "$newEnable" = "false" ]; then
logc "s r ${objid}"
else
cmclient -v _sn GETV Device.DeviceInfo.SerialNumber
cmclient -v _sv GETV Device.DeviceInfo.SoftwareVersion
hn="SN-"$_sn"_FW-"$_sv
if [ "$user" = "boot" -o \
"$changedEnable" = "1" -o \
"$changedRemoteServer" = "1" -o \
"$changedRemotePort" = "1" -o \
"$changedBufferSize" = "1" -o \
"$changedBufferedEntriesLimit" = "1" -o \
"$changedServiceLabel" = "1" -o \
"$changedIdentityFilter" = "1" -o \
"$changedSeverityFilter" = "1" -o \
"$changedUseTLS" = "1" -o \
"$changedUseRFC5424Format" = "1" ]; then
[ "$newUseTLS" = "true" ] && newUseTLS="/etc/certs/syslog_ca.pem" || newUseTLS=0
[ "$newUseRFC5424Format" = "true" ] && newUseRFC5424Format=1 || newUseRFC5424Format=0
[ "$newServiceLabel" = "" ] && newServiceLabel="*"
[ -n "$newRemoteServer" ] && \
logc "s r ${objid} ${hn} ${newRemoteServer} ${newRemotePort} $newBufferedEntriesLimit ${newUseRFC5424Format} ${newBufferSize} ${newUseTLS} \"${newServiceLabel}\" ${newSeverityFilter} ${newIdentityFilter}" \
|| logc "s r ${objid}"
fi
fi
;;
Device.X_ADB_SystemLog.FileLogging.* )
objid=${obj##*.}
if [ "$setEnable" = "1" ] || help_is_changed Append ServiceLabel \
IdentityFilter SeverityFilter StorageVolume Filename SizeLimit \
BufferedEntriesLimit Format HeaderFormat FooterFormat \
SizeLimitFormat ErrorFormat; then
logc "s l ${objid}"
if [ "$newEnable" = "true" ]; then
local baseDir filePath folder lvstatus online=1
if [ -n "$newStorageVolume" ]; then
cmclient -v baseDir GETV "${newStorageVolume}.X_ADB_MountPoint"
cmclient -v lvstatus GETV "${newStorageVolume}.Status"
[ "$lvstatus" != "Online" ] && online=0
else
baseDir=/tmp/log
fi
filePath="$baseDir/$newFilename"
folder="${filePath%/*}/"
case "$folder" in
/mnt/* | /tmp/log/* )
if [ "$online" = "1" ]; then
mkdir -p "$folder"
[ "$oldEnable" = "false" ] && [ "$newAppend" = "false" ] && rm -f "$filePath"
else
filePath="-"
fi
if [ -n "$newHeaderFormat" ]; then
local sn sv pc pr
. /etc/ah/helper_functions.sh
cmclient -v sn GETV DeviceInfo.SerialNumber
cmclient -v sv GETV DeviceInfo.SoftwareVersion
cmclient -v pc GETV DeviceInfo.ProductClass
cmclient -v pr GETV DeviceInfo.ProvisioningCode
newHeaderFormat=`help_str_replace "{sn}" "$sn" "$newHeaderFormat"`
newHeaderFormat=`help_str_replace "{sv}" "$sv" "$newHeaderFormat"`
newHeaderFormat=`help_str_replace "{pc}" "$pc" "$newHeaderFormat"`
newHeaderFormat=`help_str_replace "{pr}" "$pr" "$newHeaderFormat"`
fi
[ "$newAppend" = "true" ] && newAppend=1 || newAppend=0
logc "s l ${objid} \"$filePath\" $newBufferedEntriesLimit $newSizeLimit $newAppend \"$newFormat\" \"$newHeaderFormat\" \"$newFooterFormat\" \"$newSizeLimitFormat\" \"$newErrorFormat\" $newSeverityFilter \"${newServiceLabel:-*}\" \"$newIdentityFilter\""
;;
* )
exit 1
;;
esac
fi
fi
;;
esac
}
service_delete()
{
case "$obj" in
Device.X_ADB_SystemLog.Server.* )
objid=${obj##*.}
logc "s r ${objid}"
;;
Device.X_ADB_SystemLog.FileLogging.* )
objid=${obj##*.}
logc "s l ${objid}"
;;
esac
}
case "$op" in
g)
for arg
do
service_get "$obj" "$arg"
done
;;
s)
service_config
;;
d)
service_delete
;;
esac
exit 0
