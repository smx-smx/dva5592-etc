#!/bin/sh
AH_NAME="MemoryStatus"
[ "$user" = "${AH_NAME}${obj}" -o "$changedStandardUsed" = 1 ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize >/dev/null
service_get() {
	get_path="$1"
	case "$get_path" in
	*"MemoryStatus.Total")
		echo $mem_total
		;;
	*"MemoryStatus.Free")
		echo $((mem_free + mem_buffers + mem_cached))
		;;
	*"MemoryStatus.X_ADB_SwapTotal")
		echo $mem_swaptotal
		;;
	*"MemoryStatus.X_ADB_SwapFree")
		echo $mem_swapfree
		;;
	*)
		echo ""
		;;
	esac
}
get_mem_info() {
	local section data
	set -f
	while IFS=" " read -r section data _; do
		case "$section" in
		"MemTotal:")
			mem_total=${data}
			;;
		"MemFree:")
			mem_free=${data}
			;;
		"Buffers:")
			mem_buffers=${data}
			;;
		"Cached:")
			mem_cached=${data}
			;;
		"SwapTotal:")
			mem_swaptotal=${data}
			;;
		"SwapFree:")
			mem_swapfree=${data}
			;;
		esac
	done </proc/meminfo
	set +f
}
case "$op" in
g)
	get_mem_info
	for arg; do # Arg list as separate words
		service_get "$obj.$arg"
	done
	;;
esac
exit 0
