#!/bin/sh
AH_NAME="WiFiRadioEnable"
LOCK_NAME="$AH_NAME"
[ "$op" != "s" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_serialize.sh && help_serialize "$LOCK_NAME"
. /etc/ah/helper_functions.sh
. /etc/ah/helper_radio_toogle.sh
case "$obj" in
Device.WiFi)
radio_main_toggle
cmclient SAVE
;;
esac
exit 0
