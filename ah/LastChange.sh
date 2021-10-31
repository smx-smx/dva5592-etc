#!/bin/sh
. /etc/ah/helper_lastChange.sh
service_config()
{
[ "$changedStatus" = "1" ] && help_lastChange_set "$obj"
}
service_get()
{
case "$2" in
"LastChange")
help_lastChange_get "$obj"
;;
esac
}
case "$op" in
s)
service_config
;;
g)
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
;;
esac
exit 0
