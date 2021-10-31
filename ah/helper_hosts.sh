#!/bin/sh
command -v help_resolve_hostname >/dev/null && return 0
help_resolve_hostname() {
local host_obj="$1" local_domain="$2" name domain src namespec addr='' ret='' filter tmp
cmclient -v name GETV "${host_obj}.HostName"
[ -z "$name" ] && return 1
cmclient -v src GETV "${host_obj}.AddressSource"
cmclient -v domain GETV "${host_obj}.X_ADB_Domain"
if [ -z "$domain" ]; then
if [ -n "$local_domain" ]; then
domain="$local_domain"
elif [ "$src" != 'X_ADB_CPEName' ]; then
cmclient -v local_domain GETV "Device.Hosts.X_ADB_HostName.*.[AddressSource=X_ADB_CPEName].X_ADB_Domain"
for domain in $local_domain; do
break
done
fi
fi
namespec="${name} ${name}."
[ -n "$domain" ] && namespec="${namespec} ${name}.${domain#.}"
if [ "$src" = 'X_ADB_CPEName' ]; then
addr='127.0.0.1 ::1'
else
[ "$src" != 'X_ADB_StaticName' ] && filter='.[IPAddress!127.0.0.1].[IPAddress!::1]'
cmclient -v tmp GETV "${host_obj}.IPv4Address.*${filter}.IPAddress"
for tmp in $tmp; do
addr="$addr $tmp"
break
done
cmclient -v tmp GETV "${host_obj}.IPv6Address.*${filter}.IPAddress"
for tmp in $tmp; do
addr="$addr $tmp"
break
done
[ -z "$addr" ] && \
cmclient -v addr GETV "${host_obj}${filter}.IPAddress"
fi
for addr in $addr; do
ret="${ret}${addr} ${namespec}\n"
done
echo -ne "$ret"
[ -n "$ret" ]
}
