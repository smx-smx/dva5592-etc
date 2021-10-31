#!/bin/sh
AH_NAME="VoIPProfileReset"
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_serialize.sh && help_serialize >/dev/null
. /etc/ah/helper_functions.sh
VOIP_CTRLIF_ADDR="local:/tmp/voip_socket"
service_config() {
	if [ "$setReset" = "1" -a "$newReset" = "true" ]; then
		profile_idx=${obj##*VoiceProfile.}
		profile_idx=${profile_idx%%.}
		echo "RESET" "$profile_idx" | nc $VOIP_CTRLIF_ADDR
	fi
}
case "$op" in
s)
	service_config
	;;
esac
exit 0
