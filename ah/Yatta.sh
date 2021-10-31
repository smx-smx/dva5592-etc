#!/bin/sh
AH_NAME="yatta"
[ "$user" = "${AH_NAME}" ] && exit 0
yatta_proc_dir="/proc/net/yatta/"
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
service_init() {
obj="Device.X_ADB_FastForward.Yatta"
changedEnable=1
changedMulticastEnable=1
changedHwEnable=1
changedESPEnable=1
changedNewLocalDestinedConnectionsAllowed=1
changedNewConnectionsAllowed=1
changedNotAcceleratedConnectionsAllowed=1
cmclient -v newEnable GETV "${obj}.Enable"
cmclient -v newMulticastEnable GETV "${obj}.MulticastEnable"
cmclient -v newHwEnable GETV "${obj}.HwEnable"
cmclient -v newESPEnable GETV "${obj}.ESPEnable"
obj="$obj.RateLimit"
cmclient -v newNewLocalDestinedConnectionsAllowed GETV "${obj}.NewLocalDestinedConnectionsAllowed"
cmclient -v newNewConnectionsAllowed GETV "${obj}.NewConnectionsAllowed"
cmclient -v newNotAcceleratedConnectionsAllowed GETV "${obj}.NotAcceleratedConnectionsAllowed"
}
help_is_ipsec_flow_deleted() {
local flow_app
cmclient -v flow_app GETV "%($obj.App)".ProtocolIdentifier
[ "$flow_app" = "urn:dslforum-org:ipsec" ] && return 0
return 1
}
help_set_esp_acceleration() {
local esp_en _cmd="$1" setm
cmclient -v esp_en GETV Device.X_ADB_FastForward.Yatta.ESPEnable
[ "$_cmd" = "true" ] && esp_en=$((esp_en | 2)) || esp_en=$((esp_en & 1))
setm="Device.X_ADB_FastForward.Yatta.ESPEnable=$esp_en"
setm="${setm}	Device.X_ADB_FastForward.Yatta.FlushConnections=true"
cmclient SETM "$setm"
}
help_is_ipsec_flow_enabled() {
local ipsec_flow
cmclient -v ipsec_flow GETO "%(Device.QoS.Flow.[Enable=true].App)".[ProtocolIdentifier=urn:dslforum-org:ipsec]
[ ${#ipsec_flow} -gt 0 ] && return 0
return 1
}
help_is_ipsec_tunnel_enabled() {
local ipsec_tunnel
cmclient -v ipsec_tunnel GETV "Device.IPsec.Enable"
[ "$ipsec_tunnel" = "true" ] && return 0
return 1
}
help_set_boolean_value() {
local _proc_entry="${yatta_proc_dir}${1}" _bool_value="$2" int_value=0
[ -f "$_proc_entry" ] || return
[ "$_bool_value" = true ] && int_value=1
echo "$int_value" > "$_proc_entry"
}
help_set_bitfield_value() {
local _proc_entry="${yatta_proc_dir}${1}" _bit_field_value="$2" int_value=0
[ -f "$_proc_entry" ] || return
[ $_bit_field_value = 3 ] && int_value=1
echo "$int_value" > "$_proc_entry"
}
help_set_int_value() {
local _proc_entry="${yatta_proc_dir}${1}" _int_value="$2"
[ -f "$_proc_entry" ] || return
echo "$_int_value" > "$_proc_entry"
}
service_config () {
[ ${changedEnable:-0} -eq 1 ] && help_set_boolean_value enable "${newEnable}"
[ ${changedMulticastEnable:-0} -eq 1 ] && \
help_set_boolean_value mcast_enable "${newMulticastEnable}"
[ ${changedHwEnable:-0} -eq 1 ] && \
help_set_boolean_value hw_enable "${newHwEnable}"
if [ ${changedESPEnable:-0} -eq 1 ]; then
if help_is_ipsec_flow_enabled || help_is_ipsec_tunnel_enabled; then
newESPEnable=$((newESPEnable & 1))
else
newESPEnable=$((newESPEnable | 2))
fi
cmclient SETE Device.X_ADB_FastForward.Yatta.ESPEnable "$newESPEnable"
help_set_bitfield_value esp_proto_enable "${newESPEnable}"
fi
[ ${changedNewLocalDestinedConnectionsAllowed:-0} -eq 1 ] && \
help_set_int_value rl_conn_local "${newNewLocalDestinedConnectionsAllowed}"
[ ${changedNewConnectionsAllowed:-0} -eq 1 ] && \
help_set_int_value rl_conn "${newNewConnectionsAllowed}"
[ ${changedNotAcceleratedConnectionsAllowed:-0} -eq 1 ] && \
help_set_int_value rl_conn_na "${newNotAcceleratedConnectionsAllowed}"
}
service_flush() {
[ ${setFlushConnections:-0} -eq 1 -a "${newFlushConnections}" = "true" ] && \
help_set_boolean_value "../nf_conntrack_flush" "${newFlushConnections}"
[ ${setFlushHWConnections:-0} -eq 1 -a "${newFlushHWConnections}" = "true" ] && \
help_set_boolean_value hw_conn_nr "${newFlushHWConnections}"
}
read_value() {
[ "$1" != value ] && local value
local _proc_entry="${yatta_proc_dir}${2}"
value="0"
[ -f "$_proc_entry" ] && read value < "$_proc_entry"
eval $1='$value'
}
service_get() {
local obj="$1" value=""
case "$obj" in
*"HwConnectionNumber") read_value value hw_conn_nr ;;
*"DroppedLocalDestinedConnections")
read_value value rl_conn_local_stats
value=${value##*|}
;;
*"DroppedConnections")
read_value value rl_conn_stats
value=${value##*|}
;;
*"DroppedNotAcceleratedConnections")
read_value value rl_conn_na_stats
value=${value##*|}
;;
esac
echo "$value"
}
if [ $# -eq 1 -a "$1" = "init" ]; then
service_init
op="s"
fi
case "$op" in
g)
for arg; do  # arg list as separate words
service_get "$obj.$arg"
done
;;
s)
case "$obj" in
*"Yatta"*)
service_flush
help_is_changed Enable HwEnable MulticastEnable ESPEnable \
NewLocalDestinedConnectionsAllowed NewConnectionsAllowed \
NotAcceleratedConnectionsAllowed && service_config
;;
*"Flow"* | *"IPsec"*)
if help_is_ipsec_flow_enabled || help_is_ipsec_tunnel_enabled; then
help_set_esp_acceleration false
else
help_set_esp_acceleration true
fi
;;
esac
;;
d)
case "$obj" in
*"Flow"*)
if help_is_ipsec_flow_deleted && help_is_ipsec_tunnel_enabled; then
help_set_esp_acceleration false
else
help_set_esp_acceleration true
fi
;;
esac
;;
esac
exit 0
