#!/bin/sh
_to_hex() {
local _c
case $2 in
15) _c=f;;
14) _c=e;;
13) _c=d;;
12) _c=c;;
11) _c=b;;
10) _c=a;;
*) _c=$2;;
esac
eval $1='$_c'
}
help_inc_mac_address() {
[ "$1" != _upper ] && local _upper
[ "$1" != _last_byte ] && local _last_byte
[ "$1" != _tmp ] && local _tmp
[ "$1" != _num_last_byte ] && local _num_last_byte
_upper="${2%:*}"
_last_byte="${2##*:}"
_num_last_byte=$((0x$_last_byte + $3))
[ "$_upper" = "$_mac" ] && _upper=""
if [ $_num_last_byte -gt 255 ]; then
[ -n "$_upper" ] && help_inc_mac_address _upper "$_upper" 1
_num_last_byte=$(($_num_last_byte - 256))
fi
_to_hex _last_byte $((_num_last_byte / 16))
_to_hex _tmp $((_num_last_byte % 16))
[ -n "$_upper" ] && _upper="$_upper:"
eval $1='$_upper$_last_byte$_tmp'
}
