# DEBUG=true
. /etc/clish/clish-permissions.sh
. /etc/ah/helper_functions.sh
. /etc/ah/IPv6_helper_functions.sh
DEFAULT_FIRST_COL_WIDTH="40"
let TRUNCATED_FIRST_COL_WIDTH=$DEFAULT_FIRST_COL_WIDTH-3
get_ll_list() {
local ll="$1"
while [ 1 ]; do
cmclient -v ll GETV "$ll.LowerLayers" >/dev/null
[ -n "$ll" ] && echo "$ll" || break
done
}
cli_interfaces_list="
Device.ATM.Link
Device.PTM.Link
Device.PPP.Interface
Device.Ethernet.Interface
Device.WiFi.SSID
Device.Bridging.Bridge
Device.Ethernet.VLANTermination
Device.DSL.Line
"
cli_interface_list_firewall="
Device.IP.Interface
Device.PPP.Interface
Device.ATM.Link
Device.PTM.Link
Device.WiFi.SSID
Device.Ethernet.Interface
Device.Bridging.Bridge
"
ifaces_del_list="
Device.PPP.Interface
Device.Ethernet.VLANTermination
Device.Bridging.Bridge
Device.ATM.Link
Device.PTM.Link
"
ifaces_get_deletable_list_obj() {
local this list ifname objAccess ip_iface role
get_user_role role
for ifname in $ifaces_del_list; do
cmclient -v list GETO "${ifname}"
for this in $list; do
ip_iface="$(ll_obj_to_ip_obj $this)"
if [ -n "${ip_iface}" ]; then
get_obj_access_for_role objAccess "${ip_iface}" 3 "$role"
[ $objAccess -eq 3 ] || continue
fi
echo "${this}"
done
done
}
ip_interface_get_cli_ll() {
local ll=`get_ll_list "$1"`
for i in $ll; do
for j in $cli_interfaces_list; do
[ -n "${i%%$j*}" ] && continue
echo "${i%%.Port.*}" # stripping Port from bridge
return 0
done
done
return 1
}
iface_create_ethernet_link() {
local ll_iface="$1"
local output
local iface_idx
cmclient -v iface_idx ADD "Device.Ethernet.Link"
if ! cm_err_maybe_break "$iface_idx"; then
return 1
fi
cmclient -v output SET "Device.Ethernet.Link.$iface_idx.LowerLayers" "$ll_iface"
if ! cm_err_maybe_break "$output"; then
return 1
fi
echo "Device.Ethernet.Link.$iface_idx"
}
num_to_dscp() {
case "$1" in
"-2") echo "auto";;
"0" ) echo "CS0";;
"8" ) echo "CS1";;
"10" ) echo "AF11";;
"12" ) echo "AF12";;
"14" ) echo "AF13";;
"16" ) echo "CS2";;
"18" ) echo "AF21";;
"20" ) echo "AF22";;
"22" ) echo "AF23";;
"24" ) echo "CS3";;
"26" ) echo "AF31";;
"28" ) echo "AF32";;
"30" ) echo "AF33";;
"32" ) echo "CS4";;
"34" ) echo "AF41";;
"36" ) echo "AF42";;
"38" ) echo "AF43";;
"40" ) echo "CS5";;
"46" ) echo "EF";;
"48" ) echo "CS6";;
"56" ) echo "CS7";;
* ) echo "";;
esac
}
handle_list_actions() {
local local_list_dm_location="$1"
local local_action_value="$2"
local local_item="$3"
local local_replace_item="$4"
local local_setm=""
local local_list=""
cmclient -v local_list GETV "$local_list_dm_location"
if [ "$local_action_value" = "show" ]; then
local_setm=$(help_str_replace_all "," "\n" "$local_list")
elif [ "$local_action_value" = "add" ]; then
help_item_add_uniq_in_list local_setm "$local_list" "$local_item"
[ "$local_setm" != "$local_list" ] && \
local_setm="$local_list_dm_location=$local_setm" || local_setm=""
else
[ "$local_action_value" = "del" ] && local_replace_item=""
local_setm=$(help_item_replace_uniq_in_list "$local_list" "$local_item" "$local_replace_item")
[ "$local_setm" != "$local_list" ] && \
local_setm="$local_list_dm_location=$local_setm" || local_setm=""
fi
echo "$local_setm"
}
upper_interfaces_get() {
local ll_obj_list="$1"
local ll_obj_filter="$2"
local _user="$3"
local ll_temp
local ll_obj
local ll_checked_list=""
local obj
local _seprator_=" "
[ "${ll_obj_list%.*}" = "Device.Bridging.Bridge" ] && cmclient -v ll_obj_list GETO "$ll_obj_list.Port.[ManagementPort=true]"
ll_obj_list="$ll_obj_list${_seprator_}"
while [ "$ll_obj_list" ]; do
ll_temp="${ll_obj_list%%${_seprator_}*}"
ll_obj=""
for obj in `cmclient GETO -u "$_user" "Device.**.[LowerLayers,$ll_temp]"`
do
[ "$obj" = "$ll_temp" -o "${ll_checked_list##*$obj${_seprator_}}" != "$ll_checked_list" ] && continue
ll_obj="$ll_obj${_seprator_}$obj"
done
ll_obj="${ll_obj#${_seprator_}}"
if [ -z "$ll_obj" ]; then
ll_obj_list="${ll_obj_list#*${_seprator_}}"
continue
fi
for obj in $ll_obj; do
if [ -z "$ll_obj_filter" ]; then
echo "$obj"
else
if help_is_in_list "$ll_obj_filter" "${obj%.*}"; then
echo "$obj"
fi
fi
done
ll_temp="${ll_obj%%${_seprator_}*}"
ll_checked_list="${_seprator_}$ll_temp${_seprator_}$ll_checked_list"
ll_obj_list="${ll_obj_list#*${_seprator_}}"
ll_obj_list="$ll_obj${_seprator_}$ll_obj_list"
done
}
remove_entry_from_all_owners() {
local removal_candidate_list="$1"
local single_candidate
local direct_owners
local ll_checked_list=""
local obj
local _seprator_=" "
local del_list=""
[ "${removal_candidate_list%.*}" = "Device.Bridging.Bridge" ] && cmclient -v removal_candidate_list GETO "$removal_candidate_list.Port.[ManagementPort=true]"
removal_candidate_list="$removal_candidate_list${_seprator_}"
while [ "$removal_candidate_list" ]; do
single_candidate="${removal_candidate_list%%${_seprator_}*}"
removal_candidate_list="${removal_candidate_list#*${_seprator_}}"
direct_owners=""
for obj in `cmclient GETO "Device.**.[LowerLayers,$single_candidate]"`
do
[ "$obj" = "$single_candidate" -o "${ll_checked_list##*$obj${_seprator_}}" != "$ll_checked_list" ] && continue
direct_owners="$direct_owners${_seprator_}$obj"
done
direct_owners="${direct_owners#${_seprator_}}"
if [ -z "$direct_owners" ]; then
continue
fi
for obj in $direct_owners; do
new_list="$(handle_list_actions ${obj}.LowerLayers del ${single_candidate})"
right_side=${new_list#*=}
if [ -n "$right_side" ]; then
cmclient SETM "$new_list"
else
del_list="$obj $del_list"
cmclient -v nat_obj GETO "Device.NAT.InterfaceSetting.[Interface=$obj]"
for arg_obj in $nat_obj; do
cmclient DEL "$arg_obj" > /dev/null 2>&1
done
removal_candidate_list="$obj${_seprator_}$removal_candidate_list"
fi
done
local temp="${direct_owners%%${_seprator_}*}"
ll_checked_list="${_seprator_}$temp${_seprator_}$ll_checked_list"
done
for obj in $del_list; do
cmclient DEL $obj > /dev/null 2>&1
done
cmclient DEL $1 > /dev/null 2>&1
}
remove_entry_from_specific_owner()
{
local entry="$1"
local first_owner_class="$2"
local mod_entry
local new_list
local right_side
mod_entry="$entry"
[ "${mod_entry%.*}" = "Device.Bridging.Bridge" ] && cmclient -v mod_entry GETO "$mod_entry.Port.[ManagementPort=true]"
cmclient -v first_owner_list GETO "$first_owner_class.[LowerLayers,$mod_entry]"
for first_owner in $first_owner_list; do
new_list="$(handle_list_actions $first_owner.LowerLayers del $mod_entry)"
right_side=${new_list#*=}
if [ -n "$right_side" ]; then
cmclient SETM "$new_list"
else
remove_entry_from_all_owners "$first_owner"
fi
done
}
print_horizontal_line() {
local len="${1:-60}"
printf "%${len}s\n" | tr " " "-"
}
print_2_col_row() {
local first_cell="$1"
local second_cell="$2"
local first_cell_width="${3:-$DEFAULT_FIRST_COL_WIDTH}"
local value_type="${DEFAULT_PRINT_VALUE_TYPE:-s}"
first_par_actual_width=${#first_cell}
if [ $first_par_actual_width -gt $DEFAULT_FIRST_COL_WIDTH ]; then
first_cell=${first_cell:0:$TRUNCATED_FIRST_COL_WIDTH}"..."
fi
printf "%-${first_cell_width}s |  %${value_type}\n" "$first_cell" "$second_cell"
}
print_3_col_row() {
local first_cell="$1"
local second_cell="$2"
local third_cell="$3"
local cell_width="${4:-$DEFAULT_FIRST_COL_WIDTH}"
printf "%-${cell_width}s |  %-${cell_width}s  |  %s\n" "$first_cell" "$second_cell" "$third_cell"
}
cm_err_maybe_die() {
local cm_output="$1"
local what_to_say="$2"
case "$cm_output" in
*"ERROR"*)
die "$what_to_say"
;;
esac
}
cm_err_maybe_break() {
local cm_output="$1"
case "$cm_output" in
*"ERROR"*)
return 1
;;
esac
return 0
}
die() {
echo "$@" >&2
exit 1
}
calc_max_strlength() {
local len=0 str sl
for str; do
sl=${#str}
[ $sl -gt $len ] && len=$sl
done
echo "$len"
}
dup_char() {
local cnt=$1
local ch=${2:-"-"}
while [ $cnt -ne 0 ]; do
str="$ch$str"
cnt=$((cnt-1))
done
echo "$str"
}
print_line() {
local p1="$1"
local p2="$2"
local c1="${3:-25}"
local c2="${4:-15}"
if [ -z "$p1" -a -z "$p2" ]; then
printf "|%-${c1}s|%-${c2}s|\n" "$(dup_char $c1)" "$(dup_char $c2)"
return
fi
if [ -z "$p2" ]; then
cmclient -v p2 GETV "$p1"
p1=${p1##*.}
p1=${p1##*X_ADB_}
fi
printf "|%-${c1}s|%-${c2}s|\n" "$p1" "$p2"
}
if_under_bridge()
{
local tr_device=$1
local bridge
cmclient -v bridge GETO "Device.Bridging.Bridge.*.Port.[LowerLayers=$tr_device]"
[ -n "$bridge" ] && return 0 || return 1
}
replace_separator_in_list() {
local origin_list="$1"
local new_separator="$2"
local old_separator="$3"
local updated_list=""
local each_elem=""
[ "$new_separator" = "$old_separator" -o -z "$origin_list" ] && return 1
set -f
[ -n "$old_separator" ] && IFS=$old_separator
set -- $origin_list
[ -n "$old_separator" ] && unset IFS
set +f
for each_elem; do
updated_list="$updated_list$new_separator$each_elem"
done
updated_list=${updated_list#$new_separator}
echo "$updated_list"
}
is_eth_link_required() {
local ll="$1"
case "$ll" in
*"Ethernet.Interface"* | *"Bridging.Bridge"* | *"PTM.Link"* | *"WiFi.SSID"*)
return 0
;;
*"ATM.Link"* )
if [ "EoA" = `cmclient GETV $ll.LinkType` ]; then
return 0
fi
;;
esac
return 1
}
interface_add_on_top() {
local ifname="$1"
local ll="$2"
local alias_name="$3"
local idx
local obj
local setm=""
if [ -n "$alias_name" ]; then
cmclient -v idx ADD "$ifname.[Alias=$alias_name]" > /dev/null 2>&1
else
cmclient -v idx ADD "$ifname" > /dev/null 2>&1
fi
obj="$ifname.$idx"
if is_eth_link_required "$ll"; then
ll=`iface_create_ethernet_link "$ll"`
fi
local new_list="$(handle_list_actions $obj.LowerLayers add $ll)"
cmclient SETM "$new_list" > /dev/null 2>&1
cmclient -v is_ll_bridge GETO "$ll.[LowerLayers>Device.Bridging.Bridge]"
[ -n "$is_ll_bridge" ] && setm=${setm:+$setm	}$ll.Enable=true
setm=${setm:+$setm	}$obj.Enable=true
cmclient SETM "$setm" > /dev/null 2>&1
echo "$obj"
}
ip_interface_add() {
local ll="$1"
local alias_name="$2"
case "$ll" in
"Device.Bridging.Bridge"* )
cmclient -v ll GETO "$ll.Port.[ManagementPort=true]"
;;
esac
interface_add_on_top "Device.IP.Interface" "$ll" "$alias_name"
}
ppp_interface_add() {
local ll="$1"
local alias_name="$2"
interface_add_on_top "Device.PPP.Interface" "$ll" "$alias_name"
}
ipInterface() {
ip_interface=`cmclient GETO "Device.IP.Interface.*.[LowerLayers=$ll]"`
if [ -z "$ip_interface" ]; then
if [ "$adding" = "true" ]; then
idx=`cmclient ADD Device.IP.Interface`
if [ -z "$idx" ]; then
echo "Can't add IP.Interface for $ifname"
exit 1
fi
cmclient SET Device.IP.Interface.$idx.Name $ifname
cmclient SET Device.IP.Interface.$idx.Enable true
cmclient SET Device.IP.Interface.$idx.LowerLayers $ll
ip_interface=`echo Device.IP.Interface.$idx`
else
echo "--- ip interface for $ifname not found"
ll=""
[ "$dontexit" = "true" ] || exit
fi
fi
}
cli_get_sylog() {
local component="$1"
local level="$2"
/sbin/logc t 0 0 0 0 0 \"%h:%m:%s [%t]: %g%n\" "${component}"*"${level}"
}
get_ip_obj_from_eth_link() {
local ip_obj
local link_obj
cmclient -v link_obj GETO "Device.Ethernet.Link.*.[LowerLayers,$1]"
for arg_obj in $link_obj
do
cmclient -v ip_obj GETO "Device.IP.Interface.*.[LowerLayers,$arg_obj]"
if [ -n "$ip_obj" ]; then
echo "$ip_obj"
return
fi
done
}
ll_obj_to_ip_obj() {
local dev_obj="$1"
local ip_obj=""
local link_obj arg_obj
local br_port
if ! is_eth_link_required "$dev_obj"; then
cmclient -v ip_obj GETO "Device.IP.Interface.*.[LowerLayers,$dev_obj]"
else
case "$dev_obj" in
"Device.Bridging.Bridge"* )
cmclient -v br_port GETO "$dev_obj.Port.[ManagementPort=true]"
ip_obj=`get_ip_obj_from_eth_link $br_port`
;;
"Device.Ethernet.Interface"* )
ip_obj=`get_ip_obj_from_eth_link $dev_obj`
;;
"Device.ATM.Link"* | "Device.PTM.Link"* | "Device.WiFi.SSID"* )
cmclient -v ip_obj GETO "Device.IP.Interface.*.[LowerLayers=$dev_obj]"
[ -z "$ip_obj" ] && ip_obj=`get_ip_obj_from_eth_link $dev_obj`
;;
esac
fi
echo "$ip_obj"
}
ll_obj_to_ip_obj_ex() {
local ip_obj
ip_obj=`ll_obj_to_ip_obj "$@"`
echo "$ip_obj"
}
ascii2hex() {
wepkey=$1
i=1
hex=""
while [ "$i" -le "${#wepkey}" ]; do
char=$(expr substr "$wepkey" $i 1)
hexchar=`printf %02x "'$char"`
hex=$hex$hexchar
i=$((i+1))
done
echo "$hex"
}
list_exclude() {
local current_list="$1"
shift
local allowed="$@"
for i in $allowed; do
if ! help_is_in_list "$current_list" "$i"; then
echo "$i"
fi
done
}
list_print() {
local l="$1"
set -f; IFS=","; set -- $l; unset IFS; set +f
for i; do
echo "$i"
done
}
list_to_comma_sep() {
local list i
for i in $@; do
list="${list:+$list,}$i"
done
echo "$list"
}
generic_merge_lists() {
local lists="$@"
local list_all=""
local list_curr
local list_obj
local list_entry
for list_obj in $lists; do
cmclient -v list_curr GETV "$list_obj"
set -f; IFS=","; set -- $list_curr; unset IFS; set +f
for list_entry; do
[ -n "$list_entry" ] || continue
help_item_add_uniq_in_list list_all "$list_all" "$list_entry"
done
done
echo "$list_all"
}
forwarding_policy_is_free() {
local fp="$1"
local this
for this in \
"Device.Routing.Router.IPv4Forwarding.[ForwardingPolicy=$fp]" \
"Device.NAT.InterfaceSetting.[X_ADB_ForwardingPolicy=$fp]" \
"Device.NAT.PortMapping.[X_ADB_ForwardingPolicy=$fp]"; do
cmclient -v this GETO "$this"
[ -n "$this" ] && return 1
done
return 0
}
forwarding_policy_get_free() {
local this
local list="$1 `seq 1 1 256`"
for this in $list; do
forwarding_policy_is_free "$this" && echo "$this" && return 0
done
return 1
}
show_split_text() {
local this="$1"
local that="$2"
this="$(sed -e 's/\./ /g' -e 's/VoIP/VOIP/g' -e 's/QoS/QOS/g' -e 's/^X_ADB_//' -e 's/\([a-z]\)\([A-Z][a-z]\{2,\}\)/\1 \2/g' -e 's|\([a-z]\)\([A-Z]\)|\1 \2|g' -e 's|\([A-Z][A-Z]\)\([A-Z][a-z]\)|\1  \2|g' -e 's/[ ]*/ /g' -e 's/^ //' <<EOF
$this
EOF
)"
that="$(sed -e 's/X_ADB_//g' <<EOF
$that
EOF
)"
print_2_col_row "$this" "$that"
}
show_from_cm() {
local obj="$1"
local obj_prop="$2"
local strip_prefix="$3"
local value=""
local obj_prop_val=""
cmclient -v obj_prop_val GET "${obj}.${obj_prop}"
[ -n "${obj_prop_val}" ] && value="${obj_prop_val#*;}" || return
[ -n "${strip_prefix}" ] && value="${value##$strip_prefix}"
show_split_text "$obj_prop" "$value"
}
show_full_ip_possibly_excluded() {
local obj="$1"
local obj_prop="$2"
local value=""
cmclient -v value GETV "${obj}.${obj_prop}IP"
if [ "$value" != "" ]; then
cmclient -v mask GETV "${obj}.${obj_prop}Mask"
widthmask=$(ipv4_mask2prefix $mask)
cmclient -v is_exl GETV "${obj}.${obj_prop}IPExclude"
[ "$is_exl" = "true" ] && value="$value/$widthmask exclude" || value="$value/$widthmask"
fi
echo -n "$value"
}
show_portrange_possibly_excluded() {
local obj="$1"
local obj_prop="$2"
local value=""
cmclient -v value GETV "${obj}.${obj_prop}"
[ "$value" = "-1" ] && value="Any"
if [ "$value" != "Any" -a "$value" != "" ]; then
cmclient -v rangemax GETV "${obj}.${obj_prop}RangeMax"
[ "$rangemax" = "-1" ] && rangemax="" || rangemax=" - $rangemax"
cmclient -v is_exl GETV "${obj}.${obj_prop}Exclude"
[ "$is_exl" = "true" ] && value="$value$rangemax exclude" || value="$value$rangemax"
fi
echo -n "$value"
}
show_interface_possibly_excluded() {
local obj="$1"
local par="$2"
cmclient -v all_ifs GETV "${obj}.${par}AllInterfaces"
if [ "$all_ifs" = "true" ]; then
val="All"
else
cmclient -v val GETV "${obj}.${par}Interface"
[ "$val" = "X_ADB_Local" ] && val="local" || val="$(cmclient GETV ${val%%.Port.*}.Alias)"
val=$(echo "$val" | sed 's/ /\\ /g')
fi
if [ -n "$val" ]; then
cmclient -v ex GETV "${obj}.${par}InterfaceExclude"
[ "$ex" = "true" ] && val="$val exclude"
fi
echo -n "$val"
}
set_ip_with_prefix_possibly_excluded()
{
local obj=$1
local par=$2
local addr_cidr=$3
local exclude=$4
local prefix=${addr_cidr#*/}
local mask="$(ipv4_prefix2mask $prefix)"
local address=${addr_cidr%/*}
. /etc/clish/quick_cm.sh set "${obj}" "${par}IP" "$address"
. /etc/clish/quick_cm.sh set "${obj}" "${par}Mask" "$mask"
[ -n "${exclude}" ] && excl="true" || excl="false"
. /etc/clish/quick_cm.sh set "${obj}" "${par}IPExclude" "$excl"
}
set_interface_possibly_excluded() {
obj="$1"
source_dest="$2"
ifname="$3"
exclude="$4"
case "${ifname}" in
All)
setm="${obj}.${source_dest}AllInterfaces=true	${obj}.${source_dest}Interface="
;;
*)
setm="${obj}.${source_dest}AllInterfaces=false	${obj}.${source_dest}Interface=${ifname}"
;;
esac
cmclient -v result SETM "$setm" >/dev/null 2>&1
[ -n "${exclude}" ] && excl=true || excl=false
cmclient SET "${obj}.${source_dest}InterfaceExclude $excl" >/dev/null 2>&1
}
ipv4_prefix2mask ()
{
set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
[ $1 -gt 1 ] && shift $1 || shift
echo ${1-0}.${2-0}.${3-0}.${4-0}
}
ipv4_mask2prefix ()
{
set -- 0^^^128^192^224^240^248^252^254^ ${#1} ${1##*255.}
set -- $(( ($2 - ${#3})*2 )) ${1%%${3%%.*}*}
echo $(( $1 + (${#2}/4) ))
}
get_low_level(){
local next="$1"
local prev
while [ -n "$next" ]; do
prev="$next"
[ -z "${prev##Device.Bridging.*}" ] && return 0
cmclient -v next GETV "${prev%%,*}.LowerLayers"
done
echo "$prev"
}
is_lowlevel_upstream(){
local this="$1"
local low
low="$(get_low_level $this)"
if [ -n "$low" ]; then
local flag
cmclient -v flag GETV "$low.Upstream"
[ "$flag" = "true" ] && return 0 || return 1
else
return 1
fi
}
neigh_disc_on_iface_validate() {
local ip_objs ip_obj
if [ "$1" != "all" ]; then
local ip_objs="$(ll_obj_to_ip_obj $(cli_to_tr $1))"
[ -z "$ip_objs" ] && die "ERROR: No IPv6 address is assigned for $1"
cmclient -v ip_obj GETO "Device.NeighborDiscovery.InterfaceSetting.*.[Interface=$ip_objs]"
[ -n "$ip_obj" ] && ip_objs=""
else
local i
cmclient -v ip_objs GETO "Device.IP.Interface"
cmclient -v ip_obj GETV "Device.NeighborDiscovery.InterfaceSetting.*.Interface"
for i in $ip_obj; do
case "$ip_objs" in
*"$i"* )
;;
* )
cmclient DEL "Device.NeighborDiscovery.InterfaceSetting.*.[Interface=$i]" > /dev/null
;;
esac
done
set -- $ip_objs
ip_objs=""
for i; do
case "$ip_obj" in
*"$i"* )
;;
* )
ip_objs="${ip_objs:+$ip_objs }$i"
;;
esac
done
fi
local new_object local_ipv6_enable global_ipv6_enable
for ip_obj in $ip_objs; do
cmclient -v new_object ADD "Device.NeighborDiscovery.InterfaceSetting"
cm_err_maybe_break || continue
new_object="Device.NeighborDiscovery.InterfaceSetting.$new_object"
cmclient SET "$new_object.Interface" "$ip_obj" > /dev/null
cmclient -v local_ipv6_enable GET "Device.IP.IPv6Enable"
cmclient -v global_ipv6_enable GET "$ip_obj.IPv6Enable"
[ "$local_ipv6_enable" = "true" -a "$global_ipv6_enable" = "true" ] && \
cmclient SET "$new_object.Enable" "true" > /dev/null
done
return 0
}
cli_or_tr_alias_to_tr_obj(){
case "$1" in
Device.*)
cmclient GETO "$@"
;;
*)
cli_to_tr "$1"
;;
esac
}
cli_with_param_to_tr(){
case "$1" in
Device.*)
echo "$1"
;;
*)
local cli_id="${1%%.[^0-9]*}"
echo "$(cli_to_tr $cli_id)${1#$cli_id}"
;;
esac
}
gui_to_cli_label_conversion() {
local gui_label="$1"
echo $(help_lowercase $(help_str_replace_all " " "_" "$gui_label"))
}
is_ipv6_enabled_maybe_die() {
local enabled
cmclient -v enabled GETV "Device.IP.IPv6Enable"
[ "$enabled" = "false" ] && die "WARNING: please, enable IPv6."
return 0
}
show_from_cm_interface(){
local this="${1}"
local that="${2}"
[ -z "${that}" ] && that="${this##*.}"
cmclient -v this GETV "${this}"
if [ -n "${this}" ]; then
cmclient -v value GETV "${this}.Alias"
show_split_text "${that}" "${value}"
else
show_split_text "${that}" ""
fi
}
size_to_human_format(){
awk -v bytes="${1}" -f - << EOF
BEGIN {
split("B KB MB GB TB PB", type);
if (int(bytes) > 0) {
for(i = 5; y < 1; i--){
y = bytes / (2**(10*i))
}
printf "%.2f%s\n", y, type[i+2];
}
else {
printf "0B\n";
}
}
EOF
}
show_deref_list()
{
local list_par="$1"
local par_to_show="$2"
local add_prefix="$3"
local prefix=""
local objs=""
local o=""
local a=""
local values=""
cmclient -v objs GETV "${list_par}"
set -f; IFS=","; set -- $objs; unset IFS; set +f
for o; do
cmclient -v a GETV $o.$par_to_show
if [ "$add_prefix" = true ]; then
prefix=${o#Device.}
prefix=${prefix%%.*}.
fi
values="${values}$prefix$a\n"
done
printf "$values"
}
show_deref_list_as_list()
{
local list_par="$1"
local par_to_show="$2"
local add_prefix="$3"
local prefix=""
local objs=""
local o=""
local a=""
local values=""
cmclient -v objs GETV "${list_par}"
set -f; IFS=","; set -- $objs; unset IFS; set +f
for o; do
cmclient -v a GETV $o.$par_to_show
if [ "$add_prefix" = true ]; then
	case $o in
Device.Bridging.Bridge*)
prefix=${o#*"Device.Bridging.Bridge."}
prefix=${prefix%%"."*}
prefix="Bridge.$prefix."
;;
*)
prefix=${o#*"Device."}
prefix=${prefix%%"."*}
prefix="$prefix."
;;
esac
fi
if [ -z "$values" ]; then
values="$prefix$a";
else
values="${values},$prefix$a"
fi
done
case "$values" in
*\ *)
values=\"$values\"
;;
esac
printf "$values"
}
show_deref_list_runconf()
{
local list_reference=$1 only_first=$2
cmclient -v ifaces GETV $list_reference
set -f; IFS=","; set -- $ifaces; unset IFS; set +f
for l; do
cmclient -v o GETV $l.Alias
l=${l#Device.}
l=${l#X_ADB_}
l=${l%%.*}
val="${val:+$val,}$l.$o"
[ "$only_first" = "true" ] && break
done
[ -n "$val" ] && echo -n "\"$val\""
}
show_single_entry() {
local obj="$1"
local name="$2"
local params_to_script="$3"
case "$name" in
*::*)
first=${name%%::*}
second=${name#*::}
second=${second%%::*}
second=$(sed 's/\\//g; s/^;*//g' <<EOF
$second
EOF
)
if [ ${#params_to_script} -eq 0 ]; then
sec=$(eval "$second")
else
sec=$(eval "$second" "$obj" "$first")
fi
show_split_text "$first" "$sec"
;;
*)
show_from_cm "$obj" $name
;;
esac
}
show_object() {
local obj=$1
local display_params="$2"
local show_all_except="$3"
local params_to_script=$4
local comma_replacement="\^\^\^\^\^"
local newline_replacement="\&\&\&\&\&"
print_horizontal_line
escaped_display_params=$(sed "s/\\\,/$comma_replacement/g" <<-EOF
$display_params
EOF
)
if [ "$show_all_except" = "yes" ] ; then
nospace_display_params=$(sed 's/,[ ]*/,/g; s/[ ]*::/::/g; s/^[ ]*//g' <<-EOF
$escaped_display_params
EOF
)
nonewline_display_params=$(tr '\n' ';' <<-EOF | sed -e "s/\\([^\\]\\);/\\1$newline_replacement/g"
$escaped_display_params
EOF
)
cmclient -v contents GETN $obj. 0
for name in $contents ; do
obj_ext=${name%.*}
name=${name##*.}
case ,$nospace_display_params, in
*,"$name"::*)
name=$(sed -e "s/.*,[ ]*\($name[ ]*::.*\)/\1/" \
-e 's/,.*//' \
-e 's/::\(.*\)::.*/::\1/' \
-e "s/$comma_replacement/,/g" \
-e "s/$newline_replacement/\n/g" <<-EOF
,$nonewline_display_params
EOF
)
;;
*,"$name",*)
name=""
;;
*)
;;
esac
[ -n "$name" ] && show_single_entry "$obj_ext" "$name" "$params_to_script"
done
else
while [ "$escaped_display_params" ] ; do
name=${escaped_display_params%%,*}
escaped_display_params=${escaped_display_params#*,}
[ "$escaped_display_params" = "$name" ] && escaped_display_params=
name=$(echo "$name" | sed "s/$comma_replacement/,/g")
show_single_entry "$obj" "$name" "$params_to_script"
done
fi
print_horizontal_line
}
show_all_child_objects() {
local child_objects
local obj
local disp_entry="$2"
cmclient -v child_objects GETO "$1"
if [ -n "$2" -a "$4" = "true" ]; then
for obj in $child_objects; do
disp_entry=$(echo "$2" | sed "s/$1.%d/$obj/g")
show_object "$obj" "$disp_entry" "$3"
done
else
for obj in $child_objects; do
show_object "$obj" "$disp_entry" "$3"
done
fi
}
var_runconf_classIndex() {
local classIndexPath="$1"
local completionRoutine="$2"
local skipMatching=${3:-true}
local found_entry=""
local classIndex
local val
cmclient -v classIndex GETV $classIndexPath
if [ "$skipMatching" = "false" ]; then
available_policies="$(. /etc/clish/completion.sh $completionRoutine)"
found_entry=""
set -f;IFS=$'\n';set -- $available_policies;unset IFS;set +f
for policy; do
found_prefix=${policy%%\[*}
found_prefix=${found_prefix#\"}
case ,"$classIndex", in
*,"$found_prefix",*)
stripped_policy=${policy%\(*}
[ -z "$found_entry" ] && found_entry=${stripped_policy#\"} || found_entry="$found_entry,"${stripped_policy#\"}
help_remove_from_unique_list classIndex "$classIndex" "$found_prefix"
;;
esac
done
fi
if [ -n "$classIndex" ]; then
classIndex="$classIndex,"
while [ -n "$classIndex" ]; do
val=${classIndex%%","*}
if [ "$val" != -1 -a "$val" != 0 -a "$val" != "" ]; then
[ -z "$found_entry" ] && found_entry="new $val" || found_entry="$found_entry,new $val"
fi
classIndex=${classIndex#*","}
done
fi
echo -n $found_entry
}
validate_list_against_list() {
local ref_list=$1
if [ -n $ref_list ]; then
ref_list=","$ref_list","
else
return
fi
local ref_list_len=${#ref_list}
local list_to_check=${2//,/ }
local out_list=""
for elem in $list_to_check;
do
out_list=${out_list/;$elem;/}
test=${ref_list/,$elem,/}
[ ${#test} -lt $ref_list_len ] && out_list="$out_list;$elem;"
done
out_list=${out_list##;}
out_list=${out_list%%;}
echo ${out_list//;;/,}
}
rem_LowerLayers() {
local object=$1
local ll=$2
local newLL=""
local new_list right_side
if [ -n "$ll" ]; then
new_list="$(handle_list_actions ${object}.LowerLayers list_del ${ll})"
right_side=${new_list#*=}
if [ -n "$right_side" ]; then
newLL=$right_side
fi
cmclient -v dummy SET ${object}.LowerLayers "$newLL"
fi
}
add_LowerLayers() {
local object=$1
local ll_to_add=$2
local oldLL newLL
cmclient -v oldLL GETV "$object.LowerLayers"
if [ -n "$oldLL" ]; then
newLL="$oldLL,$ll_to_add"
else
newLL=$ll_to_add
fi
cmclient -v dummy SET ${object}.LowerLayers "$newLL"
}
remove_shortest_substring_from_back() {
local string="$1"
local pattern="$2"
local result=""
result=${string%"$pattern"}
echo "$result"
}
