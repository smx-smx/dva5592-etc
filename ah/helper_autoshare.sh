#!/bin/sh
rootFolder="Folder.1"
autoshare_config_folder_access() {
	local lv="$1" user_p="$2" perm="$3" idx
	case "$perm" in
	"rw") perm="6" ;;
	"ro") perm="4" ;;
	esac
	cmclient DEL "${lv}.${rootFolder}.UserAccess"
	cmclient DEL "${lv}.${rootFolder}.GroupAccess"
	case "$user_p" in
	*UserAccount*)
		cmclient -v idx ADD "${lv}.${rootFolder}.UserAccess.[UserReference=$user_p]"
		idx="${lv}.${rootFolder}.UserAccess.${idx}"
		cmclient SETM "${idx}.Permissions=$perm	${idx}.Enable=true	${lv}.${rootFolder}.X_ADB_AllowGuestAccess=false"
		;;
	*UserGroup*)
		cmclient -v idx ADD "${lv}.${rootFolder}.GroupAccess.[GroupReference=$user_p]"
		idx="${lv}.${rootFolder}.GroupAccess.${idx}"
		cmclient SETM "${idx}.Permissions=$perm	${idx}.Enable=true	${lv}.${rootFolder}.X_ADB_AllowGuestAccess=false"
		;;
	"")
		cmclient SET "${lv}.${rootFolder}.X_ADB_AllowGuestAccess true"
		;;
	esac
}
service_reconf_permission() {
	local lvs lv setm=""
	[ "$newX_ADB_AutoshareEnable" != "true" ] && return 1
	cmclient -v lvs GETO "Device.Services.StorageService.1.LogicalVolume.[Enable=true]"
	for lv in $lvs; do
		setm="${setm:+$setm	}${lv}.${rootFolder}.X_ADB_Permission=$newX_ADB_AutosharePermission"
		autoshare_config_folder_access "$lv" "$newX_ADB_AutoshareUser" "$newX_ADB_AutosharePermission"
	done
	[ -n "$setm" ] && cmclient SETM "$setm"
	return 0
}
service_reconf_name() {
	local folder folders suffix setm=""
	[ "$newX_ADB_AutoshareLegacyNaming" = "true" ] && return 0
	cmclient -v folders GETO "Device.Services.StorageService.1.LogicalVolume.${rootFolder}.[X_ADB_ShareName>$oldX_ADB_AutoshareName]"
	for folder in $folders; do
		autoshare_set_name "$folder"
	done
	return 0
}
service_reconf_enable() {
	local enabled lvs lv
	case "$newX_ADB_AutoshareEnable" in
	"true")
		cmclient SET "Device.Services.StorageService.NetworkServer.[SMBEnable!true].SMBEnable true"
		cmclient -v enabled GETV "Device.Services.StorageService.Enable"
		[ "$enabled" != "true" ] && return 1
		cmclient -v lvs GETO "Device.Services.StorageService.1.LogicalVolume.[Enable=true]"
		for lv in $lvs; do
			autoshare_volume "$lv" "$newX_ADB_AutoshareUser"
		done
		;;
	"false")
		if [ -n "$newX_ADB_AutoshareUser" ]; then
			cmclient DEL "Device.Services.StorageService.LogicalVolume.${rootFolder}.UserAccess.[UserReference=$newX_ADB_AutoshareUser]"
			cmclient DEL "Device.Services.StorageService.LogicalVolume.${rootFolder}.GroupAccess.[GroupReference=$newX_ADB_AutoshareUser]"
		fi
		cmclient SETM "Device.Services.StorageService.LogicalVolume.${rootFolder}.X_ADB_ShareName=	Device.Services.StorageService.LogicalVolume.${rootFolder}.X_ADB_Permission=ro"
		cmclient SET "Device.Services.StorageService.1.NetworkServer.SMBEnable false"
		;;
	esac
}
autoshare_set_name() {
	local folder="$1" legacy share_name suffix tmp
	local lv="${folder%.Folder.*}"
	cmclient -v legacy GETV "Device.Services.StorageService.1.NetworkServer.X_ADB_AutoshareLegacyNaming"
	if [ "$legacy" = "true" ]; then
		getUniqueShareNameLetters "$folder"
	else
		cmclient -v share_name GETV "Device.Services.StorageService.1.NetworkServer.X_ADB_AutoshareName"
		[ ${#share_name} -eq 0 ] && cmclient -v share_name GETV "%(${lv}.PhysicalReference).Name"
		suffix=""
		while [ 1 ]; do
			cmclient -v tmp GETO "Device.Services.StorageService.LogicalVolume.Folder.[X_ADB_ShareName=$share_name$suffix]"
			[ ${#tmp} -eq 0 -o "$tmp" = "$folder" ] && break
			suffix=$((${suffix:-0} + 1))
		done
		cmclient SET "${folder}.X_ADB_ShareName $share_name$suffix"
	fi
}
autoshare_volume() {
	local ns="Device.Services.StorageService.1.NetworkServer" lv="$1" user_p="$2"
	autoshare_set_name "${lv}.${rootFolder}"
	cmclient -v perm GETV "${ns}.X_ADB_AutosharePermission"
	autoshare_config_folder_access "$lv" "$user_p" "$perm"
	cmclient SET "${lv}.Folder.Enable false"
	cmclient SETM "${lv}.${rootFolder}.X_ADB_Permission=$perm	${lv}.${rootFolder}.Enable=true"
}
autoshare_usb_event() {
	local ns="Device.Services.StorageService.1.NetworkServer" lv="$1"
	local enabled user_p phy
	cmclient -v enabled GETV "${ns}.X_ADB_AutoshareEnable"
	if [ "$enabled" != "true" ]; then
		cmclient SET "${ns}.[X_ADB_AutoshareStatus!Disabled].X_ADB_AutoshareStatus Disabled"
		return
	fi
	cmclient -v enabled GETV "Device.Services.StorageService.Enable"
	if [ "$enabled" != "true" ]; then
		cmclient SET "${ns}.X_ADB_AutoshareStatus Error_Misconfigured"
		return
	fi
	cmclient SET "${ns}.[SMBEnable!true].SMBEnable true"
	cmclient -v user_p GETV "${ns}.X_ADB_AutoshareUser"
	if [ -z "$user_p" ]; then
		cmclient SET "${ns}.[NetworkProtocolAuthReq=true].NetworkProtocolAuthReq false"
	else
		cmclient SET "${ns}.[NetworkProtocolAuthReq=false].NetworkProtocolAuthReq true"
	fi
	cmclient -v phy GETV "${lv}.PhysicalReference"
	help_serialize "$phy" notrap
	autoshare_volume "$lv" "$user_p"
	help_serialize_unlock "$phy" 2>/dev/null
	cmclient SET "${lv}.${rootFolder}.X_ADB_SambaRefresh true"
	cmclient SET "${ns}.X_ADB_AutoshareStatus Enabled"
}
