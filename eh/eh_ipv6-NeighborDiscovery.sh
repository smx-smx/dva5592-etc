#!/bin/sh
#udp:ip-pre-up,ppp,*
#sync:max=1
. /etc/ah/IPv6_helper_functions.sh
help_ipv6_reconf_iface "$IFNAME"
