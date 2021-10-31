#!/bin/sh
CONFDIR=/tmp/cfg/quagga
STATEDIR=/var/run/quagga
PRIVSEP_USER="daemon"
PRIVSEP_GROUP="nogroup"
. /etc/ah/helper_svc.sh
zebra_genconfig()
{
echo "password zebra"
echo "access-list vty permit 127.0.0.0/8"
echo "access-list vty permit 192.168.1.0/24"
echo "access-list vty deny any"
echo "line vty"
echo " access-class vty"
}
zebra_start()
{
local ret
help_serialize "quagga_startstop_lock" notrap
zebra_genconfig > /tmp/zebra.conf
chown "$PRIVSEP_USER:$PRIVSEP_GROUP" /tmp/zebra.conf
pidof bfdd || bfdd -d -f /dev/null ## XXX temporary, unitl bfd will have own TR-181.
zebra -d -f /tmp/zebra.conf
ret=$?
[ $ret -eq 0 ] && help_svc_wait_proc_started "zebra" "${STATEDIR}/zebra.pid" 30
help_serialize_unlock "quagga_startstop_lock"
return $ret
}
zebra_ensure_running()
{
pidof zebra && return 0
mkdir -p ${CONFDIR}
chown -R "$PRIVSEP_USER:$PRIVSEP_GROUP" ${CONFDIR}
chmod a+x /tmp/cfg/
if [ ! -d ${STATEDIR} ]; then
mkdir -p ${STATEDIR}
chown -R "$PRIVSEP_USER:$PRIVSEP_GROUP" ${STATEDIR}
fi
zebra_start
}
zebra_maybe_stop()
{
local proto_enabled
cmclient -v proto_enabled GETV Device.Routing.RIP.Enable
[ "$proto_enabled" = "true" ] && return
cmclient -v proto_enabled GETV Device.Routing.X_ADB_RIPng.Enable
[ "$proto_enabled" = "true" ] && return
cmclient -v proto_enabled GETV Device.Routing.X_ADB_BGP.Enable
[ "$proto_enabled" = "true" ] && return
cmclient -v proto_enabled GETV Device.Routing.X_ADB_OSPF.Enable
[ "$proto_enabled" = "true" ] && return
cmclient -v proto_enabled GETV Device.Routing.X_ADB_OSPFv3.Enable
[ "$proto_enabled" = "true" ] && return
help_serialize "quagga_startstop_lock" notrap
help_svc_stop "zebra" "${STATEDIR}/zebra.pid" "15"
help_serialize_unlock "quagga_startstop_lock"
}
