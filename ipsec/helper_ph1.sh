#!/bin/sh

command -v help_strextract >/dev/null || . /etc/ah/helper_functions.sh
command -v help_iptables >/dev/null || . /etc/ah/helper_firewall.sh
command -v help_getfilter >/dev/null || . /etc/ah/helper_ipsec.sh
command -v help_last_ip > /dev/null || . /etc/ah/helper_ipcalc.sh

helper_l2tp_policy() {
	local laddr="$1" raddr="$2" cmd="$3" tmp_policy

	tmp_policy="$IPSEC_PATH/dynspd_$raddr"
	help_gentransportsp "$cmd" "$laddr" "$raddr" "1701" "1701" > "$tmp_policy"
	setkey -f "$tmp_policy"
	rm "$tmp_policy"
}

helper_restricted_subnet() {
	local ev_msg="$1" remote_id="$2" _dst_addr _dst_mask objs obj

	## XXX, it would be good to verify if PSK matches, but racoon don't pass this information
	cmclient -v objs GETO Device.IPsec.X_ADB_Security.[Enable=true].[Side=Remote].[IdentifierValue="$remote_id"].[RestrictedAddress!""]
	[ ${#objs} -eq 0 ] && return

	_chain="${FW_CHAIN_PREFIX}_${remote_id}_${INTERNAL_ADDR4##*.}"

	case "$ev_msg" in
		"phase1_up")
			help_iptables -t "$FW_TABLE_FILTER" -N "$_chain"
			## Currently it is possible to create multiple security objects with the same IdentifierValue.
			## Handle it here by allowing access to multiple IP addresses.
			## XXX, there could be some potential issues with it (like problem when objects have same IdentifierValue, but different PSKs).
			for obj in $objs; do
				cmclient -v _dst_addr GETV "$obj.RestrictedAddress"
				cmclient -v _dst_mask GETV "$obj.RestrictedSubnet"
				: ${_dst_mask:=255.255.255.255}

				help_iptables -t "$FW_TABLE_FILTER" -A "$_chain" -s "$INTERNAL_ADDR4" -d "${_dst_addr}/${_dst_mask}" -j ACCEPT
			done
			help_iptables -t "$FW_TABLE_FILTER" -A "$_chain" -s "$INTERNAL_ADDR4" -j DROP
			ipsec_firewall_link_chain "$_chain"
			;;
		"phase1_down")
			ipsec_firewall_link_chain "$_chain" "D"
			help_iptables -t "$FW_TABLE_FILTER" -F "$_chain"
			help_iptables -t "$FW_TABLE_FILTER" -X "$_chain"
			;;
	esac
}

helper_dynamicsp() {
	local ev_msg="$1" cmd spgen fobj="$5" \
		tun_src="$2" tun_dst="$3" trf_src trf_smask trf_dst="$4" trf_dmask="255.255.255.255"

	cmclient -v trf_src GETV ${fobj}.SourceIP
	if [ -z "$trf_src" ]; then
		local fiface
		cmclient -v fiface GETV ${fobj}.Interface
		case $fiface in
			"Device.IP.Interface"*)
				cmclient -v trf_src GETV "$fiface.IPv4Address.1.IPAddress"
				cmclient -v trf_smask GETV "$fiface.IPv4Address.1.SubnetMask"
				help_calc_network trf_src "$trf_src" "$trf_smask"
				[ -z "$trf_src" ] && return
				;;
			*)
				return
				;;
		esac
	fi

	help_subnet_dot2slash "trf_smask" "$trf_smask"
	help_subnet_dot2slash "trf_dmask" "$trf_dmask"

	case "$ev_msg" in
		"phase1_up")	cmd=spdadd	;;
		"phase1_down")	cmd=spddelete	;;
	esac

	tmp_policy="$IPSEC_PATH/dynspd_$tun_dst"
	help_gentunnelsp "$cmd" "$tun_src" "$tun_dst" "$trf_src" "$trf_smask" "$trf_dst" "$trf_dmask" > "$tmp_policy"
	setkey -f "$tmp_policy"
	rm "$tmp_policy"
}

