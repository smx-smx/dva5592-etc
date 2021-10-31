#!/bin/sh
[ "$user" = "yacs" ] && exit 0
[ "$user" = "voipservice" ] && exit 0
. /etc/ah/VoIPCommon.sh
. /etc/ah/helper_svc.sh
AH_NAME="VoIPServiceV2"
serviceId="${obj##*.VoiceService.}"
serviceId="${serviceId%%.*}"
phyInterfaceId="${obj##*.PhyInterface.}"
phyInterfaceId="${phyInterfaceId%%.*}"
voip_service="Services.VoiceService.${serviceId}"
error_region="0"
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize "VoipServiceV2" >/dev/null
. /etc/ah/helper_functions.sh
checkregion_changed() {
	checkloadconf_region "Test" "Ver2"
	retval=$?
	if [ $retval -eq 1 ]; then
		checkloadconf_region "All" "Ver2"
		retval=$?
		if [ $retval -eq 2 ]; then
			cmclient DELE "${voip_service}.Tone.EventProfile."
			cmclient DELE "${voip_service}.Tone.Description."
			cmclient DELE "${voip_service}.Tone.Pattern."
			cmclient CONF "${ROOT_CONF_DIR}$newRegion/factory_voip_tone.$newRegion.xml"
			cmclient DELE "${voip_service}.POTS.FXS."
			cmclient CONF "${ROOT_CONF_DIR}$newRegion/factory_voip_v2.$newRegion.xml"
			cmclient DELE "${voip_service}.POTS.Ringer.Event."
			cmclient CONF "${ROOT_CONF_DIR}$newRegion/factory_voip_ring.$newRegion.xml"
			cmclient SAVE
		elif [ $retval -eq 3 ]; then
			echo "Cannot load configuration"
			error_region="1"
		fi
	fi
}
ret=0
echo "$AH_NAME running."
checkregion_changed
if [ "$error_region" = "1" ]; then
	echo "Error to load CONF" && exit 2
fi
case "$op" in
a) ;;

d) ;;

s)
	ret=$?
	;;
esac
service_reload
exit $ret
