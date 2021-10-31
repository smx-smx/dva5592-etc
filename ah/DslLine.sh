#!/bin/sh
AH_NAME="DslLine"
. /etc/ah/target.sh
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" -o "$changedStandardUsed" = 1 -o "$changedLinkStatus" = 1 ] && exit 0
[ "$user" = "InterfaceMonitor" -o "$user" = "skip" ] && exit 0
if [ "$user" = "CWMP" -a "$setEnable" = "1" -a "$changedEnable" = "0" ]; then
. /etc/ah/helper_ifname.sh
help_lowlayer_obj_get tmp '%(Device.ManagementServer.X_ADB_ConnectionRequestInterface)' "$obj"
[ ${#tmp} -eq 0 ] || exit 0
unset tmp
fi
dsl_line_path="$obj"
phy_line=${obj##*.}
phy_line=$((phy_line - 1))
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
STATS_NOVAL="4294967295"		# used as default value for u_int data type vars
dsl_update_firmware_version() {
local xDslFirmwareVersion
xDslFirmwareVersion=`xdsl_get_version $phy_line`
xDslFirmwareVersion=${xDslFirmwareVersion##*-}
xDslFirmwareVersion=${xDslFirmwareVersion%%xdslctl*}
cmclient SET -u "DslLine${obj}" ${dsl_line_path}.FirmwareVersion $xDslFirmwareVersion
}
dsl_config_enable() {
local tmp
if [ "$1" = "true" ]; then
xdsl_initialize $phy_line
cmclient -v tmp GETO Device.DSL.BondingGroup.[Enable=true]
if [ -n "$tmp" ]; then
xdsl_enable_bonding_mediasearch $phy_line
else
xdsl_disable_bonding_mediasearch $phy_line
fi
dsl_reconfigure
xdsl_connection_up $phy_line
else
xdsl_connection_down $phy_line
xdsl_uninitialize $phy_line
fi
}
dsl_reconfigure() {
		configure_dsl
G994VENDORID="B5004244434D0000"
VENDORID="5900414442420000"
cmclient -v SERNUMBER GETV Device.DeviceInfo.SerialNumber
dsl_update_firmware_version
cmclient -v VERNUMBER GETV Device.DeviceInfo.SoftwareVersion
cmclient -v prof GETV Device.DeviceInfo.X_ADB_ProfileType
[ -n "$prof" ] && VERNUMBER="$VERNUMBER"_"$prof"
xdsl_set_hexVendorId $phy_line "$VENDORID"
xdsl_set_versionNumber $phy_line "$VERNUMBER"
xdsl_set_serialNumber $phy_line "$SERNUMBER"
xdsl_set_g994VendorId $phy_line "$G994VENDORID"
}
dsl_phy() {
dsl_update_firmware_version
cmclient -v version GETV ${dsl_line_path}.FirmwareVersion
echo "**** $version ****" > /dev/console
cmclient SET -u "DslLine${obj}" ${dsl_line_path}.FirmwareVersion $version
if [ -z ${version/A2p*/} ]; then
version="${version:0:1}${version:2:1}${version:3:1}${version:7:4}${version:12:4}"
else
version="${version:0:3}${version:4:9}"
version=${version/.d/.}
fi
cmclient -v tmp GETV ${dsl_line_path}.X_ADB_XTURModelShort
VERNUMBER="$version $tmp"
xdsl_set_versionNumber $phy_line "$VERNUMBER"
}
dsl_get_modulation() {
local cmdval=""
set -f
IFS=","
set -- $1
unset IFS
set +f
for arg
do
case $arg in
"G.992.1_Annex_A" | "G.992.1_Annex_B" | "G.992.1_Annex_C" )
printf d
;;
"G.992.2" )
printf l
;;
"T1.413" )
printf t
;;
"G.992.3_Annex_A" | "G.992.3_Annex_B" | "G.992.3_Annex_C" | "G.992.3_Annex_I" | "G.992.3_Annex_J" | "G.992.3_Annex_M" )
printf 2
;;
"G.992.3_Annex_L" )
printf e
;;
"G.992.5_Annex_A" | "G.992.5_Annex_B" | "G.992.5_Annex_C" | "G.992.5_Annex_I" | "G.992.5_Annex_J" )
printf p
;;
"G.992.5_Annex_M" )
printf m
;;
"G.993.2_Annex_A" | "G.993.2_Annex_B" | "G.993.2_Annex_C" )
printf v
;;
"G.9701" )
printf f
;;
* )
;;
esac
done
}
dsl_profile_2_hex() {
local _profile=0
set -f
IFS=","
set -- $1
unset IFS
set +f
for arg
do
case $arg in
"8a" )	_profile=$(( $_profile | 0x01 ))
;;
"8b" )	_profile=$(( $_profile | 0x02 ))
;;
"8c" ) 	_profile=$(( $_profile | 0x04 ))
;;
"8d" ) 	_profile=$(( $_profile | 0x08 ))
;;
"12a" )	_profile=$(( $_profile | 0x10 ))
;;
"12b" )	_profile=$(( $_profile | 0x20 ))
;;
"17a" )	_profile=$(( $_profile | 0x40 ))
;;
"30a" )	_profile=$(( $_profile | 0x80 ))
;;
"35b" )	_profile=$(( $_profile | 0x100 ))
;;
* )
;;
esac
done
printf "%x\n" $_profile
}
service_do_reconf() {
if [ "$newEnable" = "false" ]; then
dsl_config_enable "false"
return 0
elif [ "$newEnable" = "true" ]; then
dsl_config_enable "true"
fi
}
service_get() {
get_path="$1"
local buf="" xlsts=0
debug_dsl_stats=0
case "$get_path" in
*"ModulationType" )
case "$adsl_modulation_type" in
"ADSL2"* )
echo "ADSL_2plus" ;;
"VDSL"* )
echo "VDSL" ;;
"G.Dmt" )
echo "ADSL_G.dmt" ;;
"G.lite" )
echo "ADSL_G.lite" ;;
*)
echo "$adsl_modulation_type" ;;
esac
;;
*"XTUCCountry" | *"ATUCCountry" )
echo $adsl_country_id ;;
*"DataPath" )
echo $adsl_data_path ;;
*"XTUCVendor" | *"ATUCVendor" )
if [ -z "$adsl_vendor_id" ]; then
echo "00000000"
else
tmp=`echo $adsl_vendor_id|hexdump`
set -- $tmp
echo "${2}${3}"
fi
;;
*"CurrentProfile" )
echo $adsl_profile ;;
*"DownstreamMaxBitRate" | *"DownstreamMaxRate")
echo $adsl_max_down_rate ;;
*"UpstreamMaxBitRate" | *"UpstreamMaxRate")
echo $adsl_max_up_rate ;;
*"DownstreamAttenuation" )
echo $adsl_down_attn ;;
*"UpstreamAttenuation" )
echo $adsl_up_attn ;;
*"DownstreamNoiseMargin" )
echo $adsl_down_snr ;;
*"SNRMpbus" )
help_get_dsl_SNRMpb us ;;
*"SNRMpbds" )
help_get_dsl_SNRMpb ds ;;
*"PowerManagementState" )
echo $adsl_power_state ;;
*LastChange)
help_lastChange_get "$obj"
;;
*"UpstreamNoiseMargin" )
echo $adsl_up_snr ;;
*"DownstreamPower" )
echo $adsl_down_pwr ;;
*"UpstreamPower" )
echo $adsl_up_pwr ;;
*"UpstreamCurrRate" )
echo ${adsl_bearer_up_rate:-$STATS_NOVAL}
;;
*"DownstreamCurrRate" )
echo ${adsl_bearer_down_rate:-$STATS_NOVAL}
;;
*"PacketsReceived" )
if [ -n "$adsl_down_sf" ]; then
echo $adsl_down_sf
else
echo $vdsl_down_sf
fi
;;
*"PacketsSent" )
if [ -n "$adsl_up_sf" ]; then
echo $adsl_up_sf
else
echo $vdsl_up_sf
fi
;;
*"BytesReceived" )
if [ -n "$adsl_down_sf" -a -n "$adsl_down_b" ]; then
echo $(($adsl_down_sf*69*$((adsl_down_b+1))))
elif [ -n "$vdsl_down_sf" -a -n "$adsl_down_b" ]; then
echo $(($vdsl_down_sf*257*$((adsl_down_b+1))))
else
echo
fi
;;
*"BytesSent" )
if [ -n "$adsl_up_sf" -a -n "$adsl_up_b" ]; then
echo $(($adsl_up_sf*69*$((adsl_up_b+1))))
elif [ -n "$vdsl_up_sf" -a -n "$adsl_down_b" ]; then
echo $(($vdsl_up_sf*257*$((adsl_down_b+1))))
else
echo
fi
;;
*"ErrorsReceived" )
if [ -n "$adsl_down_sferr" ]; then
echo $adsl_down_sferr
else
echo $vdsl_down_sferr
fi
;;
*"ErrorsSent" )
if [ -n "$adsl_up_sferr" ]; then
echo $adsl_up_sferr
else
echo $vdsl_up_sferr
fi
;;
*"TotalStart")
echo ${adsl_totalstart}
;;
*"LastShowtimeStart" )
echo ${adsl_sincelastshowtimestart}
;;
*"ShowtimeStart" )
echo ${adsl_showtimestart}
;;
*"CurrentDayStart" )
echo ${adsl_currentdaystart}
;;
*"QuarterHourStart" )
echo ${adsl_quarterhourstart}
;;
*"Stats.Total.ErroredSecs" )
echo ${adsl_down_total_es:-$STATS_NOVAL}
;;
*"Stats.QuarterHour.ErroredSecs" )
echo ${adsl_down_quarterhour_es:-$STATS_NOVAL}
;;
*"Stats.CurrentDay.ErroredSecs" )
echo ${adsl_down_currentday_es:-$STATS_NOVAL}
;;
*"Stats.Showtime.ErroredSecs" )
echo ${adsl_down_showtime_es:-$STATS_NOVAL}
;;
*"Stats.LastShowtime.ErroredSecs" )
echo ${adsl_down_sincelastshowtime_es:-$STATS_NOVAL}
;;
*"Stats.Total.SeverelyErroredSecs" )
echo ${adsl_down_total_ses:-$STATS_NOVAL}
;;
*"Stats.QuarterHour.SeverelyErroredSecs" )
echo ${adsl_down_quarterhour_ses:-$STATS_NOVAL}
;;
*"Stats.CurrentDay.SeverelyErroredSecs" )
echo ${adsl_down_currentday_ses:-$STATS_NOVAL}
;;
*"Stats.Showtime.SeverelyErroredSecs" )
echo ${adsl_down_showtime_ses:-$STATS_NOVAL}
;;
*"Stats.LastShowtime.SeverelyErroredSecs" )
echo ${adsl_down_sincelastshowtime_ses:-$STATS_NOVAL}
;;
*"Stats.X_ADB_DSLRetrainNumber" )
echo ${adsl_retrain_number:-$STATS_NOVAL}
;;
* )
echo "### $AH_NAME: Nothing to do ###" > /dev/null
;;
esac
}
configure_dsl() {
local initcfg=" "
local tmpcmd=""
local mod=""
local cfg="--phycfg 0 0 0 0 0" phycfg=0x0 phycfgmask=0x0 auxcfg=0x0 auxcfgmask=0x0
case "$newX_ADB_AllowedStandards" in
*"Auto"*)
mod=`dsl_get_modulation $newStandardsSupported`
;;
"")
;;
*)
mod=`dsl_get_modulation $newX_ADB_AllowedStandards`
;;
esac
if [ -n "$mod" ]; then
initcfg="$initcfg --mod $mod"
fi
if [ -n "$newX_ADB_AllowedProfiles" ]; then
local profiles
[ "${newX_ADB_AllowedProfiles%%Auto*}" = "${newX_ADB_AllowedProfiles}" ] && profiles=${newX_ADB_AllowedProfiles} || profiles=${newAllowedProfiles}
local tmp_profile=`dsl_profile_2_hex "$profiles"`
initcfg="$initcfg --profile 0x$tmp_profile"
fi
local bitswap=""
case "$newX_ADB_BitSwap" in
""|"0")
bitswap="off"
;;
*)
bitswap="on"
;;
esac
initcfg="$initcfg --bitswap $bitswap"
[ -n "$newX_ADB_TargetSNR" ] && [ "$newX_ADB_TargetSNR" -gt 0 ] && \
initcfg="$initcfg --snr $newX_ADB_TargetSNR"
local sra=""
case "$newX_ADB_SRA" in
""|"0")
sra="off"
;;
*)
sra="on"
;;
esac
initcfg="$initcfg --sra $sra"
local sos=""
case "$newX_ADB_SOS" in
"0")
sos="off"
;;
"1")
sos="on"
;;
esac
[ -n "$sos" ] && initcfg="$initcfg --SOS $sos"
local dynamicF=""
case "$newX_ADB_DynamicF" in
"0")
dynamicF="off"
;;
"1")
dynamicF="on"
;;
esac
[ -n "$dynamicF" ] && initcfg="$initcfg --dynamicF $dynamicF"
local dynamicD=""
case "$newX_ADB_DynamicD" in
"0")
dynamicD="off"
;;
"1")
dynamicD="on"
;;
esac
[ -n "$dynamicD" ] && initcfg="$initcfg --dynamicD $dynamicD"
local V43=""
case "$newX_ADB_V43" in
"-1")
V43=""
;;
""|"0")
V43="off"
;;
*)
V43="on"
;;
esac
if [ "$V43" != "" ]
then
initcfg="$initcfg --V43 $V43"
fi
local lpair=""
if [ "$newLineNumber" = "1" ]; then
lpair="i"
else
lpair="o"
fi
initcfg="$initcfg --lpair $lpair"
local trellis=""
if [ "$newTRELLISds" = "1" ]; then
trellis="on"
else
trellis="off"
fi
initcfg="$initcfg --trellis $trellis"
if [ -n "$newX_ADB_PhyR" ]; then
initcfg="$initcfg --phyReXmt $newX_ADB_PhyR"
fi
if [ -n "$newX_ADB_GINP" ]; then
initcfg="$initcfg --Ginp $newX_ADB_GINP"
else
initcfg="$initcfg --Ginp 0"
fi
local monitorTone=""
if [ "$newX_ADB_MonitorTone" = "1" ]; then
monitorTone="on"
else
monitorTone="off"
fi
initcfg="$initcfg --monitorTone $monitorTone"
if [ "$newX_ADB_ToggleJ43B43" = "1" ]; then
initcfg="$initcfg --toggleJ43B43 on"
else
initcfg="$initcfg --toggleJ43B43 off"
fi
xdsl_initial_configuration "$phy_line" "$initcfg"
if [ $newX_ADB_EnableATTNDRframingConstrains -ge 0 ]; then
phycfg=$(($phycfg | ($newX_ADB_EnableATTNDRframingConstrains << 15) ))
phycfgmask=$(($phycfgmask | 0x00008000))
fi
if [ $newX_ADB_NoG994AVdslToggle -ge 0 ]; then
phycfg=$(($phycfg | ($newX_ADB_NoG994AVdslToggle << 4) ))
phycfgmask=$(($phycfgmask | 0x00000010))
fi
if [ $newX_ADB_AlignAfterPeriodics -ge 0 ]; then
phycfg=$(($phycfg | ($newX_ADB_AlignAfterPeriodics << 5) ))
phycfgmask=$(($phycfgmask | 0x00000020))
fi
if [ $newX_ADB_DynamicV43handling -ge 0 ]; then
phycfg=$(($phycfg | ($newX_ADB_DynamicV43handling << 23) ))
phycfgmask=$(($phycfgmask | 0x00800000))
fi
if [ $newX_ADB_SOS -ge 0 -a $newX_ADB_SOS -lt 2 ]; then
auxcfg=$(($auxcfg | ($newX_ADB_SOS << 27) ))
auxcfgmask=$(($auxcfgmask | 0x08000000))
fi
if [ $newX_ADB_EnableROC -ge 0 ]; then
auxcfg=$(($auxcfg | ($newX_ADB_EnableROC << 28) ))
auxcfgmask=$(($auxcfgmask | 0x10000000))
fi
if [ "$phycfgmask" != "0x0" -o "$auxcfgmask" != "0x0" ]; then
cfg=$(printf "%s 0x%x 0x%x 0x%x 0x%x" "$cfg" "$auxcfgmask" "$auxcfg" "$phycfgmask" "$phycfg")
xdsl_set_configuration "$phy_line" "$cfg"
fi
}
service_config() {
if [ "$changedStatus" = 1 ]; then
help_if_link_change "$newName" "$newStatus" "$AH_NAME"
elif [ "$setEnable" = 1 ] || help_is_changed X_ADB_AllowedStandards X_ADB_AllowedProfiles X_ADB_BitSwap X_ADB_TargetSNR \
X_ADB_SRA X_ADB_G992DTF X_ADB_DynamicF X_ADB_DynamicD X_ADB_V43 LineNumber TRELLISds X_ADB_ToggleJ43B43 \
X_ADB_EnableATTNDRframingConstrains X_ADB_NoG994AVdslToggle X_ADB_AlignAfterPeriodics X_ADB_DynamicV43handling \
X_ADB_PhyR X_ADB_GINP X_ADB_MonitorTone X_ADB_EnableROC X_ADB_SOS; then
rm -f /tmp/cfg/cache/xdslctl${phy_line}
service_do_reconf
elif [ "$setX_ADB_Reset" = "1" -a "$newEnable" = "true" ]; then
dsl_config_enable false
dsl_config_enable true
fi
if [ "$setX_ADB_PhyReconf" = "1" -a "$newEnable" = "true" ]; then
dsl_phy
fi
if [ "$newEnable" = "true" -a "$changedEnable" = 1 ]; then
cmclient -v annex_autosense GETV "${dsl_line_path}.X_ADB_AnnexAutosense.Enable"
if [ "$annex_autosense" = "true" ];
then
cmclient -v autosense_timeout GETV "${dsl_line_path}.X_ADB_AnnexAutosense.Timeout"
cmclient -v autosense_fallback GETV "${dsl_line_path}.X_ADB_AnnexAutosense.Fallback"
if [ "$autosense_fallback" = "Switch" ]
then
case "$newX_ADB_Annex" in
A)
next_annex="B"
;;
B)
next_annex="A"
;;
*)
next_annex="A"
;;
esac
if [ $autosense_timeout -le 43200 ]
then
next_timeout=$(($autosense_timeout * 2))
cmclient -u "${AH_NAME}${obj}" SET ${obj}.X_ADB_AnnexAutosense.Timeout "$next_timeout"
else
cmclient -u "${AH_NAME}${obj}" SET ${obj}.X_ADB_AnnexAutosense.Timeout 86400
fi
else
next_annex=$autosense_fallback
fi
cmclient -v i ADD "Device.X_ADB_Time.Event"
eventObj="Device.X_ADB_Time.Event.$i"
setm_params="$eventObj.Alias=AutosenseTimeout"
setm_params="$setm_params	$eventObj.Type=Aperiodic"
setm_params="$setm_params	$eventObj.DeadLine=$autosense_timeout"
cmclient -v j ADD "$eventObj.Action"
setm_params="$setm_params	$eventObj.Action.$j.Operation=Set"
setm_params="$setm_params	$eventObj.Action.$j.Path=$obj.X_ADB_Annex"
setm_params="$setm_params	$eventObj.Action.$j.Value=$next_annex"
cmclient SETM "$setm_params"
cmclient SET "$eventObj.Enable" "true"
fi
else
cmclient DEL "Device.X_ADB_Time.Event.[Alias=AutosenseTimeout]"
fi
if [ "$changedX_ADB_Annex" = 1 ]; then
cmclient -v current_standard GETV ${dsl_line_path}.StandardUsed
case $current_standard in
""|"G.993.2"*)
access_tecnology="VDSL"
;;
*)
access_tecnology="ADSL"
;;
esac
cmclient -v annex_configuration GETO "${dsl_line_path}.X_ADB_AnnexAutosense.AnnexConfiguration.[Annex=${newX_ADB_Annex}].[AccessTecnology=${access_tecnology}]"
if [ -z "$annex_configuration" ]; then
cmclient -v annex_configuration GETO "${dsl_line_path}.X_ADB_AnnexAutosense.AnnexConfiguration.[Annex=${newX_ADB_Annex}].[AccessTecnology=Both]"
fi
cmclient -v parameters GETO ${annex_configuration}.Parameter
for p in $parameters
do
cmclient -v path GETV ${p}.Path
cmclient -v value GETV ${p}.Value
setm_params="${setm_params}${path}=${value}	"
done
if [ -n "$setm_params" ]; then
(cmclient SETM "$setm_params" && cmclient SAVE && sleep 5 && reboot) &
else
(sleep 5 && reboot) &
fi
case $newX_ADB_Annex in
"A")
echo pots > /tmp/cfg/xdsl-mode
;;
"B")
echo isdn > /tmp/cfg/xdsl-mode
;;
*)
echo isdn > /tmp/cfg/xdsl-mode
;;
esac
fi
}
case "$op" in
g)
. /etc/ah/helper_lastChange.sh
. /etc/ah/helper_dsl.sh
help_get_dsl_stats
case "$obj" in
*"InternetGatewayDevice"* )
help_get_dsl_vendor	;;
esac
for arg # Arg list as separate words
do
service_get "$obj.$arg"
done
;;
s)
case "$obj" in
*)
service_config
;;
esac
;;
esac
exit 0
