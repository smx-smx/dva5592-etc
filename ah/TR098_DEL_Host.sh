#!/bin/sh
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_delete_tr098() {
tr98ref="$newX_ADB_TR098Reference"
if [ -n "$tr98ref" ]; then
help181_del_tr98obj "$tr98ref"
fi
}
case "$op" in
"d")
service_delete_tr098
;;
esac
exit 0
