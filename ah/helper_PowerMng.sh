#!/bin/sh
rxchain_set_parameters() {
	local objs=$1 tempFile=$2 radioName=$3 val obj
	for obj in $objs; do
		cmclient -v val GETV "$obj.RxchainPowerSaveQuietTime"
		echo "rxchain_pwrsave_quiet_time=$val"
		cmclient -v val GETV "$obj.RxchainPowerSavePps"
		echo "rxchain_pwrsave_pps=$val"
		cmclient -v val GETV "$obj.RxchainPowerSaveEnable"
		[ "$val" = "true" ] && val=1 || val=0
		echo "rxchain_pwrsave_enable=$val"
		echo "rxchain_pwrsave_stas_assoc_check=$val"
	done >>"$tempFile.$radioName"
}
radiopwrsave_set_parameters() {
	local objs=$1 tempFile=$2 radioName=$3 val obj
	for obj in $objs; do
		cmclient -v val GETV "$obj.RadioPowerSaveQuietTime"
		echo "radio_pwrsave_quiet_time=$val"
		cmclient -v val GETV "$obj.RadioPowerSavePps"
		echo "radio_pwrsave_pps=$val"
		cmclient -v val GETV "$obj.RadioPowerSaveEnable"
		[ "$val" = "true" ] && val=1 || val=0
		echo "radio_pwrsave_enable=$val"
		echo "radio_pwrsave_stas_assoc_check=$val"
	done >>"$tempFile.$radioName"
}
configure_power_mng() {
	local radioName=$1 radioTempFile=$2 objs radioObj
	cmclient -v radioObj GETO "Device.WiFi.Radio.[Name=$radioName]"
	cmclient -v objs GETO "$radioObj.X_ADB_PowerManagement"
	rxchain_set_parameters "$objs" "$radioTempFile" "$radioName"
	radiopwrsave_set_parameters "$objs" "$radioTempFile" "$radioName"
}
