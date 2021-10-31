#!/bin/sh
. /etc/clish/clish-commons.sh
PREDEF_NAMES_FILE="/tmp/predef_names"
tr_with_predef_names="
|Device.Ethernet.Interface|-|
|Device.DSL.Line|dsl:_1|
|Device.WiFi.Radio|radio:_1|
|Device.WiFi.SSID|::ssid_auto_name|
"
get_predef_names_tr_list() {
	local i tr_list
	for i in $tr_with_predef_names; do
		i=${i#|}
		i=${i%%|*}
		tr_list="${tr_list:+$tr_list }$i"
	done
	echo "$tr_list"
}
composing_automatic_names() {
	local tr_obj="$1"
	local tr_obj_type="${tr_obj%.*}"
	local tr_obj_index="${tr_obj#$tr_obj_type.}"
	local rule="${tr_with_predef_names#*|$tr_obj_type|}"
	rule="${rule%%|*}"
	case "${rule#*:}" in
	"_"*)
		local objs
		cmclient -v objs GETO "$tr_obj_type"
		if [ -n "${objs#$tr_obj}" ]; then
			echo "|$tr_obj|${rule%:*}$(($tr_obj_index - 1 + ${rule#*:_}))|"
		else
			echo "|$tr_obj|${rule%:*}|"
		fi
		;;
	":"*)
		local spec_function='$('"${rule#::}"' $tr_obj)'
		eval echo "$spec_function"
		;;
	"-")
		:
		;;
	*)
		echo "|$tr_obj|${rule%:*}$(($tr_obj_index - 1 + ${rule#*:}))|"
		;;
	esac
}
ssid_auto_name() {
	local tr_obj="$1"
	local ssid_index=0
	local radio_obj objs each_obj radio_obj_index
	cmclient -v radio_obj GETV "$tr_obj.LowerLayers"
	radio_obj_index="${radio_obj##*.}"
	cmclient -v objs GETO "${radio_obj%.*}"
	[ -z "${objs#$radio_obj}" ] && radio_obj_index=""
	cmclient -v objs GETO "Device.WiFi.SSID.*.[LowerLayers=$radio_obj]"
	for each_obj in $objs; do
		[ "$each_obj" = "$tr_obj" ] && break
		ssid_index=$(($ssid_index + 1))
	done
	[ "$ssid_index" = 0 ] && ssid_index="" || ssid_index=".$ssid_index"
	echo "|$tr_obj|wifi$radio_obj_index$ssid_index|"
}
if [ ! -f "$PREDEF_NAMES_FILE" ]; then
	touch "$PREDEF_NAMES_FILE"
	chmod 666 "$PREDEF_NAMES_FILE"
fi
for each_obj_list in $(get_predef_names_tr_list); do
	cmclient -v obj_list GETO "$each_obj_list"
	for each_obj in $obj_list; do
		cmclient -v obj_label GETV "$each_obj.X_ADB_Label"
		if [ -z "$obj_label" ]; then
			tmp_val=$(composing_automatic_names "$each_obj")
			[ -n "$tmp_val" ] && echo "$tmp_val"
		else
			echo "|$each_obj|"$(gui_to_cli_label_conversion "$obj_label")"|"
		fi
	done
done >$PREDEF_NAMES_FILE
