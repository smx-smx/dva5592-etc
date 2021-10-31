#!/bin/sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/VoIPCommon.sh
. /etc/ah/helper_ipcalc.sh
. /etc/ah/helper_firewall.sh
AH_NAME="VoipNetwork"
[ "$user" = "${AH_NAME}" ] && exit 0
if [ "$1" = "r" -o "$1" = "u" -o "$1" = "d" ]; then
op="$1"
shift
fi
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize ${AH_NAME}
serviceId=1
VOIP_SERVICE="Services.VoiceService.${serviceId}"
VOIP_PROFILE="${VOIP_SERVICE}.VoiceProfile"
voip_firewall_cfg() {
local multipleIfEnable="" interfaceList="" sipPort="$1" i="" transports="" j=""
help_iptables -F VoIPServicesIn
cmclient -v multipleIfEnable GETV "Device.Services.VoiceService.${serviceId}.Capabilities.X_ADB_ProfileOutboundInterface"
case "$multipleIfEnable" in
"true")
cmclient -v interfaceList GETV "Device.Services.VoiceService.${serviceId}.VoiceProfile.*.X_ADB_OutboundInterface"
;;
*)
cmclient -v interfaceList GETV "Device.Services.VoiceService.${serviceId}.X_ADB_OutboundInterface"
;;
esac
cmclient -v transports GETV "Device.Services.VoiceService.${serviceId}.Capabilities.SIP.Transports"
IFS=","
for interfaceList in $interfaceList; do
help_lowlayer_ifname_get ifname "$interfaceList"
for transports in $transports; do
help_iptables -A VoIPServicesIn -i "$ifname" -p $(help_lowercase $transports) --dport "$sipPort" -j VoIPFirewall
done
done
unset IFS
help_iptables commit
cmclient SET "Device.Services.VoiceService.${serviceId}.X_ADB_VoIPFirewall.[Enable=true].Refresh true"
}
voip_network_firewall_update() {
local sipPort="" pobjs="" rtpMax="" rtpMin="" udptlMax="" udptlMin="" profile=""
cmclient -v sipPort GETV ${VOIP_SERVICE}.X_ADB_SIP.LocalPort
init_natskip "SIP" "$sipPort"
cmclient -v pobjs GETO "$VOIP_PROFILE"
for pobjs in $pobjs; do
cmclient -v rtpMax GETV "$pobjs.RTP.LocalPortMax"
cmclient -v rtpMin GETV "$pobjs.RTP.LocalPortMin"
cmclient -v udptlMax GETV "$pobjs.FaxT38.X_ADB_UDPTLLocalPortMax"
cmclient -v udptlMin GETV "$pobjs.FaxT38.X_ADB_UDPTLLocalPortMin"
init_natskip "RTP" "$rtpMin" "$rtpMax"
init_natskip "FaxT38" "$udptlMin" "$udptlMax"
done
[ -f /etc/ah/VoIPFirewall.sh ] && voip_firewall_cfg "$sipPort"
}
voip_if_lan_update() {
local ifChanged="$1" netObjs="" netItf="" interface="" ips="" ipa="" ipn="" netaddr=""
if [ "$multiple_wan" = "true" ]; then
cmclient -v netObjs GETO $VOIP_PROFILE
else
netObjs="${VOIP_SERVICE}"
fi
for netObjs in $netObjs ; do
cmclient -v netItf GETV ${netObjs}.X_ADB_OutboundInterface
table_idx=`get_dev_rule_table $netItf`
help_lowlayer_ifname_get interface "$ifChanged"
cmclient -v ips GETO ${ifChanged}.IPv4Address
for ips in $ips ; do
cmclient -v ipa GETV ${ips}.IPAddress
cmclient -v ipn GETV ${ips}.SubnetMask
[ "$ipa" != "" -a "$ipn" != "" ] && help_calc_network netaddr $ipa $ipn
for netObjs in $netObjs ; do
ip route add $netaddr/$ipn dev $interface table $table_idx
done
done
done
}
voip_if_changed() {
ifChanged="$1"
if [ "$multiple_wan" = "true" ]; then
cmclient -v ifObjs GETO ${VOIP_PROFILE}.*.[X_ADB_OutboundInterface="$ifChanged"]
else
cmclient -v ifObjs GETO ${VOIP_SERVICE}.[X_ADB_OutboundInterface="$ifChanged"]
fi
if [ "$ifObjs" = "" ]; then
return
fi
voip_network_firewall_update
}
voip_if_deleted() {
ifChanged="$1"
if [ "$multiple_wan" = "true" ]; then
cmclient -v ifObjs GETO ${VOIP_PROFILE}.*.[X_ADB_OutboundInterface="$ifChanged"]
else
cmclient -v ifObjs GETO ${VOIP_SERVICE}.[X_ADB_OutboundInterface="$ifChanged"]
fi
if [ "$ifObjs" = "" ]; then
return
fi
for ifObj in $ifObjs ; do
cmclient SET ${ifObj}.X_ADB_OutboundInterface ""
done
}
cmclient -v multiple_wan GETV ${VOIP_SERVICE}.Capabilities.X_ADB_ProfileOutboundInterface
case "$op" in
s)
lobj="${obj##*VoiceProfile.}"
if [ "$multiple_wan" = "true" ]; then
if [ "$lobj" = "$obj" ]; then
exit 2
fi
else
if [ "$lobj" != "$obj" ]; then
exit 2
fi
fi
cmclient -v landevs GETO Device.IP.Interface.[X_ADB_Upstream=false]
for landevs in $landevs ; do
voip_if_lan_update $landevs
done
voip_network_firewall_update
service_reload
;;
r)
voip_network_firewall_update
;;
u)
cmclient -v wandevice GETV "$1".X_ADB_Upstream
if [ "$wandevice" != "true" ]; then
voip_if_lan_update $1
fi
voip_if_changed $1
service_reload
;;
d)
voip_if_deleted $1
service_reload
;;
esac
exit 0
