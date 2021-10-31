#!/bin/sh
set -f
extract_cmds() {
for arg; do
case "$arg" in
\**)
arg="${arg#\*}"
eval "$arg"'() { exec_cmd_safely "'"`which "$arg"`"'" "$@" ;}'
;;
esac
commands_supported="$commands_supported $arg"
done
}
exec_cmd_safely() {
local cmd="$1" rp
shift
for arg; do
case "$arg" in
*/../*|*/..)
echo "${cmd##*/}: path ($arg) not permitted."
return 1
;;
/mnt/sd[a-z][0-9]*)
rp=`readlink -f "$arg"`
if [ "${rp:-$arg}" != "${arg%/}" ]; then
echo "${cmd##*/}: path ($arg) not permitted."
return 1
fi
;;
-*)	;;
*)
echo "${cmd##*/}: path ($arg) not permitted."
return 1
;;
esac
done
"$cmd" "$@"
}
quote_for_eval() {
local c="${2%"${2#?}"}" str=${2#?} ret=
while [ ${#c} -ne 0 ]; do
case "$c" in
[\"\'\ ]) ret="$ret$c" ;;
*) ret="$ret\\$c" ;;
esac
c="${str%"${str#?}"}"
str="${str#?}"
done
eval $1='$ret'
}
extract_cmds "$@"
while read -p '> ' -r cmd args; do
case " $commands_supported " in
*" $cmd "*)
quote_for_eval args "$args"
eval "$cmd" $args
continue
;;
esac
case "$cmd" in
exit)
break
;;
"")
;;
*)
echo "$cmd: command not supported"
;;
esac
done
exit 0
