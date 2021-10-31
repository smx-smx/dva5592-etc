#!/bin/sh
help_svc_proc_pid() {
local pid="$1" pname="$2" rdpname=''
read -r _ rdpname _ < "/proc/$pid/stat"
[ -z "$rdpname" ] && return 1
rdpname=${rdpname#(}
rdpname=${rdpname%)}
[ "$rdpname" != "$pname" ] && return 1
return 0
}
help_svc_wait_proc_started() {
local _p _i _pname="$1" _pidfile="$2" _t="$3"
while [ ! -f "$2" -a $_t -gt 0 ]; do sleep 0.1; _t=$((_t-1)); done
}
help_svc_start() {
local c="$3:$4:$5:$6:$1" f=$2
if [ ${#f} -eq 0 ]; then
set -- $1
f=$1
fi
echo $c > /tmp/inittab.d/"$f"
}
help_svc_stop() {
local arg="$1" pidfile="$2" sig="$3" _p
if [ -f /tmp/inittab.d/"$arg" ]; then
rm -f /tmp/inittab.d/"$arg"
elif [ -f "$pidfile" ]; then
read _p < "$pidfile"
kill -$sig "$_p"
else
pkill -x "$arg"
fi
}
help_svc_stop_multi() {
local arg
for arg; do
help_svc_stop "$arg"
done
}
help_svc_init() {
mkdir -p /tmp/inittab.d
kill -CHLD 1
}
help_svc_wait() {
local i=0
while [ ! -f /tmp/inittab.d/.ready -a $i -lt 100 ]; do
sleep 0.1
i=$((i+1))
done
[ ! -f /tmp/inittab.d/.ready ] && printf '\033[0;31m Watchdog initialization failed!!! boot is broken\033[0m\n' >/dev/console
}
