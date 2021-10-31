#!/bin/sh
help_add_bridge() {
if [ "$1" = "OVS" ]; then
ovs-vsctl --may-exist add-br "$2"
else
brctl addbr "$2"
brctl setfd "$2" 0
fi
}
help_add_bridge_port() {
if [ "$1" = "OVS" ]; then
if [ "${3##vxlan*}" != "" ]; then
ovs-vsctl --may-exist add-port "$2" "$3" -- set Interface "$3" ofport_request="$4"
else
ovs-vsctl --may-exist add-port "$2" "$3" -- set Interface "$3" type=vxlan options:local_ip=flow options:remote_ip=flow options:key=flow options:df_default=false options:tos=inherit ofport_request="$4"
fi
else
brctl addif "$2" "$3"
fi
}
help_del_bridge() {
if [ "$1" = "OVS" ]; then
ovs-vsctl --if-exists del-br "$2"
else
brctl delbr "$2"
fi
}
help_del_bridge_port() {
if [ "$1" = "OVS" ]; then
ovs-vsctl --if-exists del-port "$2" "$3"
else
brctl delif "$2" "$3"
fi
}
help_set_bridge_stp() {
local _stp
if [ "$1" = "OVS" ]; then
ovs-vsctl set bridge "$2" stp_enable="$3"
else
[ "$3" = "true" ] && _stp="1" || _stp="0"
brctl stp "$2" "$_stp"
fi
}
