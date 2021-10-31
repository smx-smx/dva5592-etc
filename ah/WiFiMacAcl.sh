#!/bin/sh
AH_NAME="WiFiMacAcl"
service_reconf() {
local ifName=""
local macAclFile=""
local _macMode="$1"
local _macList="$2"
ifName=`cmclient GETV "$obj.Name"`
if [ -n "$ifName" ]; then
if [ "$_macMode" = "Accept" ]; then
macAclFile="/tmp/"$ifName".accept"
elif [ "$_macMode" = "Deny" ]; then
macAclFile="/tmp/"$ifName".deny"
else
return
fi
TMP_FILE=`mktemp -p /tmp`
oldIFS=$IFS
IFS=","
for macAddr in $_macList; do
echo $macAddr >> $TMP_FILE
done
IFS=$oldIFS
mv $TMP_FILE $macAclFile
fi
}
service_config() {
local macMode=""
local macList=""
if [ "${changedX_ADB_MacMode:=0}" -eq 1 -a "$newX_ADB_MacMode" != "None" ]; then
macList=`cmclient GETV "$obj.X_ADB_MacList"`
service_reconf "$newX_ADB_MacMode" "$macList"
fi
if [ "${changedX_ADB_MacList:=0}" -eq 1 ]; then
macMode=`cmclient GETV "$obj.X_ADB_MacMode"`
if [ "$macMode" != "None" ]; then
service_reconf "$macMode" "$newX_ADB_MacList"
fi
fi
}
case "$op" in
s)
service_config
;;
esac
exit 0
