#!/bin/sh
AH_NAME="IPsecProfile"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_ipsec.sh
restart_required() {
local IPsec_Enable
cmclient -v IPsec_Enable GETV "Device.IPsec.Enable"
[ "$IPsec_Enable" = "false" ] && return 1
cmclient -v DadFilter GETO "Device.IPsec.Filter.[Profile=$obj]"
[ -z "$DadFilter" ] && return 1
[ "$op" = "d" ] && return 0
help_is_changed "Alias" "RemoteEndpoints" "X_ADB_LocalEndpoint" "Protocol" "X_ADB_IKEv2ExchangeMode" \
"X_ADB_IKEv2Check" "IKEv2AuthenticationMethod" "IKEv2AllowedEncryptionAlgorithms" \
"ESPAllowedEncryptionAlgorithms" "IKEv2AllowedIntegrityAlgorithms" "ESPAllowedIntegrityAlgorithms" \
"IKEv2AllowedDiffieHellmanGroupTransforms" "X_ADB_ESPAllowedDiffieHellmanGroupTransform" \
"IKEv2SATimeLimit" "ChildSATimeLimit" "X_ADB_IKEv2CheckPeersID" "X_ADB_RemoteEndpointMask" && return 0
return 1
}
service_delete() {
local _this_filter
if ! restart_required; then exit 0; fi
for _this_filter in $DadFilter; do
cmclient SETE "$_this_filter.Profile" ""
done
ipsec_commit
}
service_config() {
if restart_required; then ipsec_commit; fi
}
case "$op" in
d)
service_delete
;;
s)
service_config
;;
esac
exit 0
