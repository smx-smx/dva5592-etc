#!/bin/sh
AH_NAME="Autoshare.sh"
. /etc/ah/helper_serialize.sh
. /etc/ah/helper_autoshare.sh
service_config() {
local err=0 lvs lv reconfEnable=0 ss="Device.Services.StorageService.1"
help_is_changed X_ADB_AutoshareName X_ADB_AutosharePermission \
X_ADB_AutoshareUser X_ADB_AutoshareEnable && reconfEnable=1
[ $changedX_ADB_AutoshareName -eq 1 ] && service_reconf_name
[ $changedX_ADB_AutosharePermission -eq 1 ] && service_reconf_permission
if [ $changedX_ADB_AutoshareUser -eq 1 ]; then
cmclient -v lvs GETO "${ss}.LogicalVolume"
for lv in $lvs; do
autoshare_config_folder_access "$lv" "$newX_ADB_AutoshareUser" "$newX_ADB_AutosharePermission"
done
fi
if [ $changedX_ADB_AutoshareEnable -eq 1 ]; then
if service_reconf_enable; then
if [ "$newX_ADB_AutoshareEnable" = "true" ]; then
cmclient SET "${ss}.NetworkServer.X_ADB_AutoshareStatus Enabled"
elif [ "$newX_ADB_AutoshareEnable" = "false" ]; then
cmclient SET "${ss}.NetworkServer.X_ADB_AutoshareStatus Disabled"
fi
else
[ "$newX_ADB_AutoshareEnable" = "true" ] && cmclient SET "${ss}.NetworkServer.X_ADB_AutoshareStatus Error_Misconfigured"
fi
fi
if [ "$newSMBEnable" = "true" ] || [ "$reconfEnable" -eq 1 ]; then
cmclient SET "${ss}.HTTPServer.[Enable=true].X_ADB_Reset" "true"
cmclient SET "${ss}.HTTPSServer.[Enable=true].X_ADB_Reset" "true"
cmclient SET "${ss}.X_ADB_HTTPServerRemote.[Enable=true].X_ADB_Reset" "true"
cmclient SET "${ss}.X_ADB_HTTPSServerRemote.[Enable=true].X_ADB_Reset" "true"
fi
}
result=0
case "$op" in
"s")
service_config
;;
esac
exit 0
