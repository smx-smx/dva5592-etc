#!/bin/sh
AH_NAME="QoSApp"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_firewall.sh
ICMP_ALG_MOD="ip_conntrack_proto_icmp nf_nat_proto_icmp"
FTP_ALG_MOD="nf_conntrack_ftp nf_nat_ftp"
TFTP_ALG_MOD="nf_conntrack_tftp nf_nat_tftp"
PPTP_ALG_MOD="nf_conntrack_proto_gre nf_nat_proto_gre nf_conntrack_pptp \
nf_nat_pptp"
SIP_ALG_MOD="nf_conntrack_sip nf_nat_sip"
H323_ALG_MOD="nf_conntrack_h323 nf_nat_h323"
ALG_FTP_PROTO_ID="urn:dslforum-org:ftp"
ALG_TFTP_PROTO_ID="urn:dslforum-org:tftp"
ALG_PPTP_PROTO_ID="urn:dslforum-org:pptp"
ALG_IPSEC_PROTO_ID="urn:dslforum-org:ipsec"
ALG_SIP_PROTO_ID="urn:dslforum-org:sip"
ALG_H323_PROTO_ID="urn:dslforum-org:h323"
alg_ftp="FTP"
alg_tftp="TFTP"
alg_pptp="PPTP"
alg_ipsec="IPSEC"
alg_sip="SIP"
alg_h323="H323"
alg_mod_name=""
reverse_list() {
	local _l _revlist=""
	[ ! "$2" ] && eval $1='' && return
	for _l in $2; do
		_revlist="$_l $_revlist"
	done
	eval $1='$_revlist'
}
alg_cmd() {
	local _enable="$1" _cmd="" _v
	case "$alg_mod_name" in
	*"$alg_ipsec"*)
		if [ "$_enable" = "true" ]; then
			help_iptables -t mangle -A IPsec -p udp --dport 500 -j ACCEPT
			help_iptables -t mangle -A IPsec -p udp --dport 4500 -j ACCEPT
			help_iptables -t mangle -A IPsec -p 50 -j ACCEPT
			help_iptables -t mangle -A IPsec -p 51 -j ACCEPT
		else
			help_iptables -t mangle -F IPsec
		fi
		;;
	*"$alg_ftp" | "$alg_tftp" | "$alg_pptp" | "$alg_sip" | "$alg_h323")
		_list="$alg_mod_name""_ALG_MOD"
		eval _list=\$$_list
		if [ "$_enable" = "true" ]; then
			if [ "$alg_mod_name" = "$alg_sip" ]; then
				help_iptables -t mangle -F SIP
				help_iptables -t mangle -A SIP -p tcp --sport 5060 -j SKIPFC
				help_iptables -t mangle -A SIP -p udp --sport 5060 -j SKIPFC
				help_iptables -t mangle -A SIP -p tcp --dport 5060 -j SKIPFC
				help_iptables -t mangle -A SIP -p udp --dport 5060 -j SKIPFC
			fi
			_cmd="insmod "
			modlist="$_list"
		else
			[ "$alg_mod_name" = "$alg_sip" ] && help_iptables -t mangle -F SIP
			_cmd="rmmod "
			reverse_list modlist "$_list"
		fi
		read _ _ _v _ </proc/version
		for mod in $modlist; do
			[ "$_cmd" = "insmod " -a -d /sys/module/"${mod%.*}" ] && continue
			[ "$_cmd" = "rmmod " -a ! -d /sys/module/"${mod%.*}" ] && continue
			$_cmd /lib/modules/${_v%-}/"$mod".ko
			ret=$?
		done
		;;
	esac
	return $ret
}
service_reconf() {
	local _path="$1" _status="$2" _enable="$3"
	if [ ! -d /tmp/init_iptables ]; then
		cmclient -v c GETO Device.QoS.Classification.[App="$obj"]
		for c in $c; do
			cmclient SET "$c".[Enable=true].Enable true
		done
	fi
	case "$newProtocolIdentifier" in
	"")
		alg_mod_name=""
		;;
	*"$ALG_FTP_PROTO_ID"*)
		alg_mod_name="$alg_ftp"
		;;
	*"$ALG_TFTP_PROTO_ID"*)
		alg_mod_name="$alg_tftp"
		;;
	*"$ALG_PPTP_PROTO_ID"*)
		alg_mod_name="$alg_pptp"
		;;
	*"$ALG_IPSEC_PROTO_ID"*)
		alg_mod_name="$alg_ipsec"
		;;
	*"$ALG_SIP_PROTO_ID"*)
		alg_mod_name="$alg_sip"
		;;
	*"$ALG_H323_PROTO_ID"*)
		alg_mod_name="$alg_h323"
		;;
	*)
		echo "ALG: Not yet Supported"
		;;
	esac
	alg_cmd "$newEnable"
	_ret=$?
	if [ $_ret -eq 0 ]; then
		[ "$newEnable" = "true" ] &&
			cmclient SETE "$obj.Status" "Enabled" ||
			cmclient SETE "$obj.Status" "Disabled"
	else
		cmclient SETE "$obj.Status" "Error"
	fi
}
service_delete() {
	alg_cmd "false"
	_ret=$?
	[ $_ret -eq 0 ] &&
		cmclient SETE "$obj.Status" "Disabled" ||
		cmclient SETE "$obj.Status" "Error"
}
service_config() {
	[ "$setEnable" = "1" ] && service_reconf
}
case "$op" in
s)
	service_config
	;;
d)
	service_delete
	;;
esac
exit 0
