#!/bin/sh
help_calc_network() {
[ "$1" != ip ] && local ip
[ "$1" != mask ] && local mask
help_ip2int ip "$2"
help_ip2int mask "$3"
help_int2ip $1 $((ip & mask))
}
help_calc_broadcast() {
[ "$1" != ip ] && local ip
[ "$1" != mask ] && local mask
help_ip2int ip "$2"
help_ip2int mask "$3"
help_int2ip $1 $((ip | 0xffffffff & ~mask))
}
help_first_ip() {
[ "$1" != ip ] && local ip
[ "$1" != mask ] && local mask
help_ip2int ip "$2"
help_ip2int mask "$3"
[ "$4" = "dhcp" -a $(((ip & mask) + 1)) -eq $ip ] && \
help_int2ip $1 $(((ip & mask) + 2)) || \
help_int2ip $1 $(((ip & mask) + 1))
}
help_last_ip() {
[ "$1" != ip ] && local ip
[ "$1" != mask ] && local mask
help_ip2int ip "$2"
help_ip2int mask "$3"
[ "$4" = "dhcp" -a $(((ip | 0xffffffff & ~mask) - 1)) -eq $ip ] && \
help_int2ip $1 $(((ip | 0xffffffff & ~mask) - 2)) || \
help_int2ip $1 $(((ip | 0xffffffff & ~mask) - 1))
}
help_mask2cidr() {
set -- $1 0^^^128^192^224^240^248^252^254^ ${#2} ${2##*255.}
set -- $1 $((($3 - ${#4})*2)) ${2%%${4%%.*}*}
eval $1='$(($2 + (${#3}/4)))'
}
help_cidr2mask() {
[ $1 != _ret ] && local _ret=$1 || _ret=$1
set -- $((5 - ($2 / 8))) 255 255 255 255 $(((255 << (8 - ($2 % 8))) & 255)) 0 0 0
[ $1 -gt 1 ] && shift $1 || shift
eval $_ret='${1-0}.${2-0}.${3-0}.${4-0}'
}
help_check_ip_netmask() {
local ip mask
help_ip2int ip "$1"
help_ip2int mask "$2"
[ $ip -eq $((ip & mask)) ]
}
help_check_ip_in_network() {
local ip network mask
help_ip2int ip "$1"
help_ip2int network "$2"
help_ip2int mask "$3"
[ $((ip & mask)) -eq $((network & mask)) ]
}
help_ip2int() {
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=.
set -- $1 $2
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
eval $1=0
[ $# -eq 5 ] && eval $1=$((($2 & 0xFF) << 24 | ($3 & 0xFF) << 16 | ($4 & 0xFF) << 8 | $5 & 0xFF))
}
help_int2ip() {
eval $1=$(($2 >> 24 & 0xFF)).$(($2 >> 16 & 0xFF)).$(($2 >> 8 & 0xFF)).$(($2 & 0xFF))
}
help_ips2masks() {
[ $1 != _minaddr ] && local _minaddr=$2 || _minaddr=$2
[ $1 != _maxaddr ] && local _maxaddr=$3 || _maxaddr=$3
[ $1 != _ipmask ] && local _ipmask
[ $1 != _ipaddr ] && local _ipaddr
[ $1 != _mask ] && local _mask
[ $1 != _str ] && local _str="" || _str=""
help_ip2int _minaddr "$_minaddr"
help_ip2int _maxaddr "$_maxaddr"
while [ $_minaddr -le $_maxaddr ]; do
_mask=32
while [ $_mask -ge 0 ]; do
[ $((1+_maxaddr-_minaddr)) -lt $((1<<(32-$_mask))) ] && break
help_cidr2mask _ipmask $_mask
help_ip2int _ipmask $_ipmask
[ $((_minaddr & _ipmask)) -ne $_minaddr ] && break
_mask=$((_mask-1))
done
_mask=$((_mask+1))
help_cidr2mask _ipmask $_mask
help_int2ip _ipaddr "$_minaddr"
_str="$_str $_ipaddr/$_ipmask"
_minaddr=$((_minaddr+(1<<(32-$_mask))))
done
eval $1='$_str'
}
