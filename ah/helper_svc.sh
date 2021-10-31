#!/bin/sh
command -v help_svc_start >/dev/null && return 0
if [ -f /etc/ah/helper_svc_wd.sh ]; then
. /etc/ah/helper_svc_wd.sh
return 0
fi
help_svc_proc_pid() {
local pid="$1" pname="$2" rdpname=''
read -r _ rdpname _ < "/proc/$pid/stat"
[ -z "$rdpname" ] && return 1
rdpname=${rdpname#(}
rdpname=${rdpname%)}
[ "$rdpname" != "$pname" ] && return 1
return 0
}
help_svc_wait_n_kill() {
local _pid=$1 _t=$2
while [ -d /proc/$_pid -a $_t -ne 0 ]; do sleep 0.1; _t=$((_t-1)); done
[ $_t -eq 0 ] && kill -9 $_pid
}
help_svc_wait_proc_started() {
local _p _i _pname="$1" _pidfile="$2" _t="$3"
while [ ! -f "$2" -a $_t -gt 0 ]; do sleep 0.1; _t=$((_t-1)); done
}
help_svc_stop_bypid() {
local _p _i _pname="$1" _pidfile="$2" _sig="$3"
[ -f "$_pidfile" ] || return
read _p < "$_pidfile"
! help_svc_proc_pid $_p "$_pname" && return
kill -s $_sig $_p
help_svc_wait_n_kill $_p 20
}
help_svc_start() {
if [ "$3" = "attach" -o "$3" = "attach-reboot" ]; then
return 0
fi
if [ "$3" = "daemon" -o "$3" = "daemon-reboot" ]; then
$1
else
$1 &
[ -n "$7" ] && echo $! > "$7"
fi
}
help_svc_stop() {
if [ ${#3} -ne 0 ]; then
if [ ${#2} -ne 0 ]; then
case $1 in
hostapd*)
help_svc_stop_bypid hostapd "$2" "$3"
;;
*)
help_svc_stop_bypid "$1" "$2" "$3"
;;
esac
else
pkill  -"$3" -x "$1"
fi
else
pkill -9 -x "$1"
fi
}
help_svc_stop_multi() {
killall -9 $*
}
help_svc_init() { :; }
help_svc_wait() { :; }
