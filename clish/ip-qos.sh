#/bin/sh
. /etc/clish/clish-commons.sh
set_mac_addr_and_mask()
{
local obj="$1"
local mac_field="$2"
local mask_field="$3"
local input="$4"
local exclude_field="$5"
local exclude="$6"
local all_mac="$7"
local all_mask="$8"
local mac=""
local mask=""
local mac_with_mask=""
local setm=""
local tmp_mac
local valid
[ "$exclude_field" = "-" ] && exclude_field=""
[ "$exclude" != "true" ] && exclude="false"
if [ -n "$input" ]; then
set -f; IFS=","; set -- $input; unset IFS; set +f
for mac_with_mask; do
mask=${mac_with_mask#*"/"}
mac=${mac_with_mask%%"/"*}
[ "$mask" = "$mac" -a -n "$mask" ] && mask=""
[ -z "$mac" ] && die "Error validating MAC address with mask: $mac/$mask"
[ -n "$mask" -a -z "$mac" ] && die "Error validating MAC address with mask: $mac/$mask"
if ! help_is_in_list "$all_mac" "$mac"; then
if [ -z "$all_mask" -a -n "$mask" -a -n "$all_mac" ]; then
tmp_mac="$all_mac,"
while [ -n "$tmp_mac" ]; do
all_mask="$all_mask,"
tmp_mac=${tmp_mac#*","}
done
all_mac="$all_mac${all_mac:+,}$mac"
all_mask="$all_mask$mask"
else
all_mac="$all_mac${all_mac:+,}$mac"
all_mask="$all_mask${all_mask:+,}$mask"
fi
else
echo "Warning: Skipping MAC: $mac because it is already in list"
fi
done
fi
setm="$obj.$mac_field=$all_mac	$obj.$mask_field=$all_mask"
[ -n "$exclude_field" ] && setm="$setm	$obj.$exclude_field=$exclude"
. /etc/clish/quick_cm.sh setm "$setm"
}
add_mac_addr_and_mask()
{
local cur_mac=""
local cur_mask=""
cmclient -v cur_mac GETV "$1.$2"
cmclient -v cur_mask GETV "$1.$3"
set_mac_addr_and_mask "$1" "$2" "$3" "$4" "-" "-" "$cur_mac" "$cur_mask"
}
print_mac_addr_and_mask()
{
local cur_mac=""
local cur_mask=""
local cur_exclude
local show="$5"
local mac mask output
cmclient -v cur_mac GETV "$1.$2"
cmclient -v cur_mask GETV "$1.$3"
[ "x$4" != "x-" ] && cmclient -v cur_exclude GETV "$1.$4"
[ "$cur_exclude" = "true" ] && cur_exclude=" exclude" || cur_exclude=""
if [ -n "$cur_mac" ]; then
cur_mac="$cur_mac,"
cur_mask="$cur_mask,"
output=""
while [ -n "$cur_mac" ]; do
mac=${cur_mac%%","*}
mask=${cur_mask%%","*}
[ -z "$mask" ] && output="$output"${output:+,}"$mac" || output="$output"${output:+,}"$mac/$mask"
cur_mac=${cur_mac#*","}
cur_mask=${cur_mask#*","}
done
[ "$show" = "true" ] && echo "\"$output\"$cur_exclude" || echo -n "\"$output\"$cur_exclude"
else
[ "$show" = "true" ] && echo "\"\""
fi
}
del_mac_addr_and_mask()
{
local obj="$1"
local mac_field="$2"
local mask_field="$3"
local input="$4"
local type="$5"
local cur_mac=""
local cur_mask=""
local new_mac
local new_mask
local mac=""
local mask=""
local old_mac=""
local old_mask=""
local mac_with_mask=""
local setm=""
local mask_empty
local is_changed=0
cmclient -v cur_mac GETV "$1.$2"
cmclient -v cur_mask GETV "$1.$3"
[ -z "$cur_mask" ] && mask_empty=1 || mask_empty=0
[ ${#cur_mac} -eq 0 ] && die "Error: Address does not exist"
if [ -n "$input" ]; then
set -f; IFS=","; set -- $input; unset IFS; set +f
for mac_with_mask; do
[ -z "$cur_mac" ] && break;
mask=${mac_with_mask#*"/"}
mac=${mac_with_mask%%"/"*}
[ "$mask" = "$mac" -a -n "$mask" ] && mask=""
[ -z "$mac" ] && die "Error validating $type address with mask: $mac/$mask"
[ -n "$mask" -a -z "$mac" ] && die "Error validating $type address with mask: $mac/$mask"
new_mac=""
new_mask=""
cur_mac="$cur_mac,"
cur_mask="$cur_mask,"
while [ -n "$cur_mac" ]; do
old_mac=${cur_mac%%","*}
old_mask=${cur_mask%%","*}
if [ "$mac" != "$old_mac" ]; then
new_mac="$new_mac${new_mac:+,}$old_mac"
new_mask="$new_mask${new_mac:+,}$old_mask"
else
is_changed=1
fi
cur_mac=${cur_mac#*","}
cur_mask=${cur_mask#*","}
done
cur_mac="$new_mac"
cur_mask="$new_mask"
done
if [ "$is_changed" -eq 1 ]; then
[ -n "$cur_mask" -a "$mask_empty" -eq 1 ] && cur_mask=""
cur_mask=${cur_mask#*","}
setm="$obj.$mac_field=$cur_mac	$obj.$mask_field=$cur_mask"
. /etc/clish/quick_cm.sh setm "$setm"
fi
fi
}
print_wday_list()
{
local day_of_week_list
local output
cmclient -v day_of_week_list GETV "$1.$2"
if [ -n "$day_of_week_list" ]; then
day_of_week_list="$day_of_week_list,"
output=""
for i in `seq 1 7`
do
if help_is_in_list "$day_of_week_list" "$i"; then
case $i in
1) output="$output${output:+,}Monday" ;;
2) output="$output${output:+,}Tuesday" ;;
3) output="$output${output:+,}Wednesday" ;;
4) output="$output${output:+,}Thrusday" ;;
5) output="$output${output:+,}Friday" ;;
6) output="$output${output:+,}Saturday" ;;
7) output="$output${output:+,}Sunday" ;;
esac
fi
done
[ "$3" = "true" ] && echo "$output" || echo -n "$output"
fi
}
set_wday_list()
{
local output=""
local idx=1
for i in Monday Tuesday Wednesday Thrusday Friday Saturday Sunday;
do
if help_is_in_list "$3" "$i"; then
output="$output${output:+,}$idx"
fi
idx=$((idx+1))
done
. /etc/clish/quick_cm.sh setm "$1.$2=$output"
}
quess_ip_ver() {
local input="$1"
local tmp="${input#*:}"
if [ "$tmp" = "$input" ]; then
tmp=${tmp#*.}
if [ "$tmp" = "$input" ]; then
return 0
else
return 4
fi
fi
return 6
}
set_ip_addr_and_mask() {
local obj="$1"
local addr_field="$2"
local mask_field="$3"
local input="$4"
local exclude_field="$5"
local exclude="$6"
local all_addr="$7"
local all_mask="$8"
local addr_type
local addr_with_mask
local addr
local mask
[ "$exclude_field" = "-" ] && exclude_field=""
[ "$exclude" != "true" ] && exclude="false"
if [ -n "$input" ]; then
set -f; IFS=","; set -- $input; unset IFS; set +f
for addr_with_mask; do
mask=${addr_with_mask#*"/"}
addr=${addr_with_mask%%"/"*}
[ "$mask" = "$addr" -a -n "$mask" ] && mask=""
[ -z "$addr" ] && die "Error validating IP address with mask: $addr/$mask"
[ -n "$mask" -a -z "$addr" ] && die "Error validating IP address with mask: $addr/$mask"
if [ -z "$addr_type" ]; then
quess_ip_ver "$addr"
addr_type=$?
[ $addr_type -eq 0 ] && die "Error determining IP address version: $addr/$mask"
else
quess_ip_ver "$addr"
[ $? -ne $addr_type ] && die "IP addresses version mismatch: $addr/$mask (expected ipv$addr_type)"
fi
if ! help_is_in_list "$all_addr" "$addr"; then
if [ -z "$all_mask" -a -n "$mask" -a -n "$all_addr" ]; then
tmp_mac="$all_addr,"
while [ -n "$tmp_mac" ]; do
all_mask="$all_mask,"
tmp_mac=${tmp_mac#*","}
done
all_addr="$all_addr${all_addr:+,}$addr"
all_mask="$all_mask$mask"
else
all_addr="$all_addr${all_addr:+,}$addr"
all_mask="$all_mask${all_mask:+,}$mask"
fi
else
echo "Warning: Skipping IP: $addr because it is already in list"
fi
done
fi
setm="$obj.$addr_field=$all_addr	$obj.$mask_field=$all_mask"
[ -n "$exclude_field" ] && setm="$setm	$obj.$exclude_field=$exclude"
. /etc/clish/quick_cm.sh setm "$setm"
}
add_ip_addr_and_mask() {
local cur_addr=""
local cur_mask=""
local addr_type
local list_type
cmclient -v cur_addr GETV "$1.$2"
cmclient -v cur_mask GETV "$1.$3"
if [ -n "$cur_addr" ]; then
quess_ip_ver "$4"
addr_type=$?
quess_ip_ver "$cur_addr"
list_type=$?
[ $list_type -ne $addr_type -o $list_type -eq 0 -o $addr_type -eq 0 ] && die "Error: Attempt to add incompatiblie address to addresses list (got: ipv$addr_type, expected: ipv$list_type)"
fi
set_ip_addr_and_mask "$1" "$2" "$3" "$4" "-" "-" "$cur_addr" "$cur_mask"
}
case "$1" in
"set_mac_addr_and_mask" )
set_mac_addr_and_mask "$2" "$3" "$4" "$5" "$6" "$7"
;;
"add_mac_addr_and_mask" )
add_mac_addr_and_mask "$2" "$3" "$4" "$5"
;;
"del_mac_addr_and_mask" )
del_mac_addr_and_mask "$2" "$3" "$4" "$5" "MAC"
;;
"print_mac_addr_and_mask" )
print_mac_addr_and_mask "$2" "$3" "$4" "$5" "$6"
;;
"print_wday_list" )
print_wday_list "$2" "$3" "$4"
;;
"set_wday_list" )
set_wday_list "$2" "$3" "$4"
;;
"set_ip_addr_and_mask" )
set_ip_addr_and_mask "$2" "$3" "$4" "$5" "$6" "$7"
;;
"add_ip_addr_and_mask" )
add_ip_addr_and_mask "$2" "$3" "$4" "$5"
;;
"del_ip_addr_and_mask" )
del_mac_addr_and_mask "$2" "$3" "$4" "$5" "IP"
;;
"print_ip_addr_and_mask" )
print_mac_addr_and_mask "$2" "$3" "$4" "$5" "$6"
;;
* )
die "Wrong parameters"
;;
esac
