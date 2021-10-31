#!/bin/sh
help_get_macs() {
[ $1 != a ] && local a
[ $1 != ret ] && local ret
for a in /sys/class/net/*/address; do
read a < $a
ret="$ret $a"
done
eval $1='$ret'
}
help_trim_imm() {
local var
for var; do
eval local tmp=\"\${$var#\"\${$var%%[! ]*}\"}\"
eval $var=\"'${tmp%"${tmp##*[! ]}"}'\"
done
}
help_date_to_seconds() {
local var_name="$1"
shift
local i=$#
while [ $i -gt 1 ]; do
eval local _\$$i=\$$((i-1))
i=$((i-2))
done
eval "$var_name=$((${_days:-0}*86400+${_hours:-0}*3600+${_min:-0}*60+${_sec:-0}))"
}
help_div10() {
local ret="$1"
local var="$2"
case "$var" in
0.[0-9])
var="${2%.*}${2#*.}"
var="${var#0}"
;;
[0-9].[0-9]|[0-9][0-9].[0-9])
var="${2%.*}${2#*.}"
;;
-0.[0-9])
var="${2%.*}${2#*.}"
var="-${var#-0}"
;;
-[0-9].[0-9]|-[0-9][0-9].[0-9])
var="${2%.*}${2#*.}"
;;
*)
var="$2"
;;
esac
eval $ret='"$var"'
}
help_div10_imm() {
local var
for var; do
eval help_div10 \"\$var\" \"\$$var\"
done
}
help_get_dsl_attn() {
local name u0 u1 u2 u3 u4 d1 d2 d3
local d=0 u=0 nd=0 nu=0
set -f
while IFS="	:" read -r name u0 u1 u2 u3 u4 d1 d2 d3; do
help_trim_imm name u0 u1 u2 u3 u4 d1 d2 d3
help_div10_imm u0 u1 u2 u3 u4 d1 d2 d3
case "$name" in
"Line Attenuation(dB)")
if [ "$u0" != "N/A" ]; then
nu=$((nu + 1))
u=$((u + u0))
fi
if [ "$u1" != "N/A" ]; then
nu=$((nu + 1))
u=$((u + u1))
fi
if [ "$u2" != "N/A" ]; then
nu=$((nu + 1))
u=$((u + u2))
fi
if [ "$u3" != "N/A" ]; then
nu=$((nu + 1))
u=$((u + u3))
fi
adsl_up_attn=$((u / nu))
if [ "$d1" != "N/A" ]; then
nd=$((nd + 1))
d=$((d + d1))
fi
if [ "$d2" != "N/A" ]; then
nd=$((nd + 1))
d=$((d + d2))
fi
if [ "$d3" != "N/A" ]; then
nd=$((nd + 1))
d=$((d + d3))
fi
adsl_down_attn=$((d / nd))
case "$1" in
"G.fast"*)
adsl_up_attn=$adsl_down_attn;
;;
esac
break
;;
esac
done <<-EOF
`xdsl_get_band_plan_params`
EOF
}
help_get_dsl_stats() {
local name a b section
adsl_retrain_number=""
set -f
while IFS="	:" read -r name a b; do
a=${a# }
b=${b# }
case "$name" in
"Status")
adsl_status=$a
;;
"Link Power State")
adsl_power_state=$a
;;
"Mode")
[ "${0##*/}" = "DslLine.sh" ] || continue
adsl_modulation_type=$a
;;
"Max")
set -- $a
if [ "$1 $2" = "Upstream rate" ]; then
adsl_max_down_rate=$9
adsl_max_up_rate=$4
fi
;;
"Bearer"|"Channel")
set -- $a
if [ "$1 $2 $3" = "0, Upstream rate" ] || [ "$1 $2 $3" = "FAST, Upstream rate" ] || [ "$1 $2 $3" = "INTR, Upstream rate" ]; then
adsl_bearer_down_rate=$10
adsl_bearer_up_rate=$5
fi
;;
"VDSL2 Profile")
[ "${0##*/}" = "DslLine.sh" ] || continue
adsl_profile=${a#Profile }
;;
"SNR (dB)")
[ "${0##*/}" = "DslLine.sh" ] || continue
help_div10 adsl_down_snr "$a"
help_div10 adsl_up_snr "$b"
;;
"Attn(dB)")
[ "${0##*/}" = "DslLine.sh" ] || continue
case "$adsl_modulation_type" in
"VDSL"*|"G.fast"*)
help_get_dsl_attn $adsl_modulation_type
;;
*)
help_div10 adsl_down_attn "$a"
help_div10 adsl_up_attn "$b"
;;
esac
;;
"Pwr(dBm)")
[ "${0##*/}" = "DslLine.sh" ] || continue
help_div10 adsl_down_pwr "$a"
help_div10 adsl_up_pwr "$b"
;;
"Retr")
[ "${0##*/}" = "DslLine.sh" -a -z "$adsl_retrain_number" ] || continue
adsl_retrain_number="$a"
;;
"B")
adsl_down_b=$a
adsl_up_b=$b
;;
"R")
adsl_down_r=$a
adsl_up_r=$b
;;
"L")
adsl_down_l=$a
adsl_up_l=$b
;;
"D")
adsl_down_d=$a
adsl_up_d=$b
;;
"N")
adsl_down_n=$a
adsl_up_n=$b
;;
"I")
adsl_down_i=$a
adsl_up_i=$b
;;
"INP")
adsl_down_inp=$a
adsl_up_inp=$b
;;
"delay")
adsl_down_delay=$a
adsl_up_delay=$b
;;
"SF")
adsl_down_sf=$a
adsl_up_sf=$b
;;
"OHF")
vdsl_down_sf=$a
vdsl_up_sf=$b
;;
"SFErr")
adsl_down_sferr=$a
adsl_up_sferr=$b
;;
"OHFErr")
vdsl_down_sferr=$a
vdsl_up_sferr=$b
;;
"HEC")
adsl_down_hec=$a
adsl_up_hec=$b
;;
"Total time = "*)
section=total
help_date_to_seconds adsl_${section}start ${name#Total time = }
;;
"Latest 15 minutes time = "*)
section=quarterhour
help_date_to_seconds adsl_${section}start ${name#Latest 15 minutes time = }
;;
"Latest 1 day time = "*)
section=currentday
help_date_to_seconds adsl_${section}start ${name#Latest 1 day time = }
;;
"Since Link time = "*)
section=showtime
help_date_to_seconds adsl_${section}start ${name#Since Link time = }
;;
"Since Previous Link time = "*)
section=sincelastshowtime
help_date_to_seconds adsl_${section}start ${name#Since Previous Link time = }
;;
*" time = "*)
unset section
;;
"FEC")
if [ -n "$section" ]; then
eval adsl_down_${section}_fec=$a
eval adsl_up_${section}_fec=$b
fi
;;
"CRC")
if [ -n "$section" ]; then
eval adsl_down_${section}_crc=$a
eval adsl_up_${section}_crc=$b
fi
;;
"ES")
if [ -n "$section" ]; then
eval adsl_down_${section}_es=$a
echo "adsl_down_${section}_es=$a" >> $FILESTATS
eval adsl_up_${section}_es=$b
echo "adsl_up_${section}_es=$b" >> $FILESTATS
fi
;;
"SES")
if [ -n "$section" ]; then
eval adsl_down_${section}_ses=$a
echo "adsl_down_${section}_ses=$a" >> $FILESTATS
eval adsl_up_${section}_ses=$b
echo "adsl_up_${section}_ses=$b" >> $FILESTATS
fi
;;
"UAS")
if [ -n "$section" ]; then
eval adsl_down_${section}_uas=$a
echo "adsl_down_${section}_uas=$a" >> $FILESTATS
eval adsl_up_${section}_uas=$b
echo "adsl_up_${section}_uas=$b" >> $FILESTATS
fi
;;
"LOS")
if [ -n "$section" ]; then
eval adsl_down_${section}_los=$a
echo "adsl_down_${section}_los=$a" >> $FILESTATS
eval adsl_up_${section}_los=$b
echo "adsl_up_${section}_los=$b" >> $FILESTATS
fi
;;
"LOF")
if [ -n "$section" ]; then
eval adsl_down_${section}_lof=$a
echo "adsl_down_${section}_lof=$a" >> $FILESTATS
eval adsl_up_${section}_lof=$b
echo "adsl_up_${section}_lof=$b" >> $FILESTATS
fi
;;
"LOM")
if [ -n "$section" ]; then
eval adsl_down_${section}_lom=$a
echo "adsl_down_${section}_lom=$a" >> $FILESTATS
eval adsl_up_${section}_lom=$b
echo "adsl_up_${section}_lom=$b" >> $FILESTATS
fi
;;
esac
done <<-EOF
`xdsl_get_stats`
EOF
set +f
}
help_get_dsl_vendor() {
local name a b section
set -f
while IFS="	:" read -r name a b; do
help_trim_imm a b
case "$name" in
"ChipSet Country Id")
adsl_country_id=$a
;;
"ChipSet Vendor Id")
adsl_vendor_id=$a
;;
"ChipSet Data Path")
adsl_data_path=$a
;;
"ChipSet Latency Path")
adsl_latency_path=$a
;;
esac
done <<-EOF
`xdsl_get_vendor`
EOF
set +f
}
help_count_eth_interfaces() {
[ "$1" != _o ] && local _o
[ "$1" != _i ] && local _i
_i=0
for _o in Ethernet.InterfaceNumberOfEntries WiFi.SSIDNumberOfEntries; do
cmclient -v _o GETV $_o
_i=$((_i + $_o))
done
eval $1='$_i'
}
help_get_atm_mac_address() {
local mac obj="$1"
command -v help_strextract >/dev/null || . /etc/ah/helper_functions.sh
cmclient -v mac GETV Device.X_ADB_FactoryData.BaseMACAddress
cmclient -v _i GETV $obj.X_ADB_MacOffset
if [ ${_i:=-1} -gt -1 ]; then
inc_mac_address "$mac" "$_i"
else
help_count_eth_interfaces _i
inc_mac_address "$mac" "$((_i + ${obj#Device.ATM.Link.}))"
fi
return
echo "$mac"
}
help_get_ptm_mac_address() {
local mac obj="$1" _i
command -v help_strextract >/dev/null || . /etc/ah/helper_functions.sh
cmclient -v mac GETV Device.X_ADB_FactoryData.BaseMACAddress
cmclient -v _i GETV $obj.X_ADB_MacOffset
if [ ${_i:=-1} -gt -1 ]; then
inc_mac_address "$mac" "$_i"
else
help_count_eth_interfaces _i
inc_mac_address "$mac" "$((_i + ${obj#Device.PTM.Link.}))"
fi
return
echo "$mac"
}
help_get_ptm_port_id() {
local obj="$2" _id lowerLayers tmp
if [ -n "$obj" ]; then
cmclient -v tmp GETV "${obj}.LPATH"
_id=$(($tmp+1))
else
cmclient -v lowerLayers GETV "${obj}.LowerLayers"
cmclient -v tmp GETV "${lowerLayers}.LPATH"
_id=$(($tmp+1))
fi
[ $_id -gt 1 ] && _id=1
eval $1='$_id'
}
help_get_dsl_SNRMpb() {
local a b first="1"
while  read -r  a b; do
if [ ! -z "$a" ] && [ -z "${a##[0-9]*}" ]; then
if [ $a -gt 5 ] && [ $a -lt 32 ] && [ "$1" = "us" ]; then
if [ "$first" = "1" ]; then
printf "%.1f" $b
first="0"
else
printf ",%.1f" $b
fi
elif [ $a -gt 32 ] && [ "$1" = "ds" ]; then
if [ "$first" = "1" ]; then
printf "%.1f" $b
first="0"
else
printf ",%.1f" $b
fi
fi
fi
done <<-EOF
`xdsl_get_snr`
EOF
echo
}
dsl_dev_exists() {
local path=/sys/class/net/$1*
set -- $path
[ $# -eq 1 -a "$1" = "$path" ] && return 1
return 0
}
