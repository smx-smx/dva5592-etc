#!/bin/sh
cmd=$1
pid_file=$2
shift 2
if [ "$cmd" = "start" ]; then
echo $$ > "$pid_file"
exec pptp $@
elif [ "$cmd" = "stop" ]; then
read pid < "$pid_file"
read cmd_line < "/proc/$pid/cmdline"
case $cmd_line in
pptp* )
kill -9 $pid
;;
esac
rm -f "$pid_file"
fi
