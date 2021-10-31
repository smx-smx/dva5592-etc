#!/bin/sh
IPSEC_LOCK="ipsec_start_lock"
FW_TABLE_NATSKIP="nat"
FW_CHAIN_SNATSKIP="SNATSkip_IPsec"
FW_TABLE_FILTER="filter"
FW_CHAIN_FILTERIN="IPsecIn"
FW_CHAIN_FILTERFWD="ForwardAllow_IPsec"
FW_CHAIN_PREFIX="_IPsec"
IPSEC_PATH="/tmp/ipsec"
SETKEY_CONF="/tmp/ipsec/setkey.conf"
SETKEY_INCLUDE_PATH="/tmp/ipsec/setkey"
RACOON_PID="/tmp/ipsec/racoon.pid"
RACOON_SOCK="/tmp/ipsec/racoon.sock"
RACOON_CONF="/tmp/ipsec/racoon.conf"
RACOON_PSK="/tmp/ipsec/psk.txt"
RACOON_INCLUDE_PATH="/tmp/ipsec/include"
RACOON_SCRIPT_PATH="/etc/ipsec"
IPSEC_GROUP="ipsecxauth"
IPSEC_GROUP_ID="540"
GROUP_FILE=/tmp/group
TEMP_GROUP_FILE=/tmp/group.temp
ENC_OUT=""
INT_OUT=""
DH_OUT=""
params_error=""
ready_tunnels=""
conntrack_flush=""
IPSEC_TIMER_ALIAS="IPsecDynDNSRefresh"
command -v help_strextract >/dev/null || . /etc/ah/helper_functions.sh
command -v help_iptables >/dev/null || . /etc/ah/helper_firewall.sh
command -v help_last_ip >/dev/null || . /etc/ah/helper_ipcalc.sh
help_dot2number() {
case $2 in
"128" ) eval $1=1 ;;
"192" ) eval $1=2 ;;
"224" ) eval $1=3 ;;
"240" ) eval $1=4 ;;
"248" ) eval $1=5 ;;
"252" ) eval $1=6 ;;
"254" ) eval $1=7 ;;
"255" ) eval $1=8 ;;
*) eval $1=0 ;;
esac
}
help_subnet_dot2slash() {
[ "$1" != "arg" ] && local arg
[ "$1" != "slash" ] && local slash
slash=0
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS="."
for arg in $2
do
help_dot2number "arg" "$arg"
slash=$((slash + arg))
done
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
eval $1='$slash'
}
help_dom_reorder() {
local _base_obj="$1" _operation="$2" _order="$3" \
_curr_obj="$4" _obj_order _obj_list
cmclient -v _obj_list GETO "$_base_obj"
for _obj_list in $_obj_list
do
[ "$_curr_obj" = "$_obj_list" ] && continue
cmclient -v _obj_order GETV "$_obj_list.Order"
if [ $_obj_order -ge $_order ]; then
if   [ "$_operation" = "add" ]; then
_obj_order=$((_obj_order + 1))
echo "###$AH_NAME: $_obj_list.Order ++ [$_obj_order]"
elif [ "$_operation" = "del" ]; then
_obj_order=$((_obj_order - 1))
echo "###$AH_NAME: $_obj_list.Order -- [$_obj_order]"
else
echo "(E)$AH_NAME: help_dom _reorder() received wrong operation ($_operation)"
return 1
fi
cmclient SETE "$_obj_list.Order" "$_obj_order"
fi
done
}
help_getfilter() {
local filter_obj="$1" tparam tvar tval parameter_list
PROFILE_AuthMethod="pre_shared_key"
[ -z "$1" ] && return
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS='
'
cmclient -v parameter_list GET "$filter_obj."
for tparam in $parameter_list
do
tvar=${tparam%;*}
tval=${tparam#*;}
case "$tvar" in
*"RoadWarrior"*"Enable")	RW_Enable="$tval"	;;
*"RoadWarrior"*"Type")		RW_Type="$tval"		;;
*"RoadWarrior"*"PoolSize")	RW_PoolSize="$tval"	;;
*"RoadWarrior"*"DomainName")	RW_DomainName="$tval"	;;
*"RoadWarrior"*"DNSServers")	RW_DNSServers="$tval"	;;
*"RoadWarrior"*"Address")	RW_Address="$tval"	;;
*"RoadWarrior"*"SubnetMask")	RW_SubnetMask="$tval"	;;
*"Enable")		FILTER_Enable="$tval"		;;
*"Status")		FILTER_Status="$tval"		;;
*"Order")		FILTER_Order="$tval"		;;
*"Interface")		FILTER_Interface="$tval"	;;
*"AllInterfaces")	FILTER_AllInterfaces="$tval"	;;
*"DestIP")		FILTER_DestIP="$tval"		;;
*"DestMask")		FILTER_DestMask="$tval"		;;
*"SourceIP")		FILTER_SourceIP="$tval"		;;
*"SourceMask")		FILTER_SourceMask="$tval"	;;
*"ProcessingChoice")	FILTER_ProcessingChoice="$tval"	;;
*"Profile")		FILTER_Profile="$tval"		;;
*"X_ADB_ForcePassive")	FILTER_Passive="$tval"		;;
*"X_ADB_SPGeneration")	FILTER_SPGen="$tval"		;;
esac
done
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
if [ -z "$FILTER_SourceIP" ] && [ -n "$FILTER_Interface" ]; then
case "$FILTER_Interface" in
"Device.IP.Interface"*)
cmclient -v FILTER_SourceIP GETV "$FILTER_Interface.IPv4Address.1.IPAddress"
cmclient -v FILTER_SourceMask GETV "$FILTER_Interface.IPv4Address.1.SubnetMask"
help_calc_network FILTER_SourceIP "$FILTER_SourceIP" "$FILTER_SourceMask"
;;
esac
fi
if [ "$RW_Enable" = "true" ]; then
FILTER_Passive="true"
if [ "$FILTER_SPGen" = "Auto" ]; then
[ "$RW_Type" = "L2TP" ] && FILTER_SPGen="Script" || FILTER_SPGen="Dynamic"
fi
if [ -n "$RW_Address" ]; then
[ -z "$RW_SubnetMask" ]   && RW_SubnetMask="255.255.255.0"
[ -z "$FILTER_DestIP" ]   && help_calc_network FILTER_DestIP "$RW_Address" "$RW_SubnetMask"
[ -z "$FILTER_DestMask" ] && FILTER_DestMask="$RW_SubnetMask"
[ "$RW_Type" = "XAuth" ]  && PROFILE_AuthMethod="xauth_psk_server"
fi
else
[ "$FILTER_SPGen" = "Auto" ] && FILTER_SPGen="Static"
fi
}
help_getprofile() {
local profile_obj="$1" tparam tvar tval parameter_list addrs
[ -z "$1" ] && return
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS='
'
cmclient -v parameter_list GET "$profile_obj."
for tparam in $parameter_list
do
tvar=${tparam%;*}
tval=${tparam#*;}
case "$tvar" in
*"Alias")				PROFILE_Alias="$tval"			;;
*"Protocol")				PROFILE_Protocol="$tval"		;;
*"IKEv2SATimeLimit")			PROFILE_IKEv2SATimeLimit="$tval"	;;
*"ChildSATimeLimit")			PROFILE_ChildSATimeLimit="$tval"	;;
*"IKEv2DeadPeerDetectionTimeout")	PROFILE_IKEv2DeadPeerDetectionTimeout="$tval" ;;
*"IKEv2AuthenticationMethod")		PROFILE_Security="$tval"		;;
*"X_ADB_IKEv2CheckPeersID")		PROFILE_PeerAllowedIDs="$tval"		;;
*"IKEv2AllowedEncryptionAlgorithms")	convert_encryption "$tval"
PROFILE_IKEv2AllowedEncryptionAlgorithms="$ENC_OUT" ;;
*"ESPAllowedEncryptionAlgorithms")	convert_encryption "$tval"
PROFILE_ESPAllowedEncryptionAlgorithms="$ENC_OUT" ;;
*"IKEv2AllowedIntegrityAlgorithms")	convert_integrityalg "$tval"
PROFILE_IKEv2AllowedIntegrityAlgorithms="$INT_OUT" ;;
*"ESPAllowedIntegrityAlgorithms")	convert_integrityalg "$tval" "child"
PROFILE_ESPAllowedIntegrityAlgorithms="$INT_OUT" ;;
*"IKEv2AllowedDiffieHellmanGroupTransforms")	convert_dhtransform "$tval"
PROFILE_IKEv2AllowedDiffieHellmanGroupTransforms="$DH_OUT" ;;
*"X_ADB_ESPAllowedDiffieHellmanGroupTransform")	convert_dhtransform "$tval"
PROFILE_ESPAllowedDiffieHellmanGroupTransform="$DH_OUT"	 ;;
*"X_ADB_IKEv2ExchangeMode")		[ "$tval" = "Auto" ] \
&& PROFILE_IKEv2ExchangeMode="aggressive,main" \
|| PROFILE_IKEv2ExchangeMode=`help_lowercase "$tval"`	;;
*"X_ADB_IKEv2Check")			PROFILE_IKEv2Check=`help_lowercase "$tval"` ;;
*"X_ADB_LocalEndpoint")			PROFILE_LocalEndpoint="$tval"
if [ -z "$tval" ]; then
cmclient -v PROFILE_LocalEndpoint GETO "IP.Interface.*.[X_ADB_DefaultRoute=true].[Enable=true]"
fi
cmclient -v addrs GETV "${PROFILE_LocalEndpoint}.IPv4Address.[Enable=true].IPAddress"
PROFILE_SourceIP=""
for PROFILE_SourceIP in $addrs; do
break
done
;;
*"RemoteEndpoints")			### Take just the first if endpoints are more than one
PROFILE_RemoteEndpoints=${tval%%,*}
case "$PROFILE_RemoteEndpoints" in
*[a-z]|[A-Z])	### IP is not valid. Is an hostname, then?
local resolved_hn
resolved_hn=`ipsec_resolve_ip "$PROFILE_RemoteEndpoints"`
PROFILE_DestIP="$resolved_hn"
[ -n "$PROFILE_DestIP" ] && cmclient SETE "$profile_obj.X_ADB_ResolvedIP" "$PROFILE_DestIP"
;;
*)	### Valid IP (probably... no hostname)
PROFILE_DestIP="$PROFILE_RemoteEndpoints"
;;
esac	;;
*"X_ADB_RemoteEndpointMask")		help_subnet_dot2slash PROFILE_RemoteEndpointMask "${tval%%,*}" ;;
*"IKEv2SAExpiryAction")			PROFILE_IKEv2ExpAct=${tval:-"Renegotiate"} ;;
*"ChildSAExpiryAction")			PROFILE_ESPExpAct=${tval:-"Renegotiate"} ;;
esac
done
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
case "${PROFILE_IKEv2ExpAct}${PROFILE_ESPExpAct}" in
"RenegotiateDelete")		PROFILE_REKEYING="ontraffic_ph2"	;;
"DeleteRenegotiate")		PROFILE_REKEYING="off"			;;
"DeleteDelete")			PROFILE_REKEYING="ontraffic_ph1ph2"	;;
*)				PROFILE_REKEYING=""			;;
esac
}
help_getsecurity() {
local security_obj="$1" tparam tvar tval parameter_list
[ -z "$1" ] && return
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS='
'
cmclient -v parameter_list GET "$security_obj."
for tparam in $parameter_list
do
tvar=${tparam%;*}
tval=${tparam#*;}
case "$tvar" in
*"IdentifierType")
case "$tval" in
"Address")	SECURITY_IdentifierType="address"	;;
"FQDN")		SECURITY_IdentifierType="fqdn"		;;
"UserFQDN")	SECURITY_IdentifierType="user_fqdn"	;;
"KeyID")	SECURITY_IdentifierType="keyid tag"	;;
esac
;;
*"IdentifierValue")	SECURITY_IdentifierValue="$tval"	;;
*"PSK")			SECURITY_PSK="$tval"
;;
esac
done
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
if [ "$SECURITY_IdentifierType" != "address" ]; then
SECURITY_IdentifierValue="\"$SECURITY_IdentifierValue\""
elif [ -z "$SECURITY_IdentifierValue" ]; then
SECURITY_IdentifierValue="$PROFILE_SourceIP"
fi
}
convert_encryption() {
local raw_enc="$1" add_enc
ENC_OUT=""
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=","; set -- $raw_enc
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
for arg
do
add_enc=""
case "$arg" in
"NULL")		add_enc="null_enc"	;;
"DES")		add_enc="des"		;;
"3DES")		add_enc="3des"		;;
"DES-IV32")	add_enc="des_iv32"	;;
"DES-IV64")	add_enc="des_iv64"	;;
"BLOWFISH")	add_enc="blowfish"	;;
"CAST")		add_enc="cast128"	;;
"AES"*)		add_enc="aes"		;;
"CAMELLIA-CBC")	add_enc="camellia"	;;
esac
[ -z "$add_enc" ] && continue
[ -n "$ENC_OUT" ] && ENC_OUT="${ENC_OUT},"
ENC_OUT="${ENC_OUT}${add_enc}"
done
}
convert_integrityalg() {
local raw_int="$1" sa="$2" prefix add_int
[ "$sa" = "child" ] && prefix="hmac_"
INT_OUT=""
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=","; set -- $raw_int
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
for arg
do
add_int=""
case "$arg" in
"NONE")			add_int="non_auth"	;;
"HMAC-MD5-"*)		add_int="${prefix}md5"		;;
"HMAC-SHA1-"*)		add_int="${prefix}sha1"		;;
"HMAC-SHA2-256-128")	add_int="${prefix}sha2_256"	;;
"HMAC-SHA2-256-192")	add_int="${prefix}sha2_384"	;;
"HMAC-SHA2-256-256")	add_int="${prefix}sha2_512"	;;
*)	echo "###AH_NAME: $arg is unsupported" > /dev/console ;;
esac
[ -z "$add_int" ] && continue
[ -n "$INT_OUT" ] && INT_OUT="${INT_OUT},"
INT_OUT="${INT_OUT}${add_int}"
done
}
convert_dhtransform() {
local raw_dh="$1" add_dh
DH_OUT=""
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=","; set -- $raw_dh
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
for arg
do
add_dh=""
case "$arg" in
"MODP-768")	add_dh="modp768"	;;
"MODP-1024")	add_dh="modp1024"	;;
"MODP-1536")	add_dh="modp1536"	;;
"MODP-2048")	add_dh="modp2048"	;;
"MODP-3072")	add_dh="modp3072"	;;
"MODP-4096")	add_dh="modp4096"	;;
"MODP-6144")	add_dh="modp6144"	;;
"MODP-8192")	add_dh="modp8192"	;;
esac
[ -z "$add_dh" ] && continue
[ -n "$DH_OUT" ] && DH_OUT="${DH_OUT},"
DH_OUT="${DH_OUT}${add_dh}"
done
}
_exec_ikecleanup() {
[ -e "$RACOON_PSK" ] && rm $RACOON_PSK
if [ -e "$RACOON_CONF" ]; then
rm $RACOON_CONF
rm $RACOON_INCLUDE_PATH/*
fi
if [ -e "$SETKEY_CONF" ]; then
rm $SETKEY_CONF
rm $SETKEY_INCLUDE_PATH/*
fi
setkey -F
setkey -FP
}
_exec_fullreconf() {
local filter_obj filter_status="Enabled" finalize parameter_list f_num dotMask
cmclient -v parameter_list GETO "Device.IPsec.Filter.[Enable=true]"
_exec_ikecleanup
for filter_obj in $parameter_list
do
help_enforcetunnel "$filter_obj"
help_getfilter "$filter_obj"
help_getprofile "$FILTER_Profile"
help_getsecurity "$PROFILE_Security"
dotMask=$FILTER_DestMask
fix_masks
if ! check_parameters; then
echo "$AH_NAME: bad params in $filter_obj - $params_error" > /dev/console
cmclient SETE "${filter_obj}.Status" "Error_Misconfigured"
continue
fi
f_num=${filter_obj##Device.IPsec.Filter.}
help_gensp		> "${SETKEY_INCLUDE_PATH}/sp-${FILTER_Order}-${filter_obj}"
help_genremote "$f_num"	> "${RACOON_INCLUDE_PATH}/remote_${FILTER_Profile}"
help_gensainfo		> "${RACOON_INCLUDE_PATH}/sainfo_${filter_obj}"
ipsec_filter_firewall
finalize="true"
cmclient SETE "${filter_obj}.Status" "Enabled"
[ -z "$PROFILE_RemoteEndpoints" ] && PROFILE_RemoteEndpoints="ANY"
[ -z "$FILTER_DestIP" ] && FILTER_DestIP="*"
		ready_tunnels="$ready_tunnels ($FILTER_SourceIP)...[$PROFILE_SourceIP]====[$PROFILE_RemoteEndpoints]...($FILTER_DestIP)"
conntrack_flush="$conntrack_flush ${FILTER_DestIP}/${dotMask}"
done
[ -z "$finalize" ] && return 1
help_genpsk > $RACOON_PSK || return 1
help_gensetkey > $SETKEY_CONF
help_genracoon > $RACOON_CONF
return 0
}
_exec_cerror() {
cmclient SETE Device.IPsec.Status "Error"
cmclient SETE Device.IPsec.Filter.[Status=Enabled] "Disabled"
ipsec_firewall "stop"
help_serialize_unlock "$IPSEC_LOCK"
logger -t "racoon" -p 3 "ARS 001 - Unable to start the service"
exit 0
}
_exec_ccheck_start() {
local _ipsec_enabled _ipsec_filter_enabled _ipsec_security_enabled
cmclient -v _ipsec_enabled GETO IPsec.[Enable=true]
cmclient -v _ipsec_filter_enabled GETO IPsec.Filter.[Enable=true]
cmclient -v _ipsec_security_enabled GETO IPsec.X_ADB_Security.[Side=Remote].[Enable=true]
[ -z "$_ipsec_enabled" ] || \
[ -z "$_ipsec_filter_enabled" ] || \
[ -z "$_ipsec_security_enabled" ] && return 1
return 0
}
_exec_cstop() {
local racoonpid
_exec_ikecleanup
ipsec_firewall "stop"
read racoonpid < "$RACOON_PID"
kill "$racoonpid"
rm $RACOON_PID
rm $RACOON_SOCK
cmclient SETE Device.IPsec.Status "Disabled"
cmclient SETE Device.IPsec.Filter.Status "Disabled"
cmclient DEL Device.IPsec.IKEv2SA
}
_exec_cstart() {
setkey -f "$SETKEY_CONF" || return 1
racoon -f "$RACOON_CONF"
ipsec_firewall "start"
local tcount
local _status="Error"
for tcount in 1 2 3 4 5; do
if [ -e "$RACOON_PID" ]; then
_status="Enabled"
break
else
sleep 1
fi
done
[ "$_status" = "Error" ] && return 1
cmclient SETE Device.IPsec.Status "$_status"
echo "### IKE daemon ready:" > /dev/console
for ready_tunnels in $ready_tunnels; do echo "###                   $ready_tunnels" > /dev/console; done
for conntrack_flush in $conntrack_flush; do echo "$conntrack_flush" > /proc/net/nf_conntrack_flush; done
return 0
}
ipsec_commit() {
local donotstart="$1" status
[ -d "$RACOON_INCLUDE_PATH" ] || exit 0
help_serialize "$IPSEC_LOCK" notrap
[ -e "$RACOON_PID" ] &&	_exec_cstop
killall racoon
if [ -n "$donotstart" ]; then
help_serialize_unlock "$IPSEC_LOCK"
return
fi
_exec_ccheck_start || _exec_cerror
_exec_fullreconf || _exec_cerror
_exec_cstart || _exec_cerror
help_serialize_unlock "$IPSEC_LOCK"
}
help_genpsk() {
local sec_obj_index sec_obj id_val id_type psk
for sec_obj_index in `cmclient GETV Device.IPsec.X_ADB_Security.*.[Enable="true"].[Side="Remote"].Order | sort`
do
cmclient -v sec_obj GETO "Device.IPsec.X_ADB_Security.+.[Order=$sec_obj_index]"
cmclient -v id_val GETV "${sec_obj}.IdentifierValue"
cmclient -v psk GETV "${sec_obj}.PSK"
cmclient -v id_type GETV "${sec_obj}.IdentifierType"
if [ "$id_type" = "Address" ]; then
case "$id_val" in
*[a-z]|[A-Z]) ### hostname? We should have it already resolved in Profile obj
cmclient -v id_val GETV "Device.IPsec.Profile.[RemoteEndpoints=$id_val].X_ADB_ResolvedIP"
;;
esac
fi
[ -n "$id_val" -a -n "$psk" ] && echo "$id_val $psk"
done
if [ ! -e "$RACOON_PSK" ]; then
echo "$AH_NAME: no X_ADB_Security enabled remote objects seems to be present." > /dev/console
echo "$AH_NAME: IPsec not started." > /dev/console
return 1
fi
chmod 400 $RACOON_PSK
return 0
}
help_gensp() {
[ "$FILTER_SPGen" != "Static" ] && return 0
echo "spdadd ${FILTER_SourceIP}/${FILTER_SourceMask} ${FILTER_DestIP}/${FILTER_DestMask} any -P out ipsec"
echo "esp/tunnel/${PROFILE_SourceIP}-${PROFILE_DestIP}/require;"
echo "spdadd ${FILTER_DestIP}/${FILTER_DestMask} ${FILTER_SourceIP}/${FILTER_SourceMask} any -P in ipsec"
echo "esp/tunnel/${PROFILE_DestIP}-${PROFILE_SourceIP}/require;"
}
help_gentransportsp() {
local cmd="$1" src_addr="$2" dst_addr="$3" src_port="${4:+[$4]}" dst_port="${5:+[$5]}"
echo "$cmd ${src_addr}${src_port} ${dst_addr}${dst_port} any -P out ipsec"
echo "esp/transport//require;"
echo "$cmd ${dst_addr}${dst_port} ${src_addr}${src_port} any -P in ipsec"
echo "esp/transport//require;"
}
help_gentunnelsp() {
local cmd="$1" tun_src="$2" tun_dst="$3" trf_src="$4" trf_smask="$5" trf_dst="$6" trf_dmask="$7" \
full_src
[ "$trf_src" = "0.0.0.0" ] && full_src="$trf_src" || full_src="${trf_src}/${trf_smask}"
echo "$cmd $full_src ${trf_dst}/${trf_dmask} any -P out ipsec"
echo "esp/tunnel/${tun_src}-${tun_dst}/require;"
echo "$cmd ${trf_dst}/${trf_dmask} $full_src any -P in ipsec"
echo "esp/tunnel/${tun_dst}-${tun_src}/require;"
}
help_gensetkey() {
local sp_file
echo "#!/usr/sbin/setkey -f"
echo "flush;"
echo "spdflush;"
for sp_file in $SETKEY_INCLUDE_PATH/*
do
echo ""
echo "# $sp_file"
cat "$sp_file"
done
}
help_enforcetunnel() {
local tun fobj="$1"
cmclient -v tun GETO Device.IPsec.Tunnel.[Filters=$fobj]
[ ${#tun} -gt 0 ] && return
cmclient -v tun ADD Device.IPsec.Tunnel
cmclient SETE Device.IPsec.Tunnel.${tun}.Filters "$fobj"
}
_get_peers_ids() {
local _sec_obj, _id, _ty
echo "  ## enforce check on remote peer identifier"
for _sec_obj in $PROFILE_PeerAllowedIDs; do
cmclient -v _id GETV ${_sec_obj}.IdentifierValue
cmclient -v _ty GETV ${_sec_obj}.IdentifierType
case "$_ty" in
"FQDN")		_ty="fqdn" _id="\"$_id\"" ;;
"UserFQDN")	_ty="user_fqdn" _id="\"$_id\"" ;;
"KeyID")	_ty="keyid tag" _id="\"$_id\"" ;;
"Address")      _ty="address"
case "$_id" in
*[a-z]|[A-Z]) ### hostname? We should have it already resolved in Profile obj
cmclient -v _id GETV "Device.IPsec.Profile.[RemoteEndpoints,$_id].X_ADB_ResolvedIP"
;;
esac
;;
esac
echo "  peers_identifier $_ty $_id;"
done
echo "  verify_identifier on;"
}
help_genremote() {
local _fobj="$1" _encryption _integrity _dhgroup
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=","
set +f
echo "remote \"$PROFILE_Alias\" {"
echo "  tr181_id $_fobj;"
if [ -n "$PROFILE_DestIP" ]; then
echo "  remote_address $PROFILE_DestIP;"
[ -n "$PROFILE_RemoteEndpointMask" ] && echo "  remote_mask $PROFILE_RemoteEndpointMask;"
fi
echo "  exchange_mode $PROFILE_IKEv2ExchangeMode;"
echo "  my_identifier $SECURITY_IdentifierType $SECURITY_IdentifierValue;"
[ ${#PROFILE_PeerAllowedIDs} -gt 0 ] && _get_peers_ids
echo "  proposal_check $PROFILE_IKEv2Check;"
echo "  nat_traversal on;"
[ -n "$PROFILE_IKEv2DeadPeerDetectionTimeout" ] && \
echo "  dpd_delay $PROFILE_IKEv2DeadPeerDetectionTimeout;"
echo "  script \"phase1.sh\" phase1_up;"
echo "  script \"phase1.sh\" phase1_down;"
echo "  script \"phase1.sh\" phase1_dead;"
[ "$FILTER_Passive" = "true" ] && echo "  passive on;"
[ "$FILTER_SPGen" = "Dynamic" ] && echo "  generate_policy cfgm_only;"
[ "$FILTER_SPGen" = "Full" ] && echo "  generate_policy on;"
[ -n "$PROFILE_REKEYING" ] && echo "  rekey $PROFILE_REKEYING;"
for _encryption in $PROFILE_IKEv2AllowedEncryptionAlgorithms; do
for _integrity in $PROFILE_IKEv2AllowedIntegrityAlgorithms; do
for _dhgroup in $PROFILE_IKEv2AllowedDiffieHellmanGroupTransforms; do
echo "  proposal {"
echo "    encryption_algorithm $_encryption;"
echo "    hash_algorithm $_integrity;"
echo "    authentication_method	$PROFILE_AuthMethod;"
echo "    dh_group $_dhgroup;"
echo "    lifetime time $PROFILE_IKEv2SATimeLimit sec;"
echo "  }"
done
done
done
echo "}"
set -f
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
}
help_gensainfo() {
[ "$RW_Enable" = "true" ] \
&& echo "sainfo anonymous {" \
|| echo "sainfo address ${FILTER_SourceIP}/${FILTER_SourceMask} any address ${FILTER_DestIP}/${FILTER_DestMask} any {"
[ -n "$PROFILE_ESPAllowedDiffieHellmanGroupTransform" ] && \
echo "  pfs_group $PROFILE_ESPAllowedDiffieHellmanGroupTransform;"
echo "  lifetime time $PROFILE_ChildSATimeLimit sec;"
echo "  encryption_algorithm $PROFILE_ESPAllowedEncryptionAlgorithms;"
echo "  authentication_algorithm $PROFILE_ESPAllowedIntegrityAlgorithms;"
echo "  compression_algorithm deflate;"
echo "}"
if [ "$RW_Enable" = "true" -a "$RW_Type" != "L2TP" ]; then
echo "mode_cfg {"
[ -n "$RW_PoolSize" ] && \
echo "    pool_size $RW_PoolSize;"
echo "    network4 $RW_Address;"
echo "    netmask4 $RW_SubnetMask;"
[ -n "$RW_DNSServers" ] && \
echo "    dns4 $RW_DNSServers;"
[ -n "$RW_DomainName" ] && \
echo "    default_domain $RW_DomainName;"
echo "    split_network include ${FILTER_SourceIP}/${FILTER_SourceMask};"
[ "$RW_Type" = "XAuth" ] && \
echo "    auth_groups \"$IPSEC_GROUP\";"
echo "}"
fi
}
help_genracoon() {
local inc_info
echo "path include \"$RACOON_INCLUDE_PATH\";"
echo "path pre_shared_key \"$RACOON_PSK\";"
echo "path script \"$RACOON_SCRIPT_PATH\";"
echo "path pidfile \"$RACOON_PID\";"
echo "listen {"
echo "  isakmp       ${PROFILE_SourceIP} [500];"
echo "  isakmp_natt  ${PROFILE_SourceIP} [4500];"
echo "  strict_address;"
echo "  adminsock    \"$RACOON_SOCK\";"
echo "}"
for inc_info in $RACOON_INCLUDE_PATH/*
do
echo "include \"$inc_info\";"
done
}
ipsec_resolve_ip() {
local host_name="$1" resolved_ip polling i
cmclient SET Device.DNS.Diagnostics.NSLookupDiagnostics.HostName "$host_name" > /dev/null
cmclient SET Device.DNS.Diagnostics.NSLookupDiagnostics.NumberOfRepetitions 1 > /dev/null
cmclient SET Device.DNS.Diagnostics.NSLookupDiagnostics.DiagnosticsState "Requested" > /dev/null
for i in 1 2 3 4 5; do
cmclient -v resolved_ip GETV "Device.DNS.Diagnostics.NSLookupDiagnostics.Result.1.IPAddresses" > /dev/null
[ -n "$resolved_ip" ] && break
sleep 1
done
resolved_ip=${resolved_ip##*,}
echo "${resolved_ip:=0.0.0.0}"
}
check_parameters() {
params_error=""
[ -z "$FILTER_Profile" ] &&		params_error=${params_error:+"$params_error,"}"FilterProfile"
[ -z "$FILTER_SourceIP" ] &&		params_error=${params_error:+"$params_error,"}"FilterSrcIP"
[ -z "$PROFILE_SourceIP" ] &&		params_error=${params_error:+"$params_error,"}"ProfileSrcIP"
[ ${#PROFILE_Security} -eq 0 -o -z "$SECURITY_IdentifierType" -o -z "$SECURITY_IdentifierValue" ] && \
params_error=${params_error:+"$params_error,"}"ProfileLocId"
if [ "$RW_Enable" = "true" ]; then
[ "$RW_Type" != "L2TP" -a \( -z "$RW_PoolSize" -o -z "$RW_Address" -o -z "$RW_SubnetMask" \) ] && \
params_error=${params_error:+"$params_error,"}"RW params"
else
[ -z "$FILTER_DestIP" ] &&	params_error=${params_error:+"$params_error,"}"FilterDstIP"
[ -z "$PROFILE_DestIP" -o "$PROFILE_DestIP" = "0.0.0.0" ] && params_error=${params_error:+"$params_error,"}"ProfileDstIP"
fi
[ -z "$params_error" ] || return 1
return 0
}
fix_masks() {
if [ -z "$FILTER_SourceMask" ]; then
FILTER_SourceMask="32"
elif [ ${#FILTER_SourceMask} -gt 2 ]; then
help_subnet_dot2slash FILTER_SourceMask "$FILTER_SourceMask"
fi
if [ -z "$FILTER_DestMask" ]; then
FILTER_DestMask="32"
elif [ ${#FILTER_DestMask} -gt 2 ]; then
help_subnet_dot2slash FILTER_DestMask "$FILTER_DestMask"
fi
}
ipsec_firewall_link_chain() {
local chain_name="$1" cmd=${2-I} inChain
for inChain in "$FW_CHAIN_FILTERFWD" "$FW_CHAIN_FILTERIN"; do
help_iptables -t "$FW_TABLE_FILTER" -${cmd} "$inChain" -j "$chain_name"
done
}
ipsec_firewall() {
local cmd="$1" filter_obj fwTable dir
if [ "$cmd" = "start" ]; then
help_iptables -t "$FW_TABLE_FILTER" -A "$FW_CHAIN_FILTERIN" -p udp --dport 500 -j ACCEPT
help_iptables -t "$FW_TABLE_FILTER" -A "$FW_CHAIN_FILTERIN" -p udp --dport 4500 -j ACCEPT
help_iptables -t "$FW_TABLE_FILTER" -A "$FW_CHAIN_FILTERIN" -p esp -j ACCEPT
help_iptables -t "$FW_TABLE_FILTER" -A "$FW_CHAIN_FILTERIN" -p ah -j ACCEPT
else
help_iptables -t "$FW_TABLE_FILTER" -F "$FW_CHAIN_FILTERFWD"
help_iptables -t "$FW_TABLE_FILTER" -F "$FW_CHAIN_FILTERIN"
help_iptables -t "$FW_TABLE_NATSKIP" -F "$FW_CHAIN_SNATSKIP"
cmclient -v filter_obj GETO Device.IPsec.Filter.[Enable=true]
for filter_obj in $filter_obj; do
for fwTable in "$FW_TABLE_NATSKIP" "$FW_TABLE_FILTER"; do
for dir in IN OUT; do
help_iptables -t "$fwTable" -F "${FW_CHAIN_PREFIX}${dir}_${filter_obj#Device.IPsec.}"
help_iptables -t "$fwTable" -X "${FW_CHAIN_PREFIX}${dir}_${filter_obj#Device.IPsec.}"
done
done
done
fi
}
ipsec_filter_create_chains() {
local chainName="$1" fwTable
for fwTable in "$FW_TABLE_NATSKIP" "$FW_TABLE_FILTER"; do
help_iptables -t "$fwTable" -N "${FW_CHAIN_PREFIX}OUT_$chainName"
help_iptables -t "$fwTable" -A "${FW_CHAIN_PREFIX}OUT_$chainName" -s "$FILTER_SourceIP/$FILTER_SourceMask" -d "$FILTER_DestIP/$FILTER_DestMask" -j ACCEPT
help_iptables -t "$fwTable" -N "${FW_CHAIN_PREFIX}IN_$chainName"
help_iptables -t "$fwTable" -A "${FW_CHAIN_PREFIX}IN_$chainName" -s "$FILTER_DestIP/$FILTER_DestMask" -d "$FILTER_SourceIP/$FILTER_SourceMask" -j ACCEPT
done
}
ipsec_filter_firewall() {
[ ${#FILTER_SourceIP} -eq 0 -o ${#FILTER_DestIP} -eq 0 ] && return
ipsec_filter_create_chains "${filter_obj#Device.IPsec.}"
help_iptables -t "$FW_TABLE_NATSKIP" -A "$FW_CHAIN_SNATSKIP" -j "${FW_CHAIN_PREFIX}OUT_${filter_obj#Device.IPsec.}"
ipsec_firewall_link_chain "${FW_CHAIN_PREFIX}OUT_${filter_obj#Device.IPsec.}"
ipsec_firewall_link_chain "${FW_CHAIN_PREFIX}IN_${filter_obj#Device.IPsec.}"
}
ipsec_create_dyndns_timer() {
local ipsec_timer_num ipsec_timer_obj setm_params
cmclient -v ipsec_timer_obj GETO "Device.X_ADB_Time.Event.[Alias=${IPSEC_TIMER_ALIAS}]"
[ -n "$ipsec_timer_obj" ] && return
cmclient -v ipsec_timer_num ADD "Device.X_ADB_Time.Event"
ipsec_timer_obj="Device.X_ADB_Time.Event.$ipsec_timer_num"
[ -z "$newX_ADB_CheckDNSFrequency" ] && \
cmclient -v newX_ADB_CheckDNSFrequency GETV "Device.IPsec.X_ADB_CheckDNSFrequency"
setm_params="$ipsec_timer_obj.Alias=$IPSEC_TIMER_ALIAS"
setm_params="$setm_params	$ipsec_timer_obj.Type=Periodic"
setm_params="$setm_params	$ipsec_timer_obj.DeadLine=$newX_ADB_CheckDNSFrequency"
cmclient SETM "$setm_params"
cmclient ADD "$ipsec_timer_obj.Action"
setm_params="$ipsec_timer_obj.Action.1.Operation=Set"
setm_params="$setm_params	$ipsec_timer_obj.Action.1.Path=Device.IPsec.X_ADB_CheckDNSTrigger"
setm_params="$setm_params	$ipsec_timer_obj.Action.1.Value=true"
setm_params="$setm_params	$ipsec_timer_obj.Enable=true"
cmclient SETM "$setm_params"
}
ipsec_dump() {
local debug_obj="$1" param_list prefix
case "$debug_obj" in
"filter")
prefix="FILTER"
param_list="	Enable\
Status\
Order\
Interface\
AllInterfaces\
DestIP\
DestMask\
SourceIP\
SourceMask\
ProcessingChoice\
Profile"
;;
"profile")
prefix="PROFILE"
param_list="	RemoteEndpoints\
DestIP Protocol\
Security\
IKEv2ExchangeMode\
IKEv2AllowedEncryptionAlgorithms\
ESPAllowedEncryptionAlgorithms\
IKEv2AllowedIntegrityAlgorithms\
ESPAllowedIntegrityAlgorithms\
IKEv2AllowedDiffieHellmanGroupTransforms\
IKEv2SATimeLimit\
ChildSATimeLimit"
;;
"security")
prefix="SECURITY"
param_list="	IdentifierType\
IdentifierValue\
PSK"
;;
"roadwarrior")
prefix="RW"
param_list="	Enable\
Type\
PoolSize\
DomainName\
DNSServers\
Address\
SubnetMask"
;;
*)
echo "$AH_NAME: debug func ipsec_dump called with wrong parameter ($debug_obj)" > /dev/console
return
;;
esac
for index in $param_list
do
eval echo "---  ${prefix}_${index}: \$${prefix}_${index}" > /dev/console
done
}
