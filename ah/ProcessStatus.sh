#!/bin/sh
AH_NAME="ProcessStatus"
service_get() {
local get_path="$1"
case "$get_path" in
*"ProcessStatus.CPUUsage" )
echo $((cpu_usr+cpu_sys)) ;;
*"ProcessStatus.X_ADB_CPUIOWait" )
echo "$cpu_io" ;;
*"ProcessStatus.X_ADB_LoadAvg1" )
echo "$load_avg1" ;;
*"ProcessStatus.X_ADB_LoadAvg5" )
echo "$load_avg5" ;;
*"ProcessStatus.X_ADB_LoadAvg15" )
echo "$load_avg15" ;;
*"ProcessStatus.X_ADB_ProcessCount" )
echo "$proc_count" ;;
*)
echo "" ;;
esac
}
get_top_info() {
set -f
while IFS=" :%/" read -r f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 _; do
case "$f1" in
"CPU" )
cpu_usr="$f2"
cpu_sys="$f4"
cpu_io="$f10"
;;
"Load" )
load_avg1="$f3"
load_avg5="$f4"
load_avg15="$f5"
proc_running="$f6"
proc_count="$f7"
break;
esac
done <<-EOF
`top -n1`
EOF
set +f
}
case "$op" in
g)
get_top_info
for arg # Arg list as separate words
do
service_get "$obj.$arg"
done
;;
esac
exit 0
