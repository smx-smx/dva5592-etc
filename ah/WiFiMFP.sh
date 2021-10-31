#!/bin/sh
AH_NAME="WiFiMFP"
. /etc/ah/target.sh
case "$op" in
g) wifiradio_get_hw_support "mfp" && echo "Disabled,Optional,Required" || echo "" ;;
esac
exit 0
