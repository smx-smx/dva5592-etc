#!/bin/sh
. /etc/ah/VoIPCommon.sh
AH_NAME="VoIPPhoneBook"
serviceId="${obj##*.VoiceService.}"
serviceId="${serviceId%%.*}"
PhoneBookId="${obj##*.X_ADB_PhoneBook.}"
PhoneBookId="${PhoneBookId%%.*}"
profobj=""
profobj="${obj#*X_ADB_PhoneBook.}"
subprofobj="${profobj#*.}"
if [ "$profobj"	= "$subprofobj" ]; then
profobj="X_ADB_PhoneBook"
else
profobj="${subprofobj%%.*}"
fi
case "$profobj" in
"X_ADB_PhoneBook" )
phonenumberpath="0"
;;
"PhoneNumbers" )
phonenumberpath="1"
;;
esac
voip_service="Services.VoiceService.${serviceId}"
service_reload_phonebook() {
: > /etc/voip/reload_phonebook
}
check_number_phone() {
if [ "$phonenumberpath" = "1" ]; then
if [ "$changedType" = "1" ]; then
PhoneNumberId="${obj##*.PhoneNumbers.}"
PhoneNumberId="${PhoneNumberId%%.*}"
cmclient -v pbobjs GETO "${voip_service}.X_ADB_PhoneBook.${PhoneBookId}.PhoneNumbers."
for pbentry in $pbobjs; do
currentPnId="${pbentry##*.PhoneNumbers.}"
currentPnId="${currentPnId%%.*}"
if [ ${PhoneNumberId} -ne ${currentPnId} ]; then
cmclient -v pbnumbtype GETV ${voip_service}.X_ADB_PhoneBook.${PhoneBookId}.PhoneNumbers.${currentPnId}.Type
if [ "$newType" = "${pbnumbtype}" ]; then
exit 7
fi
fi
done
fi
fi	
}
service_add() {
cmclient -v numcall GETV Device.Services.VoiceService.1.X_ADB_PhoneBookNumberOfEntries
cmclient -v maxcall GETV Device.Services.VoiceService.1.Capabilities.X_ADB_MaxPhoneBookCount
[ "$numcall" = "" -o  "$maxcall" = "" ] && return 0
if [ "$maxcall" -ne "-1" ]; then
if [ "$numcall" -gt "$maxcall" ]; then
cmclient DELE ${obj}
exit 4
fi
fi
service_reload_phonebook
return 0
}
service_delete() {
service_reload_phonebook
return 0
}
service_config() {
service_reload_phonebook
return 0
}
ret=0
case "$op" in
a)
service_add
ret=$?
;;
d)
service_delete
ret=$?
;;
s)
service_config
ret=$?
;;
esac
exit $ret
