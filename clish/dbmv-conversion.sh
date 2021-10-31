#!/bin/sh
convert_param_value_to_dbmV() {
	local object="$1" param="$2" part_before_comma part_after_comma result=""
	cmclient -v value GETV "$object.$param"
	if [ ${#value} -ne 0 ]; then
		if [ $value -lt 0 ]; then
			value=${value#-}
			result="-"
		fi
		part_before_comma=$(($value / 10))
		part_after_comma=$(($value - (($value / 10) * 10)))
		result="$result$part_before_comma.$part_after_comma"
	fi
	echo "$result"
}
convert_param_value_to_dbmV "$@"
