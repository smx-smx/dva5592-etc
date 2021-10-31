#!/bin/sh
[ "$user" = "yacs" ] && exit 0
[ "$user" = "voipservice" ] && exit 0
. /etc/ah/VoIPCommon.sh
. /etc/ah/helper_svc.sh
AH_NAME="VoIPService"
serviceId="${obj##*.VoiceService.}"
serviceId="${serviceId%%.*}"
phyInterfaceId="${obj##*.PhyInterface.}"
phyInterfaceId="${phyInterfaceId%%.*}"
VOIP_SERVICE="Services.VoiceService.${serviceId}"
VOIP_PROFILE="${VOIP_SERVICE}.VoiceProfile"
ROOT_CONF_DIR="/etc/cm/conf/"
provservId="Services.VoiceService.1"
if [ "$1" = "r" ]; then
op="r"
fi
sec=""
tabIdx=""
servobj=""
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize "VoipService" > /dev/null
map_obj2section() {
local par="$1"
tabIdx=""
servobj="$1"
servobj="${servobj#*Service.}"
subservobj="${servobj#*.}"
if [ "$servobj"	= "$subservobj" ]; then
servobj="VoiceService"
else
servobj="${subservobj%%.*}"
fi
}
service_provisionig() {
checkloadconf_region "All" "Ver1"
retval=$?
if [ $retval -eq 3 ]; then
echo "Unable to load CONF" && exit 2
elif [ $retval -eq 2 ]; then
correctchg=`cmclient SET -u voip "Device.Services.VoiceService.1.POTS.Region" $newX_ADB_Region`
retset="0"
for c in $correctchg
do
if [ "$c" != "OK" ]; then
retset="1"
fi
done
if [ "$retset" = "0" ]; then
echo "Correct set POTS.Region with value'$newX_ADB_Region'"
else
echo "Unable to set POTS.Region" && exit 2
fi
fi
}
service_config() {
local ret=0 global_enable="true" dectif min_se session_expires
case "$servobj" in
"X_ADB_SIP" )
if [ "$changedLocalPort" = 1 ]; then
init_natskip "SIP" "$newLocalPort"
fi
if [ "$changedSessionExpires" = 1 ]; then
cmclient -v min_se GETV "Device.Services.VoiceService.${serviceId}.X_ADB_SIP.MinSE"
if [ "$newSessionExpires" -lt "$min_se" ]; then
exit 2
fi
fi
if [ "$changedMinSE" = 1 ]; then
cmclient -v session_expires GETV "Device.Services.VoiceService.${serviceId}.X_ADB_SIP.SessionExpires"
if [ "$newMinSE" -gt "$session_expires" ]; then
cmclient SETE "Device.Services.VoiceService.${serviceId}.X_ADB_SIP.SessionExpires" $newMinSE
fi
if [ "$newMinSE" = "0" ]; then
cmclient SETE "Device.Services.VoiceService.${serviceId}.X_ADB_SIP.SessionExpires" $newMinSE
fi
fi
;;
esac
if [ "$changedX_ADB_PhyEnable" = 1 ]; then
cmclient -v dectif GETO Device.Services.VoiceService.1.PhyInterface.[Description="DECT"]
if [ "$dectif" = "$obj" ]; then
if [ "$user" != "global" -a "$global_enable" = "false" ]; then
echo "DECT is not available on this product"
ret=1
else
cmclient SETE Device.Services.VoiceService.1.DECT.Base.1.Enable $newX_ADB_PhyEnable
fi
fi
fi
if [ "$changedEnable" = "1" -a  "$obj" = "Device.Services.VoiceService.1.DECT.Base.1" ]; then
if [ "$user" != "global" -a "$global_enable" = "false" ]; then
echo "DECT is not available on this product"
ret=1
else
cmclient SETE Device.Services.VoiceService.1.PhyInterface.[Description="DECT"].X_ADB_PhyEnable $newEnable
[ "$newEnable" = "false" ] && cmclient SETEM "${obj}.X_ADB_PagingEnable=false	${obj}.SubscriptionEnable=false"
fi
fi
if [ "$changedX_ADB_Enable" = 1 ]; then
reconf_voip_iptables
if [ "$newX_ADB_Enable" = "false" ]; then
if [ -f /var/run/voip.pid ]; then
help_svc_stop voip '' '15'
rm /var/run/voip.pid
fi
fi
if [ "$newX_ADB_Enable" != "false" ]; then
if [ ! -f /var/run/voip.pid ]; then
pwrctl config --cpuspeed 0
help_svc_start "voip >/dev/console" voip '' '' '' '15'
fi
fi
fi
return $ret
}
service_reconf() {
local profile
local profiles
local profile_done
rm -f /etc/voip/*
/etc/ah/VoIPNetwork.sh r
/etc/ah/VoIPAgent.sh r
}
ret=0
service_del() {
case "$servobj" in
"DECT" )
;;
* )
;;
esac
}
force_voip_conf_reload() {
local changedvalue=""
local newvalue=""
changedvalue="$changedX_ADB_ConfReload";
newvalue="$newX_ADB_ConfReload";
if [ -n "$changedvalue" ] && [ "$changedvalue" -eq 1 ] && [ "$newvalue" = "true" ]; then
cmclient -u "$user" SETE "Device.Services.VoiceService.${serviceId}.X_ADB_ConfReload" false
: > /etc/voip/reload
echo "Reload Conf triggered" && exit 0;
fi
echo "Reload Conf NOT triggered" ;
}
map_obj2section "$obj"
service_provisionig
if [ "$user" = "POSTPROVISIONING" -o "$user" = "voip" ]; then
force_voip_conf_reload
fi
case "$op" in
a|d)
service_del
;;
r)
service_reconf
;;
s)
service_config
ret=$?
;;
esac
service_reload
exit $ret
