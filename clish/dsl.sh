#!/bin/sh
. /etc/clish/clish-commons.sh
obj=""
obj_list=""
cell_width="25"
cell_width2="15"
line_lenght="70"
print_param() {
local var=""
cmclient -v var GETV "$obj.$2"
print_2_col_row "$1" "$var" "$cell_width"
}
print_convert_param() {
local var=""
cmclient -v var GETV "$obj.$2"
var="$(eval $3 $(list_print $var))"
print_2_col_row "$1" "$(list_to_comma_sep $var)" "$cell_width"
}
print_bool_param() {
local var=""
local b_var="false"
cmclient -v var GETV "$obj.$2"
[ -n "$var" ] && [ "$var" -gt "0" ] && b_var="true"
print_2_col_row "$1" "$b_var" "$cell_width"
}
print_table() {
local var1=""
local var2=""
cmclient -v var1 GETV "$obj.$2"
cmclient -v var2 GETV "$obj.$3"
printf "%-${cell_width}s |  %-${cell_width2}s |  %s\n" "$1" "$var1" "$var2"
}
standarts_list="
ADSL_Lite/G.Lite  G.992.2
ADSL/G.DMT        G.992.1_Annex_A
ADSL2             G.992.3_Annex_A
Re-ADSL2_Annex_L  G.992.3_Annex_L
ADSL2+            G.992.5_Annex_A
ADSL2+_Annex_M    G.992.5_Annex_M
VDSL2             G.993.2_Annex_A
ADSL_over_ISDN    G.992.1_Annex_B
ADSL2_over_ISDN   G.992.3_Annex_B
ADSL2+_over_ISDN  G.992.5_Annex_B
VDSL2_Annex_B     G.993.2_Annex_B
"
name_to_standart() {
local var
for var; do
[ -z "$var" ] && continue
local t="${standarts_list#*$var}"
if [ "$t" != "$standarts_list" ]; then
set -- $t
var="$1"
fi
echo "$var"
done
}
standart_to_name() {
local var
for var; do
[ -z "$var" ] && continue
local t=${standarts_list%%$var*}
if [ "$t" != "$standarts_list" ]; then
set -- $t
eval var="\$${#}"
fi
echo "$var"
done
}
show_line() {
cmclient -v line_alias GETV "$obj.Alias"
printf "\n"
print_2_col_row "DSL line" "$line_alias" "$cell_width"
print_horizontal_line "$line_lenght"
print_param "Enable" "Enable"
print_param "Status" "Status"
print_param "Name" "Name"
print_param "Upstream" "Upstream"
print_param "Firmware version" "FirmwareVersion"
print_param "Link status" "LinkStatus"
print_convert_param "Allowed standards" "X_ADB_AllowedStandards" "standart_to_name"
print_convert_param "Standard" "StandardUsed" "standart_to_name"
print_param "Allowed VDSL2 Profiles" "AllowedProfiles"
print_bool_param "SRA" "X_ADB_SRA"
print_bool_param "BitSwap" "X_ADB_BitSwap"
print_bool_param "Trellis downstream" "TRELLISds"
print_bool_param "Trellis upstream" "TRELLISus"
print_param "Line number" "LineNumber"
print_param "Upstream max bit rate" "UpstreamMaxBitRate"
print_param "Downstream max bit rate" "DownstreamMaxBitRate"
print_param "Upstream noise margin" "UpstreamNoiseMargin"
print_param "Downstream noise margin" "DownstreamNoiseMargin"
print_param "Upstream attenuation" "UpstreamAttenuation"
print_param "Downstream attenuation" "DownstreamAttenuation"
print_param "Upstream power" "UpstreamPower"
print_param "Downstream power" "DownstreamPower"
print_horizontal_line "$line_lenght"
printf "\n"
}
show_line_stats() {
printf "\nDSL statistics:\n"
print_horizontal_line "$line_lenght"
print_param "Bytes sent" "BytesSent"
print_param "Bytes received" "BytesReceived"
print_param "Packets sent" "PacketsSent"
print_param "Packets received" "PacketsReceived"
print_param "Errors sent" "ErrorsSent"
print_param "Errors received" "ErrorsReceived"
print_param "Total start" "TotalStart"
print_param "Show time start" "ShowtimeStart"
print_param "Last show time start" "LastShowtimeStart"
print_param "Current day start" "CurrentDayStart"
print_param "Quarter hour start" "QuarterHourStart"
print_horizontal_line "$line_lenght"
}
show_line_stats_total() {
print_table "Total" "ErroredSecs" "SeverelyErroredSecs"
}
show_line_stats_showtime() {
print_table "Show time" "ErroredSecs" "SeverelyErroredSecs"
}
show_line_stats_last_showtime() {
print_param "Errored secs" "ErroredSecs"
print_param "Severely errored secs" "SeverelyErroredSecs"
}
show_line_stats_current_day() {
print_table "Current Day" "ErroredSecs" "SeverelyErroredSecs"
}
show_line_stats_quarter_hour() {
print_table "Quarter hour" "ErroredSecs" "SeverelyErroredSecs"
}
show_line_all_stats() {
local tmp_obj="$obj"
cmclient -v obj GETO "$tmp_obj.Stats"
[ -n "$obj" ] && show_line_stats
printf "\nError statistics:\n"
print_horizontal_line "$line_lenght"
printf "%-${cell_width}s |  %-${cell_width2}s |  %s\n" "Period" "Errored secs" "Severely errored secs"
print_horizontal_line "$line_lenght"
cmclient -v obj GETO "$tmp_obj.Stats.Total"
[ -n "$obj" ] && show_line_stats_total
cmclient -v obj GETO "$tmp_obj.Stats.Showtime"
[ -n "$obj" ] && show_line_stats_showtime
cmclient -v obj GETO "$tmp_obj.Stats.CurrentDay"
[ -n "$obj" ] && show_line_stats_current_day
cmclient -v obj GETO "$tmp_obj.Stats.QuarterHour"
[ -n "$obj" ] && show_line_stats_quarter_hour
print_horizontal_line "$line_lenght"
printf "\n"
obj="$tmp_obj"
}
init_obj() {
if [ "$2" = "all" ]; then
cmclient -v obj_list GETO "Device.DSL.$1"
elif [ -n "$2" ]; then
obj=$(cli_or_tr_alias_to_tr_obj "$2")
cmclient -v obj GETO "$obj"
obj_list="$obj"
else
obj_list=""
obj=""
fi
[ -z "${obj_list}" ] && printf "no dls interface(s)" && exit
}
show() {
init_obj "Line" "$1"
for obj in $obj_list; do
[ -n "$2" ] && eval "$2"
[ -n "$3" ] && eval "$3"
done
}
trellis() {
local setm=""
init_obj "" "$1"
setm="$obj.TRELLISds=$2	$obj.TRELLISus=$2"
cm_err_maybe_die "`cmclient SETM \"$setm\"`" "ERROR: failed to execute trellis"
}
print_mode() {
local mode_val list
init_obj "" "$1"
cmclient -v list GETV "$obj.X_ADB_AllowedStandards"
list=$(list_print $list)
for i in $list; do
mode_val="${mode_val:+$mode_val,}$i"
done
if [ -z "$mode_val" ]; then
mode_val="Auto"
fi
echo "Mode=$mode_val"
}
do_profile() {
local command="$2" # <add> or <del>
local value="$3"
local setm vdsl_enable
init_obj "" "$1"
cmclient -v vdsl_enable GETV "$obj.X_ADB_AllowedStandards"
[ "$vdsl_enable" = "${vdsl_enable##*G.993}" ] && die "ERROR: Can't accomplish action. VDSL2 is not supported'"
setm="$(handle_list_actions $obj.AllowedProfiles $command $value)"
[ -n "$setm" ] && exec /etc/clish/quick_cm.sh "setm" "$setm"
}
case "$1" in
"all" )
show "all" "show_line" "show_line_all_stats" "DSL statistics"
;;
"config" )
show "$2" "show_line" ""
;;
"statistics" )
show "$2" "" "show_line_all_stats"
;;
"add_mode_list" )
show_add_mode_list "Line" "$ifname"
;;
"remove_mode_list" )
show_remove_mode_list "Line" "$2"
;;
"trellis" ) trellis "$2" "$3"
;;
"standart_to_name" ) standart_to_name $2
;;
"print_mode" ) print_mode "$2"
;;
"add_profile" | "del_profile" )
do_profile "$2" "${1%%_profile}" "$3"
;;
*) exec /etc/clish/quick_cm.sh "$1" "$2" "$3" "$4"
;;
esac
