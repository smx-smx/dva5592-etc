#!/bin/sh
case "$op" in
a)
case "$obj" in
Device.Services.VoiceService.*.SIP.Network.*)
;;
	*)
cmclient -v numiua GETV Device.Services.VoiceService.1.SIP.Registrar.1.AccountNumberOfEntries
cmclient -v maxiua GETV Device.Services.VoiceService.1.Capabilities.X_ADB_MaxIUAs
if [ "$numiua" != "" -a  "$maxiua" != "" ] && [ $numiua -gt $maxiua ]; then
cmclient DELE "$obj"
exit 4
fi
;;
esac
;;
esac
: > /etc/voip/reload
exit 0
