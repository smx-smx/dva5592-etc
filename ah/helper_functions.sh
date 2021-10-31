#!/bin/sh
[ -f /etc/ah/helper_wifi_bsd.sh ] && . /etc/ah/helper_wifi_bsd.sh
help_strextract() {
local _temp=${1#$2}
_temp="$3$_temp"
echo "${1%$_temp}"
}
help_str_replace() {
local search=$1
local replace=$2
local subject=$3
case "$subject" in
*"$search"*)
echo "${subject%%$search*}$replace${subject#*$search}"
;;
*)
echo "$subject"
return 1
;;
esac
}
help_str_replace_all() {
local search=$1
local replace=$2
local subject=$3
local ret=0
while :; do
subject=`help_str_replace "$search" "$replace" "$subject"` || break
ret=$((ret + 1))
done
echo "$subject"
return $ret
}
help_is_in_list()
{
case ,"$1", in
*,"$2",* )
return 0
;;
* )
return 1
;;
esac
}
help_is_in_list_general()
{
local input_str="$3$1$4"
local pattern="$3$2$4"
case "$input_str" in
*"$pattern"* )
return 0
;;
* )
return 1
;;
esac
}
help_list_contains() {
local x
[ -n "$3" ] && x=$3 || x=,
case "$x$1$x" in
*$x$2$x*) return 0 ;;
esac
return 1
}
help_item_add_uniq_in_list() {
if ! help_is_in_list "$2" "$3"; then
eval $1='${2:+$2,}$3'
else
eval $1='$2'
return 1
fi
}
help_remove_from_unique_list()
{
[ "$1" = before ] || local before
[ "$1" = after ] || local after
[ "$1" = tmp ] || local tmp
[ "$1" = sep ] || local sep
tmp=,$2,
case "$tmp" in
*,$3,*)
before=${tmp%%,$3,*}
after=${tmp##*,$3,}
[ ${#before} -gt 0 -a ${#after} -gt 0 ] && sep=, || sep=
eval $1='${before#,}$sep${after%,}'
;;
*) eval $1='$2' ;;
esac
}
help_item_replace_uniq_in_list() {
local list="$1"
local search="$2"
local replace="$3"
if help_is_in_list "$list" "$replace"; then
echo "$list"
return 2
fi
[ -z $replace ] && local separator="," || local separator=""
case "$list" in
*",$search,"*)
echo "${list%%$search*}$replace${list#*$search$separator}"
;;
*",$search")
echo "${list%%$separator$search*}$replace"
;;
"$search,"*)
echo "$replace${list#*$search$separator}"
;;
"$search")
echo "$replace"
;;
*)
echo "$list"
return 1
;;
esac
}
get_elem_n() {
local ret=$1
local list=$2
local position=$3
local localResult=""
IFS=$4
set -f
set -- $list
set +f
unset IFS
eval $ret'=${'$position'}'
}
help_object_remove_references() {
local obj="$1" refIntf="$2" disableObj="$3" tmpVal
cmclient -v tmpVal GETV "$obj"
[ -z "$tmpVal" ] && return
if help_is_in_list "$tmpVal" "$refIntf"; then
tmpVal=$(help_item_replace_uniq_in_list "$tmpVal" "$refIntf" "")
cmclient SET "$obj" "$tmpVal"
[ -z "$tmpVal" -a -n "$disableObj" ] && cmclient SET "$disableObj" "false"
fi
}
help_if_link_change() {
local ifname="$1"
local status="$2"
local ah_name="$3"
local mtu="$4"
local cmd=""
if [ "$ifname" ]; then
if [ "$status" = "Up" ]; then
cmd="up"
else
cmd="down"
fi
echo "### $ah_name: Executing <ip link set "$ifname" "$cmd"> ###"
if [ "$mtu" ] && [ $mtu -gt 0 ]; then
ip link set "$ifname" "$cmd" mtu "$mtu"
else
ip link set "$ifname" "$cmd"
fi
fi
}
help_obj_from_ifname_get_var() {
case $2 in
ppp* )
cmclient -v $1 GETO -u "$3" Device.PPP.Interface.*.[Name="$2"]
;;
atm* )
cmclient -v $1 GETO -u "$3" Device.ATM.Link.*.[Name="$2"]
;;
ptm*.* )
cmclient -v $1 GETO -u "$3" Device.Ethernet.VLANTermination.*.[Name="$2"]
;;
ptm* )
cmclient -v $1 GETO -u "$3" Device.PTM.Link.*.[Name="$2"]
;;
br* )
cmclient -v $1 GETO -u "$3" Device.Bridging.Bridge.**.[Name="$2"]
;;
wl* )
cmclient -v $1 GETO -u "$3" Device.WiFi.SSID.*.[Name="$2"]
;;
usb* )
cmclient -v $1 GETO -u "$3" Device.USB.Interface.*.[Name="$2"]
;;
wwan* )
cmclient -v $1 GETO -u "$3" Device.Ethernet.Link.*.[Name="$2"]
;;
*.* )
cmclient -v $1 GETO -u "$3" Device.Ethernet.VLANTermination.*.[Name="$2"]
[ -z "$1" ] && cmclient -v $1 GETO -u "$3" Device.Ethernet.Interface.*.[Name="${2%%.*}"]
;;
* )
cmclient -v $1 GETO -u "$3" Device.Ethernet.Interface.*.[Name="$2"]
;;
esac
}
help_obj_from_ifname_get() {
local obj=""
help_obj_from_ifname_get_var obj "$1" "$2"
echo "$obj"
}
help_lowlayer_intf_get() {
local _lowlayer="$1"
local _endintf="$2"
local _user="$3"
local next_lowlayer
cmclient -v next_lowlayer GETV -u "$_user" "$_lowlayer.LowerLayers"
while [ -n "$next_lowlayer" ]; do
case $next_lowlayer in
"$_endintf"*)
echo "$next_lowlayer"
return
;;
*)
cmclient -v next_lowlayer GETV -u "$_user" "$next_lowlayer.LowerLayers"
;;
esac
done
echo ""
}
help_is_valid_ip() {
local ret=0
local seg
case "$1" in
[!0-9]*|*[!0-9])
return 255
;;
esac
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=.
set -- $1
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
if [ $# -eq 4 ]; then
for seg; do
case $seg in
[0-9]|[0-9][0-9]|[0-9][0-9][0-9])
[ $seg -gt 255 ] && ret=255 && break
;;
*)
ret=255
break
;;
esac
done
else
ret=255
fi
set +f
return $ret
}
help_is_valid_ipv6() {
local seg dual_colon part tmp_value tmp_cut single ret=0
case "$1" in
*':::'*)
return 255
;;
*'::'*'::'*)
return 255
;;
*'::'*)
dual_colon=1
;;
*)
dual_colon=0
;;
esac
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=:
set -- $1
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
if [ $dual_colon -eq 0 -a $# -ne 8 ] || [ $dual_colon -eq 1 -a $# -gt 8 ]; then
ret=255
fi
for seg; do
seg_length=${#seg}
if [ $seg_length -gt 4 ]; then
ret=255
break
fi
if [ $seg_length -eq 0 ]; then
continue
fi
tmp_value=$seg
while [ ${#tmp_value} -gt 0 ]; do
tmp_cut=${tmp_value#?}
single=${tmp_value%"$tmp_cut"}
tmp_value=$tmp_cut
case $single in
[0-9]|[a-f]|[A-F])
continue
;;
*)
ret=255
break
;;
esac
done
[ $ret -eq 255 ] && break
done
set +f
return $ret
}
help_is_valid_mac() {
local ret=0
local seg
case "$1" in
[!0-9a-fA-F]*|*[!0-9a-fA-F])
return 255
;;
esac
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=:
set -- $1
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
if [ $# -eq 6 ]; then
for seg; do
case $seg in
[0-9a-fA-F]|[0-9a-fA-F][0-9a-fA-F])
;;
*)
ret=255
break
;;
esac
done
else
ret=255
fi
set +f
return $ret
}
help_is_valid_port() {
local port="$1"
case "$port" in
*[!0-9]*)
return 255
;;
*)
[ $port -gt 0 -a $port -le 65535 ] || return 255
;;
esac
}
help_get_base_stats_core() {
local get_path="$1" ifname="$2" retpar="$3" buf="0"
if [ -n "$ifname" ] && [ -d /sys/class/net/"$ifname" ]; then
case "$get_path" in
*".BytesSent" )
read buf < /sys/class/net/"$ifname"/statistics/tx_bytes
;;
*".DiscardPacketsSent" )
read buf < /sys/class/net/"$ifname"/statistics/tx_dropped
;;
*".PacketsSent" )
read buf < /sys/class/net/"$ifname"/statistics/tx_packets
;;
*".ErrorsSent" )
read buf < /sys/class/net/"$ifname"/statistics/tx_errors
;;
*".BytesReceived" )
read buf < /sys/class/net/"$ifname"/statistics/rx_bytes
;;
*".DiscardPacketsReceived" )
read buf < /sys/class/net/"$ifname"/statistics/rx_dropped
;;
*".PacketsReceived" )
read buf < /sys/class/net/"$ifname"/statistics/rx_packets
;;
*".ErrorsReceived" )
read buf < /sys/class/net/"$ifname"/statistics/rx_errors
;;
*".CRCErrors" )
read buf < /sys/class/net/"$ifname"/statistics/rx_crc_errors
;;
*".MACAddress" )
read buf < /sys/class/net/"$ifname"/address
;;
* )
buf=""
;;
esac
fi
eval $retpar='$buf'
}
help_convert_date() {
local ts="$1" arg="$2"
ts=`help_tr "T" " " "$ts"`
ts=`help_tr "Z" "" "$ts"` # XXX, optimize with: ts=${ts%%Z} ?
date $arg +"%s" --date="$ts"
}
help_get_base_stats()
{
local get_path=$1 ifname=$2 retstat
help_get_base_stats_core $get_path $ifname retstat
echo "$retstat"
}
help_get_authentication_algorithm_val() {
local _ret
local _visited_once
if [ -z "$1" ]; then
echo "non_auth"
fi
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=","
set -- $1
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
for arg; do
if [ "$_visited_once" = "1" ]; then
_ret=$_ret","
fi
if [ "$arg" = "MD5" ]; then
_ret=$_ret"hmac_md5"
elif [ "$arg" = "SHA1" ]; then
_ret=$_ret"hmac_sha1"
else
_ret="non_auth"
fi
_visited_once="1"
done
echo "$_ret"
}
help_get_encryption_algorithm_val() {
local _ret
local _visited_once
if [ -z "$1" ]; then
echo "null_enc"
fi
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=","
set -- $1
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
for arg; do
if [ "$_visited_once" = "1" ]; then
_ret=$_ret","
fi
if [ "$arg" = "DES" ]; then
_ret=$_ret"des"
elif [ "$arg" = "3DES" ]; then
_ret=$_ret"3des"
elif [ "$arg" = "AES128" ]; then
_ret=$_ret"aes 128"
elif [ "$arg" = "AES192" ]; then
_ret=$_ret"aes 192"
elif [ "$arg" = "AES256" ]; then
_ret=$_ret"aes 256"
elif [ "$arg" = "none" ]; then
_ret="null_enc"
break;
else
_ret="null_enc"
break;
fi
_visited_once="1"
done
echo "$_ret"
}
is_lan_intf() {
local _o="$1" _user="$2" _tmp
while [ ${#_o} -gt 0 ]; do
cmclient -v _tmp GETV -u "$_user" "$_o.LowerLayers"
[ ${#_tmp} -gt 0 ] && _o=${_tmp%%,*} && continue
case $_o in
"Device.X_ADB_VPN.Client."*)	return 1	;;
*)	cmclient -v _tmp GETV -u "$_user" "$_o.Upstream"
[ "$_tmp" = "true" ] && return 1 || return 0
;;
esac
done
return 1
}
is_wan_intf() {
! is_lan_intf "$@"
}
get_dev_rule_table() {
local ip_ifname=$1
local table_idx
table_idx=${ip_ifname##*Interface.}
table_idx=${table_idx%%.}
if [ "$table_idx" ]; then
table_idx=$((table_idx+1000))
echo $table_idx
else
echo ""
fi
}
get_dev_mark() {
local ip_ifname=$1
local table_mark
table_mark=${ip_ifname##*Interface.}
table_mark=${table_mark%%.}
if [ "$table_mark" ]; then
table_mark=$((table_mark*256))
echo $table_mark
else
echo ""
fi
}
is_pure_bridge() {
local _bridge="$1" _user="$2" _ports="$3" br_port
if [ ${#_ports} -gt 0 ]; then
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=","
set -f
set -- $_ports
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
else
cmclient -v _ports GETV -u "$_user" "$_bridge.**.[ManagementPort=false].LowerLayers"
set -f
set -- $_ports
set +f
fi
for br_port
do
is_wan_intf "$br_port" && return 0
done
return 1
}
ip_interface_get() {
local up="$1" _user="$2" found=0 up_temp up_obj up_obj_clean
while [ "$up" ]; do
up_temp=""
cmclient -v up_obj GETO -u "$_user" "Device.**.[LowerLayers>$up]"
if [ "$up_obj" = "$up" ]; then
break
fi
up_obj_clean=""
for up_temp in $up_obj
do
if [ "$up_temp" = "$up" ]; then
continue
fi
up_obj_clean="$up_obj_clean $up_temp"
done
up_obj=$up_obj_clean
for up_temp in $up_obj
do
if [ "$up_temp" = "$up" ]; then
continue
fi
up="$up_temp"
if [ "${up%.*}" = "Device.IP.Interface" ]; then
found=1
break
fi
done
if [ $found -eq 1 ] || [ -z "$up_temp" ]; then
break
fi
done
if [ $found -eq 1 ]; then
echo "$up"
else
echo ""
fi
}
interface_name_get() {
local ip_name="$1"
local mac="$2"
case "$ip_name" in
br*)
entry_list=`cat /sys/class/net/$ip_name/brforward | hexdump -v -e '/1 "%02x" ":"'`
mac_entry="${entry_list##*"$mac:"}"
if [ "$mac_entry" != "$entry_list" ]; then
if_index="${mac_entry%%:*}"
for port in /sys/class/net/$ip_name/brif/*; do
read port_index < $port/port_id
tmp_id="${port_index##*$if_index}"
if [ -z "$tmp_id" ]; then
ifn="${port##*/}"
break
fi
done
fi
;;
*)
ifn="$ip_name"
;;
esac
echo "$ifn"
}
align_upper_layers() {
local obj="$1" enable="$2" up="$3" _user="$4" up_layers up_layer
cmclient -v up_layers GETV -u "$_user" "Device.InterfaceStack.[LowerLayer=$obj].HigherLayer"
for up_layer in $up_layers; do
case $up_layer in
$up*)
cmclient SET -u "$_user" "$up_layer.Enable" "$enable"
;;
esac
done
}
help_sort_orders() {
local _obj=$1
local _oldorder=$2
local _neworder=$3
local _user=$4
local _param=${5:-Order}
local _additional_filter="${6:+[$6].}"
local ex_order
local i
local tmp
cmclient -v tmp GETV "${_obj%.*}.*.${_additional_filter}[${_param}=$_neworder].${_param}"
if [ -n "$tmp" ]; then
if [ $_neworder -lt $_oldorder ]; then
cmclient -v tmp GETO "${_obj%.*}.*.${_additional_filter}[${_param}+$((_neworder - 1))]"
for i in $tmp; do
[ "$i" = "$_obj" ] && continue
cmclient -v ex_order GETV "$i".${_param}
if [ $ex_order -lt $_oldorder ]; then
cmclient SET -u "${_user:-${AH_NAME}${i}}" "$i.${_param}" "$((ex_order + 1))" >/dev/null
fi
done
else
cmclient -v tmp GETO "${_obj%.*}.*.${_additional_filter}[${_param}-$((_neworder + 1))]"
for i in $tmp; do
[ "$i" = "$_obj" ] && continue
cmclient -v ex_order GETV "$i".${_param}
if [ $ex_order -gt $_oldorder ]; then
cmclient SET -u "${_user:-${AH_NAME}${i}}" "$i.${_param}" "$((ex_order - 1))" >/dev/null
fi
done
fi
fi
}
help_tr() {
local str1=$1
local str2=$2
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS="$str1"
set -- $3
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
[ $# -eq 0 ] && return
printf "%s" "$1"
shift
for arg; do
printf "%s%s" "$str2" "$arg"
done
}
help_trcd() {
local set="$1"
local arg="$2"
local ret=''
local tmp=''
[ -z "$set" ] && return 1
while [ -n "$arg" ]; do
while [ -n "$arg" ]; do
tmp="$arg"
arg=${arg#[!$set]}
[ "$arg" = "$tmp" ] && break
done
while [ -n "$arg" ]; do
tmp=`expr match "$arg" "\([$set]\)"`
[ -z "$tmp" ] && break
ret="$ret$tmp"
arg=${arg#[$set]}
done
done
echo "$ret"
}
help_trd() {
local set="$1"
local arg="$2"
local ret=''
local tmp=''
[ -z "$set" ] && return 1
while [ -n "$arg" ]; do
while [ -n "$arg" ]; do
tmp="$arg"
arg=${arg#[$set]}
[ "$arg" = "$tmp" ] && break
done
while [ -n "$arg" ]; do
tmp=`expr match "$arg" "\([^$set]\)"`
[ -z "$tmp" ] && break
ret="$ret$tmp"
arg=${arg#[!$set]}
done
done
echo "$ret"
}
help_lowercase() {
local str="$1"
local tmp
while [ -n "${str%"${str#?}"}" ]; do
tmp="${str%"${str#?}"}"
case "$tmp" in
A) printf '%c' a ;;
B) printf '%c' b ;;
C) printf '%c' c ;;
D) printf '%c' d ;;
E) printf '%c' e ;;
F) printf '%c' f ;;
G) printf '%c' g ;;
H) printf '%c' h ;;
I) printf '%c' i ;;
J) printf '%c' j ;;
K) printf '%c' k ;;
L) printf '%c' l ;;
M) printf '%c' m ;;
N) printf '%c' n ;;
O) printf '%c' o ;;
P) printf '%c' p ;;
Q) printf '%c' q ;;
R) printf '%c' r ;;
S) printf '%c' s ;;
T) printf '%c' t ;;
U) printf '%c' u ;;
V) printf '%c' v ;;
W) printf '%c' w ;;
X) printf '%c' x ;;
Y) printf '%c' y ;;
Z) printf '%c' z ;;
*) printf '%s' "$tmp" ;;
esac
str="${str#?}"
done
}
help_uppercase() {
local str="$1"
local tmp
while [ -n "${str%"${str#?}"}" ]; do
tmp="${str%"${str#?}"}"
case "$tmp" in
a) printf '%c' A ;;
b) printf '%c' B ;;
c) printf '%c' C ;;
d) printf '%c' D ;;
e) printf '%c' E ;;
f) printf '%c' F ;;
g) printf '%c' G ;;
h) printf '%c' H ;;
i) printf '%c' I ;;
j) printf '%c' J ;;
k) printf '%c' K ;;
l) printf '%c' L ;;
m) printf '%c' M ;;
n) printf '%c' N ;;
o) printf '%c' O ;;
p) printf '%c' P ;;
q) printf '%c' Q ;;
r) printf '%c' R ;;
s) printf '%c' S ;;
t) printf '%c' T ;;
u) printf '%c' U ;;
v) printf '%c' V ;;
w) printf '%c' W ;;
x) printf '%c' X ;;
y) printf '%c' Y ;;
z) printf '%c' Z ;;
*) printf '%s' "$tmp" ;;
esac
str="${str#?}"
done
}
help_hexprint() {
local str="$1"
local tmp
while [ -n "${str%"${str#?}"}" ]; do
tmp="${str%"${str#?}"}"
printf '%.2X' "'$tmp'"
str="${str#?}"
done
}
help_ipcmp_enh() {
local ip1=$1
local cmp=$2
local ip2=$3
local bip1
local bip2
help_is_valid_ip "$ip1" || return 255
help_is_valid_ip "$ip2" || return 255
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS="."
set -- $ip1
bip1=$(($1 * 16777216 | $2 * 65536 | $3 * 256 | $4))
set -- $ip2
bip2=$(($1 * 16777216 | $2 * 65536 | $3 * 256 | $4))
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
case $cmp in
"<")  [ $bip1 -lt $bip2 ] && return 0;;
"<=") [ $bip1 -le $bip2 ] && return 0;;
">")  [ $bip1 -gt $bip2 ] && return 0;;
">=") [ $bip1 -ge $bip2 ] && return 0;;
"==") [ $bip1 -eq $bip2 ] && return 0;;
"!=") [ $bip1 -ne $bip2 ] && return 0;;
esac
return 1
}
help_ipcmp() {
local ip1=$1
local ip2=$2
local bip1
local bip2
help_is_valid_ip "$ip1" || return 255
help_is_valid_ip "$ip2" || return 255
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS="."
set -- $ip1
bip1=$(($1 * 16777216 | $2 * 65536 | $3 * 256 | $4))
set -- $ip2
bip2=$(($1 * 16777216 | $2 * 65536 | $3 * 256 | $4))
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
[ $bip1 -gt $bip2 ] && return 1
[ $bip1 -lt $bip2 ] && return 2
return 0
}
help_html_escape() {
local str="$@"
local tail="$str" c
while [ -n "$tail" ] ; do
tail="${str#?}"
c="${str%"$tail"}"
case $c in
\&) printf '%s' '&amp;'  ;;
\<) printf '%s' '&lt;'   ;;
\>) printf '%s' '&gt;'   ;;
\") printf '%s' '&quot;' ;;
\') printf '%s' '&#39;'  ;;
*)  printf '%s' "$c"     ;;
esac
str="$tail"
done
}
help_xml_escape() {
[ "$1" != str ] && local str
[ "$1" != tail ] && local tail
[ "$1" != resStr ] && local resStr
[ "$1" != c ] && local c
str="$2"
tail="$str"
resStr=""
while [ -n "$tail" ] ; do
tail="${str#?}"
c="${str%"$tail"}"
case $c in
\&) resStr="$resStr""&amp;"  ;;
\<) resStr="$resStr""&lt;"   ;;
\>) resStr="$resStr""&gt;"   ;;
\") resStr="$resStr""&quot;" ;;
\') resStr="$resStr""&apos;" ;;
*)  resStr="$resStr""${c}"   ;;
esac
str="$tail"
done
eval $1='$resStr'
}
help_regex_escape() {
local str="$@"
local tail="$str" c
while [ -n "$tail" ] ; do
tail="${str#?}"
c="${str%"$tail"}"
case $c in
[\]\[\\\(\)\|{}+*?$.^]) printf '%s' "\\$c" ;;
*)  printf '%s' "$c" ;;
esac
str="$tail"
done
}
help_uri_escape() {
local uri="$@"
local tail="$uri" c
while [ -n "$tail" ] ; do
tail="${uri#?}"
c="${uri%"$tail"}"
case $c in
[a-zA-Z0-9/.:?\&=@])
printf '%s' "$c"
;;
*)
printf '%%%x' "'$c"
;;
esac
uri=$tail
done
}
help_is_changed() {
local arg
for arg; do
eval [ \"\$changed$arg\" = \"1\" ] && return 0
done
return 1
}
help_check_cwmp_progress() {
local cwmp_progress
while :; do
cmclient -v cwmp_progress GETV Device.ManagementServer.X_ADB_CWMPState.SessionInProgress
if [ "$cwmp_progress" = "true" ]; then
sleep 1
else
break
fi
done
}
help_host_disconnect() {
local host="$1" ifname="$2" mac="$3" ipaddrs="$4" resetActive="$5" l1_if tmp ipaddr
help_serialize "$mac" notrap
cmclient -v tmp GETV "$host.Active"
if [ "$tmp" = "true" ]; then
cmclient SETM "$host.Active=false	$host.X_ADB_LastUp=`date -u +%s`"
help_serialize_unlock "$mac"
for ipaddr in $ipaddrs; do
ip neigh del "$ipaddr" dev "$ifname"
done
else
[ "$resetActive" = "true" ] && cmclient SET "$host.Active" "false"
help_serialize_unlock "$mac"
fi
}
help_align_host_table() {
local l1intf="$1" physAddr="$2" objs ipv4addrs ipv6addrs ipaddr ifname
command -v help_serialize >/dev/null || . /etc/ah/helper_serialize.sh
[ -n "$l1intf" ] && [ -z "$physAddr" ] && host="Device.Hosts.Host.[Layer1Interface=$l1intf]"
[ -z "$l1intf" ] && [ -n "$physAddr" ] && host="Device.Hosts.Host.[PhysAddress=$physAddr]"
[ -n "$l1intf" ] && [ -n "$physAddr" ] && host="Device.Hosts.Host.[Layer1Interface=$l1intf].[PhysAddress=$physAddr]"
cmclient -v objs GETO "$host"
for h in $objs; do
[ -z "$physAddr" ] && cmclient -v physAddr GETV "$h.PhysAddress"
cmclient -v ifname GETV "%(%($h.Layer3Interface).LowerLayers).Name"
[ -z "$ifname" ] && continue
cmclient -v ipv4addrs GETV "$h.IPv4Address.IPAddress"
cmclient -v ipv6addrs GETV "$h.IPv6Address.IPAddress"
[ -z "$ipv4addrs" -a -z "$ipv6addrs" ] && cmclient -v ipaddr GETV "$h.IPAddress"
[ -z "$ipv4addrs$ipv6addrs$ipaddr" ] && continue
help_host_disconnect "$h" "$ifname" "$physAddr" "$ipv4addrs $ipv6addrs $ipaddr"
done
}
is_ip_in_subnet() {
local _ipval _netval _maskval
. /etc/ah/helper_ipcalc.sh
help_ip2int _ipval $1
help_ip2int _netval $2
help_ip2int _maskval $3
[ $((_ipval & _maskval)) -eq $((_netval & _maskval)) ]
}
is_ip_private() {
local _ip=$1
is_ip_in_subnet $_ip "10.0.0.0" "255.0.0.0" || is_ip_in_subnet $_ip "172.16.0.0" "255.240.0.0" || is_ip_in_subnet $_ip "192.168.0.0" "255.255.0.0" || return 1
return 0
}
help_is_equal_file() {
local ret=1 chk
if [ -f "$1" -a -f "$2" ]; then
chk=`md5sum "$1"`
chk=${chk%% *}
ret=`echo "$chk  $2" | md5sum -c -s -`
fi
return $ret
}
ERR=255
OK=0
help_strstr() {
[ -z "$2" ] && { echo "$1" ; return 0; }
case "$1" in
*$2*) ;;
*) return 1;;
esac
first=${1%$2*}
echo "${1##$first}"
}
inc_mac_address () {
local _mac="$1"
local _inc="$2"
local _upper="${_mac%:*}"
local _last_byte="${_mac##*:}"
local _num_last_byte=$((0x$_last_byte + $_inc))
[ "$_upper" = "$_mac" ] && _upper=""
if [ $_num_last_byte -gt 255 ]; then
[ -n "$_upper" ] && _upper=`inc_mac_address "$_upper" 1`
_num_last_byte=$(($_num_last_byte - 256))
fi
_last_byte=`printf %02x $_num_last_byte`
[ -n "$_upper" ] && _upper="${_upper}:"
echo "${_upper}${_last_byte}"
}
set_mac_offset () {
local obj="$1" ll_name="$2" if_name="" if_mac="" new_if_mac="" base_mac="" mac_off=""
cmclient -v if_name GETV "$obj.Name"
read if_mac < /sys/class/net/$if_name/address
cmclient -v mac_off  GETV "$obj.X_ADB_MacOffset"
cmclient -v base_mac GETV "Device.X_ADB_FactoryData.BaseMACAddress"
new_if_mac=$(inc_mac_address "$base_mac" "$mac_off")
[ "$new_if_mac" = "$if_mac" ] || ifconfig "$if_name" hw ether "$new_if_mac"
}
str_x() {
[ "$1" != "c" ] && local c
[ "$1" != "len" ] && local len
[ "$1" != "i" ] && local i
[ "$1" != "t" ] && local t
c="$2"
len="$3"
i=0
while [ $i -lt $len ]; do
t="$t$c"
i=$((i + 1))
done
eval $1='$t'
}
str_cut() {
[ "$1" != "str" ] && local str
[ "$1" != "start" ] && local start
[ "$1" != "end" ] && local end
[ "$1" != "len" ] && local len
[ "$1" != "h" ] && local h
str="$2"
start="$3"
end=$(($4 - $3))
len=${#2}
if [ $start -le $((len / 2)) ]; then
str_x h "?" $((start - 1))
str=${str#$h}
else
str_x h "?" $((len - $start + 1))
str=${str#"${str%$h}"}
fi
len=${#str}
if [ $end -lt $((len / 2)) ]; then
str_x h "?" $((end + 1))
str=${str%"${str#$h}"}
else
str_x h "?" $((len - $end - 1))
str=${str%$h}
fi
eval $1='$str'
}
help_load_dom()
{
cmclient DOM Device /etc/cm/tr181/dom/
[ -d /etc/cm/tr098/dom ] && cmclient DOM InternetGatewayDevice /etc/cm/tr098/dom/
[ -d /etc/cm/tr181ref/dom ] && cmclient DOM Device /etc/cm/tr181ref/dom/
[ -d /etc/cm/tr181/dom-customer ] && cmclient DOM Device /etc/cm/tr181/dom-customer/
[ -d /etc/cm/tr098/dom-customer ] && cmclient DOM InternetGatewayDevice /etc/cm/tr098/dom-customer/
[ -d /etc/cm/tr181ref/dom-customer ] && cmclient DOM Device /etc/cm/tr181ref/dom-customer/
}
help_xtm_link_down() {
if [ -f /etc/ah/IPv6_helper_functions.sh ]; then
. /etc/ah/IPv6_helper_functions.sh
ipv6_proc_enable "false" "$1"
fi
help_if_link_change "$1" "Down" "$AH_NAME"
}
help_get_boardid() {
local _line
[ "$1" != "boardid" ] && local boardid
IFS="
"
while read _line ; do
case "$_line" in
"system type"* )
boardid="${_line##*: }"
break
;;
*) ;;
esac
done < /proc/cpuinfo
unset IFS
eval $1='$boardid'
}
get_ip4_from_URL()
{
local URL=$1 _hostname _ip=""
URL=$(help_tr " " "" "$URL")
if [ ${#URL} -ne 0 ]; then
_hostname=${URL#*://}
_hostname=${_hostname#*@}
_hostname=${_hostname%%/*}
_hostname=${_hostname%%:*}
if ! help_is_valid_ip "$_hostname"; then
_ip=$(host "$_hostname")
if [ "$?" -eq 1 ]; then
_ip=""
else
for _ip in $_ip; do
help_is_valid_ip "$_ip" && break
done
fi
else
_ip=$_hostname
case "$_ip" in
"255.255.255.255"|"0.0.0.0") _ip=""
;;
esac
fi
fi
eval $2=$_ip
}
help_pow() {
local x="$2" y="$3" i=1
[ "$1" != "res" ] && local res
res=1
while [ $i -le $y ]; do
res=$((res * x))
i=$((i + 1))
done
eval $1='$res'
}
help_check_clean_hosts() {
local mac=$1
if [ -f /etc/ah/helper_wifi_bsd.sh ]; then
help_host_configured_to_use_bsd "$mac" && return
fi
help_change_objects_storage_option 0 "$2"
}
help_change_objects_storage_option () {
local storage_value=$1 param=""
for param in $2; do
cmclient SETS "$param" $storage_value
done
cmclient SAVE
}
help_log() {
[ $1 = ret ] || local ret
local x=$2 n=$3
ret=-1
while [ $x -gt 0 ]; do
ret=$((ret + 1))
x=$((x / $n))
done
eval $1='$ret'
}
help_switch_mac_lookup() {
[ "$1" = ifname ] || local ifname
local match_mac="$2" found=0
match_mac=$(help_tr ":" "" $match_mac)
while read id mac vlan static mask; do
case "$id" in
[0-9]*)
case "$mac" in
"$match_mac")
help_log portid $mask 2
ifname=`cat /proc/hwswitch/default/port$portid/dev`
found=1
break
;;
esac
;;
esac
done < /proc/hwswitch/default/arltable
eval $1='$ifname'
return $found
}
help_wifi_mac_lookup() {
[ "$1" = ifname ] || local ifname
local match_mac=$(help_lowercase $2) obj found=0
cmclient -v obj GETO Device.WiFi.AccessPoint.[Enable=true].AssociatedDevice.[MACAddress="$match_mac"]
if [ ${#obj} -gt 0 ]; then
for obj in $obj; do break; done
cmclient -v ifname GETV "%(${obj%.AssociatedDevice*}.SSIDReference).Name"
found=1
fi
eval $1='$ifname'
return $found
}
help_mac_lookup() {
[ "$1" = ifname ] || local ifname
local found=0
help_switch_mac_lookup ifname "$2" && help_wifi_mac_lookup ifname "$2"
found=$?
eval $1='$ifname'
return $found
}
help_hex_to_string() {
local str="$1"
local str_len=${#str}
local hex_len=2
local position=0
while [ $position -lt $str_len ]; do
printf "\x"${str:$position:$hex_len}
position=$((position+hex_len))
done
}
help_convert_to_dbm() {
local number=$1 out=$2 divisior=1000 total_part fractional_part ret
case "$number" in
Unavailable*)
ret="Unavailable"
;;
*)
total_part=$((number/divisior))
fractional_part=$((number%divisior))
fractional_part=${fractional_part#-}
ret="$total_part.$fractional_part"
;;
esac
eval $out='$ret'
}