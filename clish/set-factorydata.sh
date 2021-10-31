#!/bin/sh
. /etc/clish/clish-commons.sh
param="$1"
value="$2"
case "$param" in
"BaseMACAddress")
value=`echo "$value" | tr '[A-Z]' '[a-z]'`
;;
"WiFiWEPKey"*)
len=${#value}
if [ "$len" -eq "5" -o "$len" -eq "13" ]; then
echo "Assuming WEP key is in ASCII format"
echo "ascii WEP key=$value"
value=`ascii2hex "$value"`
elif [ "$len" -eq "10" -o "$len" -eq "26" ]; then
echo "Assuming WEP key is in hexadecimal format"
echo "Hexadecimal WEP key=$value"
value=$value
else
echo "Error! Wrong WEP key length: $len. Valid key lengths are 5-13 characters (ASCII) or 10-26 characters (HEX)"
exit 1
fi
;;
"WiFiKeyPassphrase"*)
wpa_len=${#value}
if [ $wpa_len -lt 8 -o $wpa_len -gt 63 ]; then
		echo "Error! Wrong WPA key length: $wpa_len. It shall be comprised in interval 8..63"
exit 1
fi
;;
esac
cmclient SET "Device.X_ADB_FactoryData.$param" "$value" > /dev/null
cmclient DUMPDM FactoryData /tmp/factory/deviceinfo.xml
