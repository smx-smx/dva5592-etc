#!/bin/sh
help_is_hw_bridged() {
local _ifname _dirname _vlanid _mask _untagmask _prio _cnt _line _bit _num \
_bits val
_ifname=${1%%.*}
_dirname=/proc/hwswitch/default/devices/$_ifname
[ -z "$_ifname" ] && return 1
[ ! -e "$_dirname" ] && return 1
_vlanid=${1##*.}
[ "$_vlanid" = "$_ifname" ] && read _vlanid < $_dirname/vpid
echo $_vlanid > /proc/hwswitch/default/vlan
set -- $(cat /proc/hwswitch/default/vlan)
_vlanid=$1
_mask=$2
_untagmask=$3
_prio=$4
read _line < $_dirname/bridging
_mask=$((0x$_mask))
_bits=0
for _num in $_line; do
[ $_num = "0" ] && _mask=$((_mask & ~ (1<<$_bits) ))
_bits=$((_bits + 1))
done
_cnt=0
_bit=0
while [ $_bit -lt $_bits ]; do
val=$((1 << $_bit))
[ $((_mask & $val)) != "0" ] && _cnt=$((_cnt + 1))
_bit=$((_bit + 1))
done
[ $_cnt -le 1 ] && return 1
return 0
}
