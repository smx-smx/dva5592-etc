#!/bin/sh
AH_NAME="uiPage"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
service_config() {
local OriginType
if [ "$user" = "CWMP" ]; then
OriginType="ACS"
else
OriginType="User"
fi
cmclient SETE $obj.Origin $OriginType
return 0
}
case "$op" in
s)
service_config
;;
esac
exit 0