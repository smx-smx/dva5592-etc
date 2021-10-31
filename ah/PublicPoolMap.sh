#!/bin/sh
AH_NAME="PublicPoolMap"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_ipcalc.sh
get_free_forwarding_policy() {
local qos_classifications="Device.QoS.Classification" i=1 obj
while [ $i -le 255 ]; do
cmclient -v obj GETO "$qos_classifications.[ForwardingPolicy=$i]"
[ -z "$obj" ] && break
i=$((i + 1))
done
eval $1='$i'
}
get_max_order() {
local var max=1
for var in ${@#$1}; do
[ $var -gt $max ] && max=$var
done
eval $1=$max
}
delete_refs() {
local ref
IFS=,
for ref in $newNATInterfaceSetting $newNATPortMapping $newQoSClassification; do
cmclient DEL $ref
done
unset IFS
}
add_nat_interface_setting_rule() {
local interface=$2 forwarding_policy=$3 external_address=$4 external_subnet_mask=$5 external_port=$6 external_port_end_range=$7 \
nat_type=$8 enable=$9 nat_path="Device.NAT.InterfaceSetting" nat_idx setm_params= \
dhcp dhcpitf ip_address prio
cmclient -v nat_idx ADDS ${nat_path}
nat_path="${nat_path}.${nat_idx}"
prio="1"
setm_params="${nat_path}.Interface=$interface"
setm_params="${setm_params}	${nat_path}.X_ADB_Order=$prio"
setm_params="${setm_params}	${nat_path}.X_ADB_ForwardingPolicy=$forwarding_policy"
if [ -n "$external_address" ]; then
setm_params="${setm_params}	${nat_path}.X_ADB_ExternalIPAddress=$external_address"
[ -n "$external_subnet_mask" ] && setm_params="$setm_params	${nat_path}.X_ADB_ExternalIPMask=$external_subnet_mask"
fi
if [ ${external_port:-0} -gt 0 ]; then
setm_params="$setm_params	${nat_path}.X_ADB_ExternalPort=$external_port"
[ ${external_port_end_range:-0} -gt 0 ] && setm_params="$setm_params	${nat_path}.X_ADB_ExternalPortEndRange=$external_port_end_range"
fi
setm_params="$setm_params	${nat_path}.X_ADB_Type=$nat_type"
setm_params="$setm_params	${nat_path}.X_ADB_Permissions=111"
setm_params="$setm_params	${nat_path}.Enable=$enable"
cmclient -u "${AH_NAME}${obj}" SETM "$setm_params"
eval $1='$nat_path'
}
add_qos_classification_rule() {
local interface=$2 order=$3 forwarding_policy=$4 internal_address=$5 internal_subnet_mask=$6 internal_port=$7 internal_port_end_range=$8 \
enable=$9 protocol=${10} type=${11} qos_path= tr098_qos_path= qos_paths= setm_params= ret=$1 app=${12} mask=${13} port_prefix=${14}
[ ${#port_prefix} -eq 0 ] && port_prefix="Dest"
[ "$type" = "wan" ] && prefix="Dest" || prefix="Source"
cmclient -v qos_idx ADDS Device.QoS.Classification
qos_path="Device.QoS.Classification.${qos_idx}"
cmclient -v tr098_qos_path GETV "$qos_path.X_ADB_TR098Reference"
[ ${#tr098_qos_path} -ne 0 ] && cmclient SETS "$tr098_qos_path" 0
setm_params="${setm_params:+$setm_params	}${qos_path}.Interface=$interface"
setm_params="$setm_params	${qos_path}.ForwardingPolicy=$forwarding_policy"
[ -n "$mask" ] && setm_params="$setm_params	${qos_path}.X_ADB_ForwardingPolicyMask=$mask"
setm_params="$setm_params	${qos_path}.X_ADB_Permissions=111"
setm_params="$setm_params	${qos_path}.X_ADB_IPVersion=4"
if [ -n "$internal_address" ]; then
setm_params="$setm_params	${qos_path}.${prefix}IP=$internal_address"
[ -n "$internal_subnet_mask" ] && setm_params="$setm_params	${qos_path}.${prefix}Mask=$internal_subnet_mask"
fi
if [ ${internal_port:-0} -gt 0 ] \
; then
setm_params="$setm_params	${qos_path}.${port_prefix}Port=$internal_port"
[ ${internal_port_end_range:-0} -gt 0 ] && setm_params="$setm_params	${qos_path}.${port_prefix}PortRangeMax=$internal_port_end_range"
fi
setm_params="$setm_params	${qos_path}.Enable=$enable"
qos_paths="${qos_paths:+$qos_paths,}$qos_path"
case "$protocol" in
TCP)	setm_params="$setm_params	${qos_path}.Protocol=6" ;;
UDP)	setm_params="$setm_params	${qos_path}.Protocol=17" ;;
esac
cmclient -u "${AH_NAME}${obj}" SETM "$setm_params"
eval $ret='$qos_paths'
}
add_qos_classification() {
local lan_forwarding_policy=$2 mask=$3 qos_rules= qos_rule proto=$newProtocol
if [ "$newNATType" = "None" ]; then
proto="None"
else
[ "$newProtocol" = "TCP/UDP" ] && proto="TCP UDP"
fi
for proto in $proto; do
add_qos_classification_rule qos_rule "$newInternalInterface" "$newOrder" "$lan_forwarding_policy" "$newInternalAddress" "$newInternalSubnetMask" "$newInternalPort" "$newInternalPortEndRange" "$newEnable" "$proto" "lan" "" "$mask" "Dest"
qos_rules="${qos_rules:+$qos_rules,}$qos_rule"
done
eval $1='$qos_rules'
}
add_wan_qos_classification() {
local qos_rules= qos_rule wan_forwarding_policy=$2 phy_interface proto=$newProtocol mask=$3
help_lowlayer_ifname_get phy_interface $newInterface
phy_interface=`help_obj_from_ifname_get $phy_interface`
if [ "$newNATType" = "None" ]; then
proto="None"
else
[ "$newProtocol" = "TCP/UDP" ] && proto="TCP UDP"
fi
for proto in $proto; do
add_qos_classification_rule qos_rule "$phy_interface" "$newOrder" "$wan_forwarding_policy" "$newExternalAddress" "$newExternalSubnetMask" "$newExternalPort" "$newExternalPortEndRange" "$newEnable" "$proto" "wan" "" "$mask" "Dest"
qos_rules="${qos_rules:+$qos_rules,}$qos_rule"
done
eval $1='$qos_rules'
}
add_port_mapping() {
local interface=$2 wan_forwarding_policy=$3 port_mapping_path="Device.NAT.PortMapping" tr098_port_mapping_path= pm_idx= setm_params=
cmclient -v pm_idx ADDS ${port_mapping_path}
port_mapping_path="${port_mapping_path}.${pm_idx}"
cmclient -v tr098_port_mapping_path GETV "$port_mapping_path.X_ADB_TR098Reference"
[ ${#tr098_port_mapping_path} -ne 0 ] && cmclient SETS "$tr098_port_mapping_path" 0
setm_params="$setm_params	${port_mapping_path}.Enable=true"
setm_params="$setm_params	${port_mapping_path}.Interface=$interface"
setm_params="$setm_params	${port_mapping_path}.AllInterfaces=true"
[ -n "$newInternalAddress" ] &&
setm_params="$setm_params	${port_mapping_path}.InternalClient=$newInternalAddress"
[ ${newExternalPort:-0} -gt 0 ] && \
setm_params="$setm_params	${port_mapping_path}.ExternalPort=${newExternalPort:-0}"
[ ${newExternalPortEndRange:-0} -gt 0 ] && \
setm_params="$setm_params	${port_mapping_path}.ExternalPortEndRange=${newExternalPortEndRange}"
case "$newProtocol" in
TCP|UDP)
setm_params="$setm_params	${port_mapping_path}.Protocol=$newProtocol"
;;
TCP/UDP)
setm_params="$setm_params	${port_mapping_path}.Protocol=X_ADB_TCPUDP"
;;
esac
[ -n "$newAdditionalExternalPort" ] && \
setm_params="$setm_params	${port_mapping_path}.X_ADB_AdditionalExternalPort=$additional_port"
[ ${newInternalPort:-0} -gt 0 ] && \
setm_params="$setm_params	${port_mapping_path}.InternalPort=$newInternalPort"
setm_params="$setm_params	${port_mapping_path}.X_ADB_ForwardingPolicy=$wan_forwarding_policy"
cmclient -v result -u "${AH_NAME}${obj}" SETM "$setm_params"
case "$result" in
*"ERROR"*)
cmclient DEL "$port_mapping_path"
return
;;
esac
eval $1='$port_mapping_path'
}
service_config() {
local lan_forwarding_policy qos_refs wan_forwarding_policy nat_refs natpm_refs
if [ "$setEnable" = "1" ] || help_is_changed Interface ExternalAddress ExternalSubnetMask InternalAddress \
InternalSubnetMask ExternalPort ExternalPortEndRange InternalPort InternalPortEndRange Protocol NATType Order \
; then
if [ "$changedOrder" = "1" ]; then
help_sort_orders "$obj" "$oldOrder" "$newOrder" "$AH_NAME"
cmclient SET "Device.X_ADB_PublicPool.Map.[Order-$newOrder]"
fi
delete_refs
[ -z "$newInterface" -o -z "$newInternalInterface" ] && exit 0
if [ "$newEnable" = "true" ]; then
case "$newNATType" in
None)
newInternalPort=-1 newInternalPortEndRange=-1 newExternalPort=-1 newExternalPortEndRange=-1
newExternalAddress= newExternalSubnetMask=
;;
NAPT)
newInternalSubnetMask= newExternalSubnetMask=
;;
NAT1:1)
newInternalPort=-1 newInternalPortEndRange=-1 newExternalPort=-1 newExternalPortEndRange=-1
newInternalSubnetMask=$newExternalSubnetMask
;;
esac
if [ -n "$newInternalAddress" ]; then
help_check_ip_netmask "$newInternalAddress" "${newInternalSubnetMask:-255.255.255.255}" || return
fi
get_free_forwarding_policy lan_forwarding_policy
add_qos_classification qos_refs "$lan_forwarding_policy"
get_free_forwarding_policy wan_forwarding_policy
add_wan_qos_classification qos_ref "$wan_forwarding_policy" 63
qos_refs="${qos_refs:+$qos_refs,}$qos_ref"
add_nat_interface_setting_rule nat_refs "$newInterface" "$lan_forwarding_policy" "$newExternalAddress" "$newExternalSubnetMask" "$newExternalPort" "$newExternalPortEndRange" "$newNATType" "$newEnable"
add_port_mapping natpm_refs "$newInterface" "$wan_forwarding_policy"
fi
cmclient SETE ${obj}.NATInterfaceSetting "$nat_refs"
cmclient SETE ${obj}.NATPortMapping "$natpm_refs"
cmclient SETE ${obj}.QoSClassification "$qos_refs"
[ "$changedOrder" = "1" ] && cmclient SET "Device.X_ADB_PublicPool.Map.[Order+$newOrder]"
fi
}
service_add() {
local o l maxorder=0
cmclient -v l GETO "Device.X_ADB_PublicPool.Map"
for l in $l; do
if [ "$l" != "$obj" ]; then
cmclient -v o GETV "$l.Order"
[ ${o:-0} -gt $maxorder ] && maxorder=$o
fi
done
cmclient SETE "${obj}.Order" "$((maxorder + 1))"
}
service_del() {
local  i o maxorder
cmclient -v i GETV "Device.X_ADB_PublicPool.Map.Order"
get_max_order maxorder $i
i=1
while [ $i -le $maxorder ]; do
cmclient -v o GETO "Device.X_ADB_PublicPool.Map.[Order=$i]"
[ ${#o} -gt 0 -a "$o" != "$obj" -a $i -gt $oldOrder ] && \
cmclient SETE "$o.Order" $((i - 1))
i=$((i + 1))
done
delete_refs
}
service_get() {
case "$1" in
Status)
local natif natpm qos enable val st status=Enabled
cmclient -v enable GETV "$obj.Enable"
if [ "$enable" = false ]; then
echo Disabled
return
fi
cmclient -v natif GETV "$obj.NATInterfaceSetting"
cmclient -v natpm GETV "$obj.NATPortMapping"
cmclient -v qos GETV "$obj.QoSClassification"
[ -z "$natif$natpm$qos" ] && status=Error_Misconfigured
IFS=,
for st in $natif $natpm $qos; do
cmclient -v val GETV "$st.Status"
case "$val" in
Error)	status=Error
break
;;
Disabled)
status=Disabled
;;
Enabled)
;;
*)
[ "$status" != Disabled ] && status=Error_Misconfigured
;;
esac
done
echo "$status"
unset IFS
;;
esac
}
case "$op" in
a)
service_add
;;
d)
service_del
;;
g)
for arg; do
service_get "$arg"
done
;;
s)
service_config
;;
esac
exit 0
