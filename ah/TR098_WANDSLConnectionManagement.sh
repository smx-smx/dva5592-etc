#!/bin/sh
AH_NAME="TR098_WANDSLConnectionManagement"
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
wan_path=${obj%.*}
wan_device=${wan_path%.*}
wan_path=${wan_device%.*}
wan_path=${wan_path%.*}
case "$op" in
"a")
linkconfobj=`cmclient GETO "$wan_path.WANDSLInterfaceConfig."`
if [ -n "$linkconfobj" ]; then
i=`cmclient ADD "$wan_path.WANDSLConnectionManagement.ConnectionService"`
cmclient SET "$wan_path.WANDSLConnectionManagement.ConnectionService.$i.WANConnectionDevice" "$wan_device" > /dev/null
cmclient SET "$wan_path.WANDSLConnectionManagement.ConnectionService.$i.WANConnectionService" "$obj" > /dev/null
fi
;;
"d")
for ConnectionService_obj in `cmclient GETO "$wan_path.WANDSLConnectionManagement.ConnectionService.[WANConnectionService=$obj]"`
do
cmclient DEL "$ConnectionService_obj" > /dev/null
done
;;
esac
exit 0
