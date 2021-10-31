#!/bin/sh
is_smp()
{
local _l _v
while IFS="	: "  read -r _l _v _ ; do
[ "$_l" = "processor" ] && [ "$_v" = "1" ] && return 0
done < /proc/cpuinfo
return 1
}
eth_set_egress_tm()
{
/bin/tmctl porttminit --devtype 0 --if "$1" --flag 1
echo "Configuring $1 queue"
/bin/tmctl setqcfg --devtype 0 --if "$1" --qid 0 --priority 0 --qsize 1024 --weight 0 --schedmode 1 --shapingrate 0 --burstsize 0 --minrate 0
}
get_wan_type() {
:
}
set_wan_type() {
:
}
wait_set_sched_affinity()
{
local _pid=`pidof $1` i=10 cmd=
case "$2" in
[r,f,b,o,i]-[1-9][0-9]|[r,f,b,o,i]-[0-9])
[ -x /usr/bin/chrt ] || return 1
cmd="/usr/bin/chrt -p -${2%-*} ${2#*-}"
;;
a-[1-3])
[ -x /usr/bin/taskset ] || return 1
cmd="/usr/bin/taskset -p ${2#*-}"
;;
*)
return 1
;;
esac
while [ ${#_pid} -eq 0 -a $((i=i-1)) -gt 0 ]; do sleep 0.5 ; _pid=`pidof $1` ; done
[ ${#_pid} -eq 0 ] && return 1
for _pid in $_pid ; do $cmd $_pid ; done
return 0
}
eth_eee_get()
{
local _v
ethctl $1 reg 13 0x7
ethctl $1 reg 14 0x3c
ethctl $1 reg 13 0x4007
read _ _ _ _ _ _ _ _v << EOF
`ethctl $1 reg 14 2>&1`
EOF
[ "$_v" = "0x0006" ]
}
eth_eee_set()
{
ethctl $1 reg 13 0x7
ethctl $1 reg 14 0x3c
ethctl $1 reg 13 0x4007
[ "$2" = "true" ] && ethctl $1 reg 14 6 || ethctl $1 reg 14 0
}
eth_get_link_status()
{
local ifname="$1" sub_port_option=""
if [ "$ifname" = "eth0" ]; then
sub_port_option="port 9"
fi
if [ -d /sys/class/net/"$ifname" ]; then
link_status=`ethctl "$ifname" media-type $sub_port_option 2>&1`
_status="${link_status##*"Link is "}"
case "$_status" in
"up")	echo "Up"
;;
*)	echo "Down"
;;
esac
else
echo "Down"
fi
}
eth_get_media_type()
{
local ifname="$1" sub_port_option=""
if [ "$ifname" = "eth0" ]; then
sub_port_option="port 9"
fi
link_status=`ethctl "$ifname" media-type $sub_port_option 2>&1`
dup=""
speed=""
for tok in $link_status; do
case "$tok" in
1000*) speed="1000" ;;
100baseTx-FD.) speed="100FD" ;;
100baseTx.) speed="100HD" ;;
100baseT4.) speed="100HD" ;;
10baseT.) speed="10HD" ;;
10baseT-FD.) speed="10FD" ;;
10|100) speed="$tok" ;;
half*|Half*) dup="HD" ;;
full*|Full*) dup="FD" ;;
esac
done
echo "$speed""$dup"
}
eth_set_media_type()
{
local ifname="$1" speed="$2" duplex="$3" sub_port_option=""
if [ "$ifname" = "eth0" ]; then
sub_port_option="port 9"
fi
if [ "$speed" = "Auto" ]; then
echo "### Executing <ethctl $ifname media-type auto> ###"
ethctl "$ifname" media-type auto $sub_port_option
else
case "$speed" in
"1000" ) param_mbr="1000" ;;
"100" ) param_mbr="100" ;;
"10" ) param_mbr="10" ;;
* ) param_mbr="100" ;;
esac
case "$duplex" in
"Half" ) param_duplex="HD" ;;
"Full" ) param_duplex="FD" ;;
* ) param_duplex="FD" ;;
esac
echo "### Executing <ethctl $ifname media-type $param_mbr $param_duplex> ###"
ethctl "$ifname" media-type "$param_mbr""$param_duplex" $sub_port_option
fi
}
eth_set_wan()
{
local ifname="$1" enable="$2" ethctl="$3"
case "$enable" in
"true" )
if [ "$ethctl" = "true" ]; then
echo "### Executing <ethctl $ifname wan enable> ###"
ethctl "$ifname" wan enable
else
echo "### Executing <echo 1 > /proc/hwswitch/default/devices/"$ifname"/wan> ###"
echo 1 > /proc/hwswitch/default/devices/"$ifname"/wan
fi
;;
"false" )
if [ "$ethctl" = "true" ]; then
echo "### Executing <ethctl $ifname wan disable> ###"
ethctl "$ifname" wan disable
else
echo "### Executing <echo 0 > /proc/hwswitch/default/devices/"$ifname"/wan> ###"
echo 0 > /proc/hwswitch/default/devices/"$ifname"/wan
fi
;;
* )
echo "@@@@@@ ERROR: eth_set_wan called with params $1 $2 @@@@@@"
;;
esac
}
hw_specific_post_up() {
local _ifname="$1" boardid=""
. /etc/ah/helper_functions.sh
help_get_boardid boardid
case "$boardid" in
*"963381VV3"* | *"963381DV3"*)
[ "$_ifname" = "eth4" ] || return
ethctl eth4 reg 28 0x941e
ethctl eth4 reg 24 0x0c00
ethctl eth4 reg 23 0x0021
ethctl eth4 reg 21 0x470f
;;
963138*)
[ "$_ifname" = "eth0" ] || return
ethctl phy serdespower "$ifname" 1
;;
esac
}
hw_specific_post_down() {
local _ifname="$1" boardid=""
. /etc/ah/helper_functions.sh
help_get_boardid boardid
case "$boardid" in
963138*)
[ "$_ifname" = "eth0" ] || return
ethctl phy serdespower "$ifname" 2
;;
esac
}
eth_set_power()
{
local ifname="$1" enable="$2"
case "$enable" in
"up" )
echo "### Executing <ethctl $ifname phy-power up> ###"
ethctl "$ifname" phy-power up
hw_specific_post_up "$ifname"
;;
"down" )
echo "### Executing <ethctl $ifname phy-power down> ###"
ethctl "$ifname" phy-power down
hw_specific_post_down "$ifname"
;;
* )
echo "@@@@@@ ERROR: eth_set_power called with params $1 $2 @@@@@@"
;;
esac
}
eth_set_gmac_mode()
{
local _ifname="$1" _status="$2" outdev gmacmode=1
[ -x /bin/gmacctl -a "$_status" = "Up" -a ${#_ifname} -gt 0 ] || return
[ -f /proc/driver/qos/"$_ifname" ] || return
cmclient -v upstream GETV Device.Ethernet.Interface.[Name=$_ifname].Upstream
[ "$upstream" = "false" ] && gmacmode=0
gmacctl set --mode "$gmacmode"
}
eth_set_linkup()
{
:
}
ethsw_set_ingress_shaper()
{
local port="$1" limit="$2" burst="$3"
echo "### Executing <ethswctl -c rxratectl -p $port -x $limit -y $burst> ###" > /dev/console
ethswctl -c rxratectrl -p "$port" -x "$limit" -y "$burst"
}
ethsw_power() {
local lan_if="$1" power_switch="$2"
eth_set_power $lan_if $power_switch
}
ethsw_set_jumbo_enable() {
ethswctl -c jumbo -p 9 -v 1
}
wifissid_is_virtual() {
local obj_ssid="$1" actual_obj
[ -z "$obj_ssid" ] && return 1
cmclient -v actual_obj GETO Device.WiFi.SSID."[Name=%(%($obj_ssid.LowerLayers).Name)]"
[ "$actual_obj" != "$obj_ssid" ] && echo "true" || echo "false"
}
wifiradio_isup() {
local is_up=`wlctl -i $1 isup`
[ "$is_up" = "1" ] && return 0 || return 1
}
wifiradio_get_mcsset() {
local parsed_mcsset i cur_mcsset=`wlctl -i $1 cur_mcsset`
cur_mcsset=${cur_mcsset##*'['}
cur_mcsset=${cur_mcsset%%]}
for i in $cur_mcsset
do
parsed_mcsset=${parsed_mcsset}$i,
done
parsed_mcsset=${parsed_mcsset%%,}
echo "$parsed_mcsset"
}
wifiradio_get_vht_mcsset() {
local parsed_mcsset mcs_index dom_mcsset cur_mcsset=`wlctl -i $1 rateset`
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS='
'
for parsed_mcsset in $cur_mcsset; do
case "$parsed_mcsset" in
"VHT"* )
parsed_mcsset=${parsed_mcsset#"VHT SET : "}
IFS=' '
for mcs_index in $parsed_mcsset; do
mcs_index=${mcs_index%x*}
dom_mcsset="$dom_mcsset,$mcs_index"
done
break
;;
esac
done
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
dom_mcsset=${dom_mcsset#,}
echo "$dom_mcsset"
}
wifiradio_get_num_spatial_streams () {
local num_streams=`wlctl -i $1 txstreams`
echo "$num_streams"
}
wifiradio_get_current_channel() {
local read_channel=`wlctl -i "$1" chanspec`
read_channel=${read_channel%%[\ lu/]*}
echo "$read_channel"
}
wifiradio_get_current_channel_brcm() {
[ "$2" != "_ret" ] && local _ret
_ret=`wlctl -i $1 chanspec`
_ret="${_ret%% *}"
eval $2='"$_ret"'
}
wifiradio_get_channel_list() {
local _max=$2 _band _set_band list l
cmclient -v _band GETV "Device.WiFi.Radio.[Name=${1%.*}].SupportedFrequencyBands"
case "$_band" in
2.4GHz)	_set_band="b" 		;;
5GHz)	_set_band="a" 		;;
*)	_set_band="auto" 	;;
esac
wlctl -i $1 band $_set_band
list=`wlctl -i $1 channels`
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=' '
set -- $list
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
chan_list=''
for l; do
[ ${#_max} -gt 0 ] && [ $l -ge $_max ] && continue
[ -z "$chan_list" ] && chan_list="$l" || chan_list="$chan_list,$l"
done
echo "$chan_list"
}
get_ch40MHz() {
[ "$4" != "_ret" ] && local _ret
case "$2" in
"40MHz")
_ret="$(( $3 - 2 )) $(( $3 + 2 ))"
;;
"20MHz")
_ret="$3"
;;
*) ;;
esac
eval $4='"$_ret"'
}
wifiradio_get_broadcomch_list(){
local list=`wifiradio_get_channel_list $1` ownchannel=$2 j channelpurge filter
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=","
channelpurge="${ownchannel%%[u|l]}"
for j in $list; do
case "$channelpurge" in
"$j")
filter="${ownchannel%% *}"
filter="${filter##*[0-9]}"
case "$filter" in
"l")
chlist="$j $(($j + 4))"
;;
"u")
chlist="$j $(($j - 4))"
;;
*)
chlist="$j"
;;
esac
break
;;
*) ;;
esac
done
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
eval $3='"$chlist"'
}
wifiradio_get_channels_in_use() {
local pid1=0 pid2=1 chans_in_use="" v01=0 v02=0 v03=0 v04=0 v05=0 v06=0 v07=0 v08=0 v09=0 v10=0 v11=0 v12=0 sum=0 channel="" is_autoch=""
read -r pid1 < "/var/run/hostapd_${1}.pid" || pid1="NOPROCESS"
pid2=`pgrep -f hostapd.*${1}`
cmclient -v is_autoch GETV "$obj.AutoChannelEnable"
if [ "$is_autoch" = "true" -a $pid1 -eq $pid2 ]; then
while read -r channel v01 v02 v03 v04 v05 v06 v07 v08 v09 v10 v11 v12; do
sum=$((v01+v02+v03+v04+v05+v06+v07+v08+v09+v10+v11+v12))
[ $sum -ne 0 ] && chans_in_use=${chans_in_use:+$chans_in_use,}$channel
done<<-EOF
$(acs_cli -i ${1} dump bss)
EOF
else
local ownchannel=""
wifiradio_get_current_channel_brcm "$1" ownchannel
wifiradio_get_broadcomch_list $1 $ownchannel chans_in_use
fi
echo "$chans_in_use"
}
wifiradio_get_ext_channel()
{
local read_chan=`wlctl -i $1 chanspec` ext_chan
ext_chan="${read_chan%% *}"
ext_chan="${ext_chan##*[0-9]}"
case "$ext_chan" in
"l") echo "AboveControlChannel"	;;
"u") echo "BelowControlChannel" ;;
*)   echo "None" ;;
esac
}
wifiradio_get_hw_support()
{
case "$1" in
atf|mfp) return 0 ;;
*) return 1 ;;
esac
}
wifiradio_get_counters()
{
local counter="0" txerror txnobuf rxnobuf rxfrmtoolong rxfrmtooshrt rxinvmachdr rxbadfcs
wlctl -i ${1:=0} counters > /tmp/counters
while read -r line; do
case "$line" in
*"txerror"*) txerror=${line#*txerror }; txerror=${txerror%% *} ;;
*"txnobuf"*) txnobuf=${line#*txnobuf }; txnobuf=${txnobuf%% *} ;;
*"rxnobuf"*) rxnobuf=${line#*rxnobuf }; rxnobuf=${rxnobuf%% *} ;;
*"rxfrmtoolong"*)
rxfrmtoolong=${line#*rxfrmtoolong }; rxfrmtoolong=${rxfrmtoolong%% *}
rxfrmtooshrt=${line#*rxfrmtooshrt }; rxfrmtooshrt=${rxfrmtooshrt%% *}
rxinvmachdr=${line#*rxinvmachdr }; rxinvmachdr=${rxinvmachdr%% *}
rxbadfcs=${line#*rxbadfcs }; rxbadfcs=${rxbadfcs%% *}
break ;;
esac
done < /tmp/counters
case "$2" in
ErrorsSent)
read counter < /sys/class/net/${1:=0}/statistics/tx_errors
counter=$((counter + txerror))
;;
DiscardPacketsSent)
read counter < /sys/class/net/${1:=0}/statistics/tx_dropped
counter=$((counter + txnobuf))
;;
DiscardPacketsReceived)
read counter < /sys/class/net/${1:=0}/statistics/rx_dropped
counter=$((counter + rxnobuf))
;;
ErrorsReceived)
read counter < /sys/class/net/${1:=0}/statistics/rx_errors
counter=$((counter + rxfrmtoolong + rxfrmtooshrt + rxinvmachdr + rxbadfcs))
;;
esac
echo "$counter"
}
wifiradio_set_txpower()
{
local _arg
case "$2" in
"100" | "-1" ) _arg="100" ;;
"75") _arg="92" ;;
"50") _arg="80" ;;
"25") _arg="60" ;;
*) _arg="30" ;;
esac
wlctl -i "$1" pwr_percent $_arg
}
wifiradio_set_rate()
{
if [ "$2" = "-1" ]; then
wlctl -i $1 rate auto
else
wlctl -i $1 nrate -m "$2"
[ "$3" = "true" ] && wlctl -i $1 5g_rate -v $2
fi
}
wifiradio_bf_cal()
{
cmclient -v rpcal2g GETV X_ADB_FactoryData.Rpcal2g
[ -n "$rpcal2g" ] && wlctl -i $1 rpcalvars rpcal2g=$rpcal2g
cmclient -v rpcal5gb0 GETV X_ADB_FactoryData.Rpcal5gb0
[ -n "$rpcal5gb0" ] && wlctl -i $1 rpcalvars rpcal5gb0=$rpcal5gb0
cmclient -v rpcal5gb1 GETV X_ADB_FactoryData.Rpcal5gb1
[ -n "$rpcal5gb1" ] && wlctl -i $1 rpcalvars rpcal5gb1=$rpcal5gb1
cmclient -v rpcal5gb2 GETV X_ADB_FactoryData.Rpcal5gb2
[ -n "$rpcal5gb2" ] && wlctl -i $1 rpcalvars rpcal5gb2=$rpcal5gb2
cmclient -v rpcal5gb3 GETV X_ADB_FactoryData.Rpcal5gb3
[ -n "$rpcal5gb3" ] && wlctl -i $1 rpcalvars rpcal5gb3=$rpcal5gb3
cmclient -v rpcal5gb01core3 GETV X_ADB_FactoryData.Rpcal5gb01core3
if [ -n "$rpcal5gb01core3" ]; then
wlctl -i $1 rpcalvars rpcal5gb1core3=$(($((rpcal5gb01core3 & 0xff00)) >> 8))
wlctl -i $1 rpcalvars rpcal5gb0core3=$((rpcal5gb01core3 & 0x00ff))
fi
cmclient -v rpcal5gb23core3 GETV X_ADB_FactoryData.Rpcal5gb23core3
if [ -n "$rpcal5gb23core3" ]; then
wlctl -i $1 rpcalvars rpcal5gb3core3=$(($((rpcal5gb23core3 & 0xff00)) >> 8))
wlctl -i $1 rpcalvars rpcal5gb2core3=$((rpcal5gb23core3 & 0x00ff))
fi
}
clean_interface_stack()
{
local llayer="$1" user="$2" eth_link ip_obj dhcp_pool
cmclient -v eth_link GETO "Device.Ethernet.Link.[LowerLayers>$llayer]"
for eth_link in $eth_link; do
cmclient -v $ip_obj GETO "Device.IP.Interface.[LowerLayers=$eth_link]"
for ip_obj in $ip_obj; do
cmclient -v dhcp_pool GETO "Device.DHCPv4.Server.Pool.[Interface=$ip_obj]"
for dhcp_pool in $dhcp_pool; do
cmclient -u "$user" DEL "$dhcp_pool"
done
cmclient DEL "$ip_obj"
done
cmclient -u "$user" DEL "$eth_link"
done
}
wifiradio_hostapd_start()
{
local ifName="" macAclFile="" acceptFile="" denyFile="" macMode="" maclist_val="" \
radioName="" radioList="" radioFreq="" radioRegDom="" tmp=0 n
while [ ! -e /tmp/cm_ready -a $((tmp=$tmp+1)) -le 60 ]; do
if [ $tmp -ge 60 ]; then
echo "cm not ready, skipping wifi radio init" >/dev/console
rm -f /tmp/starting_hostapd
return
fi
sleep 1
done
if [ ! -d /sys/class/net/wl0 ]; then
if [ -f /etc/ah/TR098_AlignAll.sh ]; then
local cm98_ready
cmclient -v cm98_ready GETV Device.DeviceInfo.X_ADB_TR098Ready
while [ "$cm98_ready" = false ]; do
sleep 1
cmclient -v cm98_ready GETV Device.DeviceInfo.X_ADB_TR098Ready
done
fi
cmclient -v tmp GETO Device.WiFi.Radio.
if [ -z "$tmp" ]; then
rm -f /tmp/starting_hostapd
return
fi
cmclient -v bridge GETO "Device.Bridging.Bridge"
for bridge in $bridge; do
cmclient -u "NoWiFi" DEL "$bridge.Port.[LowerLayers>Device.WiFi.SSID]"
cmclient -v is_alive GETO "$bridge.Port.[ManagementPort=false]"
if [ -z "$is_alive" ]; then
clean_interface_stack "$bridge" "NoWiFi"
cmclient DEL "$bridge"
fi
done
clean_interface_stack "Device.WiFi.SSID" "NoWiFi"
cmclient DEL "Device.WiFi.Radio."
cmclient -u "NoWiFi" DEL "Device.WiFi.SSID."
cmclient -u "NoWiFi" DEL "Device.WiFi.AccessPoint."
cmclient SAVE
rm -f /tmp/starting_hostapd
return
fi
cmclient -v radioList GETO Device.WiFi.Radio
for n in $radioList
do
cmclient -v radioName GETV $n.Name
cmclient -v radioFreq GETV $n.OperatingFrequencyBand
cmclient -v radioRegDom GETV $n.RegulatoryDomain
cmclient -v e0Rev938RegDom GETV $n.X_ADB_UseE0Rev938RegulatoryDomain
cmclient -v iov GETV $n.X_ADB_InterferenceOverride
wlctl -i $radioName radio off
wifiradio_set_fcache "$radioName" "1"
wifiradio_set_frameburst "$radioName" "1"
wifiradio_set_country "$radioName" "$radioRegDom" "$e0Rev938RegDom"
wifiradio_set_pspretend "$radioName"
wifiradio_set_chanim_mode "$radioName"
wifiradio_set_interference_override "$radioName" "$iov"
wifiradio_fix_chanim "$radioName"
done
cmclient -v n GETO Device.WiFi.SSID
for n in $n; do
macAclFile=""
cmclient -v ifName GETV "$n.Name"
acceptFile="/tmp/"$ifName".accept"
denyFile="/tmp/"$ifName".deny"
touch $acceptFile
touch $denyFile
if [ -n "$ifName" ]; then
cmclient -v macMode GETV "$n.X_ADB_MacMode"
case $macMode in
"Accept"*)
macAclFile=$acceptFile
;;
"Deny"*)
macAclFile=$denyFile
;;
*)
;;
esac
if [ -n "$macAclFile" ]; then
cmclient -v maclist_val GETV "$n.X_ADB_MacList"
TMP_FILE=`mktemp -p /tmp`
oldIFS=$IFS
IFS=","
for macAddr in $maclist_val; do
echo $macAddr >> $TMP_FILE
done
IFS=$oldIFS
mv $TMP_FILE $macAclFile
fi
fi
cmclient -v wifi_bssid GETV "$n.MACAddress"
case "$ifName" in
*.* )
base="${ifName%%.*}"
id="${ifName##*.}"
wlctl -i $base ssid -C $id temp-$ifName
ifconfig $ifName hw ether "$wifi_bssid"
ifconfig $ifName txqueuelen 500
;;
* )
ifconfig $ifName hw ether "$wifi_bssid"
ifconfig $ifName txqueuelen 500
;;
esac
done
rm -f /tmp/starting_hostapd
}
wifiradio_phy_start()
{
local radioObj="$1"
cmclient -u boot SET "$radioObj.Enable" "true" > /dev/null
}
WIFIRADIO_COUNTRY_USE_HOSTAPD="false"
wifiradio_set_country()
{
local _ctry=""
if [ -n "$3" -a "$3" = "true" ]; then
_ctry="E0/938"
else
case "$2" in
EU*|IL*)
_ctry="${2%% *}/13"
;;
IT*)
_ctry="${2%% *}/9"
;;
*)
_ctry="${2%% *}/0"
;;
esac
fi
[ -n "$_ctry" ] && wlctl -i "$1" country "$_ctry" >/dev/null
}
wifiradio_set_pspretend()
{
wlctl -i "$1" pspretend_threshold 5
wlctl -i "$1" pspretend_retry_limit 5
}
wifiradio_set_chanim_mode()
{
wlctl -i "$1" chanim_mode 2
}
wifiradio_set_dhd_radarthrs()
{
local _f _l _r=0
dhdctl -i "$1" devcap || return 0
for _f in /tmp/nvram.txt /etc/wlan/nvram.txt "" ; do
[ -f "$_f" ] && break
done
if [ ${#_f} -gt 0 ]; then
while IFS='' read -r _l ; do
case $_l in
"# @RADARTHRS:"*) _l=${_l##*@RADARTHRS:} ; _r=1 ; break ;;
esac
done < $_f
fi
[ $_r -eq 1 -a ${#_l} -gt 0 ] && wlctl -i "$1" radarthrs $_l
:
}
wifiradio_fix_ampdu()
{
wlctl -i "$1" ampdu_mpdu 32
}
wifiradio_set_interference_override()
{
wlctl -i "$1" interference_override "$2"
:
}
wifiradio_disable_nar()
{
wlctl -i "$1" nar 0
:
}
wifiradio_fix_plcphdr()
{
wlctl -i "$1" plcphdr long
:
}
wifiradio_fix_chanim()
{
wlctl -i "$1" noise_metric 1
wlctl -i "$1" mpc 0
:
}
wifiradio_set_fcache()
{
echo "### wlctl -i $1 fcache $2"
wlctl -i $1 fcache $2
}
wifiradio_set_frameburst()
{
echo "### wlctl -i $1 frameburst $2"
wlctl -i $1 frameburst $2
}
wifiradio_5g_settings()
{
echo "tpc_mode=0"
echo "radar=1"
}
wifiradio_set_retry()
{
local type="$1" value="$2" param=
if [ "$type" = "short" ]; then
param="srl"
elif [ "$type" = "long" ]; then
param="lrl"
else
return 1
fi
echo "$param=$value"
}
wifiradio_set_wmm()
{
local cmd="$1" value=
[ "$cmd" = "enable" ] && value="1" || value="0"
echo "wmm_enabled=$value"
}
wifiradio_set_wmm_bss()
{
local cmd="$1" value=
[ "$cmd" = "enable" ] && value="0" || value="1"
echo "wmm_bss_disable=$value"
}
wifiradio_set_wmm_apsd()
{
local cmd="$1" value=
[ "$cmd" = "enable" ] && echo "wmm_uapsd_enabled=1"
}
wifiradio_set_wmm_noack()
{
local cmd="$1" value=
[ "$cmd" = "enable" ] && echo "wmm_noack_enabled=1"
}
wifiradio_setup_tpid()
{
:
}
wifiradio_set_radio()
{
local ifname="$1" cmd="$2" value=""
[ "$cmd" = "enable" ] && value="ON" || value="OFF"
hostapd_cli -p /var/run/hostapd-${ifname} radio $ifname $value
}
wifiradio_get_radio()
{
local value=`hostapd_cli -p /var/run/hostapd-${1} radio $1`
[ "$value" = "OFF" ] && echo "Disabled"|| echo "Enabled"
}
wifiradio_get_max_bitrate()
{
local cx_bmap=$(wlctl -i $1 hw_txchain) cx_num=0 bands=$(wlctl -i $1 bands) band bw_cap maxbw
[ ${#cx_bmap} -eq 0 ] && echo 0 && return
while [ $cx_bmap -gt 0 ]; do
cx_num=$((cx_num+1))
cx_bmap=$((cx_bmap >> 1))
done
case "$bands" in
*a*)	band=5g;;
*)	band=2g;;
esac
bw_cap=$(wlctl -i $1 bw_cap $band)
if [ "$bw_cap" != 0x7 ]; then
maxbw=$((cx_num*150))
else
maxbw=$((cx_num*433))
[ $((cx_num % 3)) -ne 1 ] && maxbw=$((maxbw+1))
fi
echo $maxbw
}
wifiradio_set_stbc()
{
local radioName="$1" rx_enable="$2" tx_enable="$3"
[ "$rx_enable" = "true" ] && value="1" || value="0"
wlctl -i $radioName stbc_rx $value
[ "$tx_enable" = "true" ] && value="-1" || value="0"
wlctl -i $radioName stbc_tx $value
}
wifiradio_reset_stats()
{
wlctl -i $1 reset_d11cnts
}
wifiradio_adjust_hostapd_conf()
{
:
}
wifiradio_bss_down()
{
wlctl -i $1 bss down
}
wifiradio_bss_up()
{
wlctl -i $1 bss up
}
help_get_wifi_chanim_stats()
{
local rn=$1 ch txop knoise found=0
[ ${#rn} -eq 0 ] && return 1
[ ${#2} -eq 0 -o ${#3} -eq 0 ] && return 1
while IFS='	' read -r ch _ _ _ _ _ _ txop _ _ _ _ knoise _ ; do
case $ch in
0x*) found=1 ; break ;;
esac
done <<-EOF
`wlctl -i $rn chanim_stats`
EOF
if [ $found -eq 1 ] ; then
eval $2='$txop'
eval $3='$knoise'
else
eval $2=99
eval $3=-90
fi
}
help_get_wifi_throughput()
{
local _txop=${1:-0} _knoise=${2:--90} _txrate=${3:-0} _mt
[ $_txrate -lt 1000 -o $_txrate -gt 8000000 ]  && _txrate=110000
if [ $_txop -gt 6 ]; then
_txop=$((_txop - 6))
else
_txop=0;
fi
if [ $_txop -lt 87 ]; then
_txop=87
fi
_mt=$(((_txrate * _txop * (-50 - (_knoise * 10))) / 100000))
eval $4='$_mt'
}
wifiradio_get_assoc_stats()
{
local line nmode=0 rateset curband best=-200
set -f
wifi_assoc_tx_pkts="null"
while IFS="	" read -r line; do
case "$line" in
*"in network"*)
assoc_time="${line##*k }"
wifi_assoc_time="${assoc_time%% seconds*}"
;;
*"rate of last tx pkt"*)
tx_rate="${line##*: }"
wifi_assoc_downlink_rate="${tx_rate%% kbps*}"
wifi_assoc_downlink_rate2="${tx_rate##$wifi_assoc_downlink_rate kbps - }"
wifi_assoc_downlink_rate2="${wifi_assoc_downlink_rate2%% kbps*}"
[ "$wifi_assoc_downlink_rate2" -gt "$wifi_assoc_downlink_rate" ] && wifi_assoc_downlink_rate=$wifi_assoc_downlink_rate2
;;
*"rate of last rx pkt"*)
rx_rate="${line##*: }"
wifi_assoc_uplink_rate="${rx_rate%% kbps*}"
;;
*"flags 0x"*)
case "$line" in
*"VHT_CAP"*) nmode=2 ;;
*"N_CAP"*) nmode=1 ;;
*"No-ERP"*) assocmode=b ;;
esac
;;
*"rateset ["*)
rateset="${line##*rateset }"
wifi_assoc_rateset=$rateset
;;
*"tx total pkts"*)
if [ "$wifi_assoc_tx_pkts" = "null" ]; then
wifi_assoc_tx_pkts="${line##*: }"
fi
;;
*"tx total bytes"*)
wifi_assoc_tx_bytes="${line##*: }"
;;
*"tx failures"*)
wifi_assoc_tx_failures="${line##*: }"
;;
*"rx ucast pkts"*)
wifi_assoc_rx_pkts_u="${line##*: }"
;;
*"rx mcast/bcast pkts"*)
wifi_assoc_rx_pkts_mb="${line##*: }"
;;
*"rx mcast/bcast bytes"*)
wifi_assoc_rx_bytes_mb="${line##*: }"
;;
*"rx data bytes"*)
wifi_assoc_rx_bytes="${line##*: }"
;;
*"rx data pkts"*)
wifi_assoc_rx_pkts="${line##*: }"
;;
*"per antenna average rssi of rx data frames"*)
wifi_assoc_rx_rssi="${line##*: }"
for wifi_assoc_rx_rssi in $wifi_assoc_rx_rssi ; do
[ $wifi_assoc_rx_rssi -ne 0 -a $best -lt $wifi_assoc_rx_rssi ] && best=$wifi_assoc_rx_rssi
done
wifi_assoc_rx_rssi=$best
;;
esac
done <<-EOF
`wlctl -i $2 sta_info $1`
EOF
set +f
: ${wifi_assoc_rx_rssi:=`wlctl -i $2 rssi $1`}
case $nmode in
2) wifi_assoc_mode="ac" ;;
1) wifi_assoc_mode="n" ;;
*)
curband=$(wlctl -i $2 band)
if [ "a" = "$curband" ]; then
wifi_assoc_mode="a"
else
if [ "$assocmode" = "b" ]; then
wifi_assoc_mode="b"
else
wifi_assoc_mode="g"
fi
fi
;;
esac
cmclient -v _radio GETV "%(Device.WiFi.SSID.[Name=$2].LowerLayers).Name"
help_get_wifi_chanim_stats $_radio sta_txop sta_knoise
help_get_wifi_throughput $sta_txop $sta_knoise $wifi_assoc_downlink_rate wifi_assoc_throughput
}
wifiradio_off() {
wlctl -i "$1" radio off
}
wifiradio_on() {
wlctl -i "$1" radio on
}
wifiradio_set_80211h_spectrum_management_mode() {
wlctl -i "$1" spect "$2"
}
wifiradio_passive_scan() {
wlctl -i "$1" scan -t passive -n -1 -p "$2" > /dev/null
}
wifiradio_parse_scanresults() {
local counter= out=
while sleep 1; do
out=$(wlctl -i "$2" scanresults -e -s 2> /dev/null) && break
counter=$((counter + 1))
[ $counter -gt 30 ] && return 1
done
eval $1='$out'
return 0
}
wifiradio_get_scb_associated() {
wlctl -i "$1" scb_assoced
}
wifiradio_set_aspm() {
wlctl -i "$1" aspm "$2"
}
wifiradio_remove_wds_members() {
wlctl -i $1 wds none
}
wifiradio_add_wds_members() {
wlctl -i $1 wds $2
}
wifiradio_get_number_of_wds_members() {
wlctl -i $1 wds | wc -l
}
wifiradio_led_behaviour() {
wlctl ledbh "$1" "$2"
}
wifiradio_get_ampdu_stats()
{
local line
set -f
while IFS=" " read -r line; do
case "$line" in
*"tot_mpdus"*)
wifi_ampdu_mpduperampdu="${line##*mpduperampdu }"
;;
*"agg stop reason"*)
wifi_ampdu_fempty_percent="${line##*fempty*(}"
wifi_ampdu_fempty_percent="${wifi_ampdu_fempty_percent%%%)*}"
;;
*"Frameburst histogram"*)
wifi_ampdu_frameburst_avg="${line##*avg }"
;;
esac
done <<-EOF
`wlctl -i $1 dump ampdu`
EOF
set +f
}
hwswitch_set_8021p()
{
if [ $2 != "-1" ]; then
echo "### swconf 8021p set $1 $2"
swconf 8021p set $1 $2
fi
}
hwswitch_set_stp()
{
echo "### swconf stp set $1 $2"
swconf stp set $1 $2
}
xdsl_get_state() {
xdslctl info --state > /dev/null
}
xdsl_get_band_plan_params() {
xdslctl info --pbParams
}
xdsl_get_stats() {
xdslctl info --sho1
xdslctl info --stats
}
xdsl_get_vendor() {
xdslctl info --vendor
}
xdsl_get_snr() {
xdslctl info --SNR
}
xdsl_get_version() {
local phy_line="$1"
xdslctl$phy_line info --version 2>&1
}
xdsl_get_info() {
local phy_line="$1"
xdslctl$phy_line info --show
}
xdsl_get_vdslUsStartTime() {
local phy_line="$1"
xdslctl$phy_line info --vdslUsStartTone
}
xdsl_initialize() {
local phy_line="$1"
xdslctl$phy_line start
}
xdsl_uninitialize() {
local phy_line="$1"
xdslctl$phy_line stop
}
xdsl_connection_up() {
local phy_line="$1"
xdslctl$phy_line connection --up
}
xdsl_connection_down() {
local phy_line="$1"
xdslctl$phy_line connection --down
}
xdsl_enable_bonding_mediasearch() {
local phy_line="$1"
xdslctl$phy_line diag --mediaSearchCfg 0x4
}
xdsl_disable_bonding_mediasearch() {
local phy_line="$1"
xdslctl$phy_line diag --mediaSearchCfg 0xF
}
xdsl_set_hexVendorId() {
local phy_line="$1" VENDORID="$2"
xdslctl$phy_line setoemparams --hex --vendorId "$VENDORID"
}
xdsl_set_versionNumber() {
local phy_line="$1" VERNUMBER="$2"
xdslctl$phy_line setoemparams --verNumber "$VERNUMBER"
}
xdsl_set_serialNumber() {
local phy_line="$1" SERNUMBER="$2"
xdslctl$phy_line setoemparams --serNumber "$SERNUMBER"
}
xdsl_set_g994VendorId() {
local phy_line="$1" G994VENDORID="$2"
xdslctl$phy_line setoemparams --hex --g994VendorId "$G994VENDORID"
}
xdsl_initial_configuration() {
local phy_line="$1" cfg="$2"
xdslctl$phy_line configure $cfg
}
xdsl_set_configuration() {
local phy_line="$1" cfg="$2"
xdslctl$phy_line configure1 $cfg
}
xdsl_set_link()
{
local ifname="$1"
local cmd="$2"
case "$cmd" in
up)
ip link set "$ifname" up
;;
down)
ip link set "$ifname" down
;;
esac
}
hpna_cmd()
{
local ifname="$1";
local cmd="$2";
}
service_check_dad()
{
:
}
xtm_connection_state() {
local addr="$1" state="$2"
xtmctl operate conn --state "$addr" "$state"
}
xtm_add_connection() {
local addr="$1" aal="$2" linktype="$3" encap="$4" tdtei="$5" aalc encapc
case "$aal" in
"AAL1" | "AAL2" | "AAL3" | "AAL4" )
aalc="unsupported"
;;
"AAL5" )
aalc="aal5"
;;
*)
aalc=
;;
esac
if [ "$encap" = "LLC" ]; then
case "$linktype" in
"EoA" )	encapc="llcsnap_eth"
;;
"IPoA" ) encapc="llcsnap_rtip"
;;
"PPPoA" ) encapc="llcencaps_ppp"
;;
"CIP" ) encapc=""
;;
*)
;;
esac
elif [ "$encap" = "VCMUX" ]; then
case "$linktype" in
"EoA" ) encapc="vcmux_eth"
;;
"IPoA" ) encapc="vcmux_ipoa"
;;
"PPPoA" ) encapc="vcmux_pppoa"
;;
"CIP" )	encapc=""
;;
*)
;;
esac
fi
if [ -z $aalc ]
then
xtmctl operate conn --add "$addr"
else
xtmctl operate conn --add "$addr" "$aalc" "$encapc" 0 1 "$xtm_tdte_index"
fi
}
xtm_delete_connection() {
local addr="$1"
xtmctl operate conn --delete "$addr"
}
xtm_delete_queue() {
local addr="$1" qid="$2"
xtmctl operate conn --deleteq "$addr" "$qid"
}
xtm_add_queue() {
local addr="$1" size="$2" subPrio="$3" walg="$4" wval="$5" mbr="$6" sr="$7" sbs="$8"
xtmctl operate conn --addq "$addr" "$size" "$subPrio" "$walg" "$wval" "$mbr" "$sr" "$sbs"
}
xtm_show_traffic_desc_table() {
xtmctl operate tdte --show
}
xtm_add_tdte() {
echo "### $AH_NAME: Executing <xtmctl operate tdte --add $@> ###" > /dev/console
xtmctl operate tdte --add "$@"
}
xtm_delete_tdte() {
local idx="$1"
echo "### $AH_NAME: Executing <xtmctl operate tdte --delete $idx ###" > /dev/console
xtmctl operate tdte --delete "$idx"
}
xtm_create_network_device() {
local addr="$1" name="$2"
echo "### $AH_NAME: Executing <xtmctl operate conn --createnetdev "$addr" "$name"> ###"
xtmctl operate conn --createnetdev "$addr" "$name" 2>&1
}
xtm_delete_network_device() {
local addr="$1"
echo "### $AH_NAME: Executing <xtmctl operate conn --deletenetdev "$addr" > ###"
xtmctl operate conn --deletenetdev "$addr"
}
xtm_send_oam() {
local addr="$1" otype="$2" timeout="$3"
xtmctl operate conn --sendoam "$addr" "$otype"
}
xtm_mirror_enable() {
local indev="$1" outdev="$2" mtype="$3"
case "$mtype" in
Inbound)
xtmctl mirror --enable "$indev" "$outdev" "in"
;;
Outbound)
xtmctl mirror --enable "$indev" "$outdev" "out"
;;
Bidirectional)
xtmctl mirror --enable "$indev" "$outdev" "in"
xtmctl mirror --enable "$indev" "$outdev" "out"
;;
esac
}
xtm_mirror_disable() {
local indev="$1" outdev="$2"
xtmctl mirror --disable "$indev" "$outdev" "in" 2>/dev/null
xtmctl mirror --disable "$indev" "$outdev" "out" 2>/dev/null
}
xtm_bonding_status() {
xtmctl bonding --status
}
xtm_start_interface() {
pc="$1"
xtmctl start --intf "$pc"
}
xtm_interface_state() {
local portid="$1" state="$2"
xtmctl operate intf --state "$portid" "$state"
}
