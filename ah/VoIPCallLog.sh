#!/bin/sh
AH_NAME="VoIPCallLog"
serviceId="${obj##*.VoiceService.}"
serviceId="${serviceId%%.*}"
voip_service="Services.VoiceService.${serviceId}"
service_reload_calllog() {
: > /etc/voip/reload_calllog
}
check_support_ext_sync() {
cmclient -v extsync GETV "${voip_service}.Capabilities.X_ADB_CallLogExternalSync"
if [ "$extsync" = "true" ]; then
return 1
else
return 0
fi
}
check_support_calllog_supp() {
cmclient -v calllogsupp GETV "${voip_service}.DECT.Base.1.X_ADB_CallLog"
if [ "$calllogsupp" = "true" ]; then
return 1
else
return 0
fi
}
service_add() {
cmclient -v numcall GETV Device.Services.VoiceService.1.CallLogNumberOfEntries
cmclient -v maxcall GETV Device.Services.VoiceService.1.Capabilities.MaxCallLogCount
[ "$numcall" = "" -o  "$maxcall" = "" ] && return 0
if [ "$maxcall" -ne "-1" ]; then
if [ "$numcall" -gt "$maxcall" ]; then
cmclient -v callobjs GETO Device.Services.VoiceService.1.CallLog
for callobj in $callobjs; do
cmclient DEL $callobj
break
done
fi
fi
if [ $suppcallolog = 1 ]; then
service_reload_calllog
return 0
fi
return 0
}
service_delete() {
service_reload_calllog
return 0
}
service_config() {
service_reload_calllog
return 0
}
check_support_ext_sync
suppextsync=$?
check_support_calllog_supp
suppcallolog=$?
ret=0
case "$op" in
a)	
if [ $suppextsync = 1 ] && [ "$user" = "stats" ]; then
cmclient DELE "$obj"
exit 0
fi
service_add
;;
d)
if [ $suppcallolog = 1 ]; then
service_delete
fi
;;
s)
if [ $suppcallolog = 1 ]; then
service_config
fi
;;
esac
exit 0
