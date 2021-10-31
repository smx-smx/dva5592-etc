#!/bin/sh
AH_NAME="UserInterface"
case "$obj" in
Device.IP.Interface.*)
	exit 0
	;;
esac
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_svc.sh
. /etc/ah/helper_conflicts.sh
. /etc/ah/helper_hosts.sh
. /etc/ah/IPv6_helper_firewall.sh
cmclient -v ipv6_global GETV Device.IP.IPv6Enable
if [ "$obj" = "Device.UserInterface" ]; then
	[ "$changedX_ADB_IndexPage" = "1" ] &&
		cmclient SETM "Device.UserInterface.RemoteAccess.X_ADB_Reset=true	Device.UserInterface.X_ADB_LocalAccess.Reset=true"
	exit 0
fi
keySecLevel='normal'
[ "$keySecLevel" = 'high' ] && serialize_timeout=180
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize "${AH_NAME}${obj}" $serialize_timeout
[ -d /tmp/init_iptables ] && exit 0
if [ "$obj" = "Device.UserInterface.RemoteAccess" ]; then
	remote=1
	local=0
	chainSuffix="Remote"
	protocols="$newX_ADB_ProtocolsEnabled"
	interface="$newX_ADB_Interface"
	upstream="true"
	if help_is_in_list "$protocols" "HTTP"; then
		[ "$newPort" != "0" ] && HTTPPrimaryPort="$newPort"
		[ "$newX_ADB_SecondaryPort" != "0" ] && HTTPSecondaryPort="$newX_ADB_SecondaryPort"
	fi
	if help_is_in_list "$protocols" "HTTPS"; then
		[ "$newX_ADB_HTTPSPort" != "0" ] && HTTPSPrimaryPort="$newX_ADB_HTTPSPort"
		[ "$newX_ADB_SecondaryHTTPSPort" != "0" ] && HTTPSSecondaryPort="$newX_ADB_SecondaryHTTPSPort"
	fi
	if help_is_changed Enable Port X_ADB_Interface X_ADB_SecondaryPort X_ADB_HTTPSPort X_ADB_SecondaryHTTPSPort X_ADB_AccessControlEnable; then
		help_reconfigure_nat_conflicts "$newX_ADB_Interface"
		help_is_changed X_ADB_Interface && help_reconfigure_nat_conflicts "$oldX_ADB_Interface"
	fi
	HTTPSUniqueKey="$newX_ADB_HTTPSUniqueKey"
else
	remote=0
	local=1
	chainSuffix="Local"
	protocols="$newProtocolsEnabled"
	interface="$newInterface"
	upstream="false"
	if help_is_in_list "$protocols" "HTTP"; then
		[ "$newPort" != "0" ] && HTTPPrimaryPort="$newPort"
		[ "$newSecondaryPort" != "0" ] && HTTPSecondaryPort="$newSecondaryPort"
	fi
	if help_is_in_list "$protocols" "HTTPS"; then
		[ "$newHTTPSPort" != "0" ] && HTTPSPrimaryPort="$newHTTPSPort"
		[ "$newSecondaryHTTPSPort" != "0" ] && HTTPSSecondaryPort="$newSecondaryHTTPSPort"
	fi
	if help_is_changed Enable Port Interface SecondaryPort HTTPSPort SecondaryHTTPSPort X_ADB_AccessControlEnable; then
		help_reconfigure_nat_conflicts "$newInterface"
		help_is_changed Interface && help_reconfigure_nat_conflicts "$oldInterface"
	fi
	HTTPSUniqueKey="$newHTTPSUniqueKey"
fi
if [ ${#HTTPPrimaryPort} -gt 0 ]; then
	help_check_conflicts "$remote" "${interface}" "${HTTPPrimaryPort}" || exit 1
fi
if [ ${#HTTPSecondaryPort} -gt 0 ]; then
	help_check_conflicts "$remote" "${interface}" "${HTTPSecondaryPort}" || exit 1
fi
if [ ${#HTTPSPrimaryPort} -gt 0 ]; then
	help_check_conflicts "$remote" "${interface}" "${HTTPSPrimaryPort}" || exit 1
fi
if [ ${#HTTPSSecondaryPort} -gt 0 ]; then
	help_check_conflicts "$remote" "${interface}" "${HTTPSSecondaryPort}" || exit 1
fi
dports="${HTTPPrimaryPort},${HTTPSecondaryPort},${HTTPSPrimaryPort},${HTTPSSecondaryPort}"
IFS=,
set -- $dports
unset IFS
local v=
for i; do v="${v%*,}${i:+,$i}"; done
dports="${v#,}"
help_iptables -t nat -F NATSkip_GUI${chainSuffix}
help_iptables_all -F GUI${chainSuffix}In
help_iptables_all -F GUI${chainSuffix}Out
if [ "$changedX_ADB_AccessControlEnable" = "1" ]; then
	rm -f /tmp/cfg/cache/iptables /tmp/cfg/cache/ip6tables
	[ "$newX_ADB_AccessControlEnable" = "true" ] && cmd_line=-A || cmd_line=-D
	help_iptables_all $cmd_line ServicesIn_LocalACLServices -j GUI${chainSuffix}In
	help_iptables_all $cmd_line OutputAllow_LocalACLServices -j GUI${chainSuffix}Out
fi
if [ "$newEnable" = "false" ]; then
	rm -f /tmp/httpd/${obj}*
	set -- /tmp/httpd/*
	if [ ! -e "$1" -a ! -L "$1" ]; then
		help_svc_stop httpd
	fi
	exit 0
fi
baseDirs="/ui /www/htdocs /www /tmp"
baseParameters="1 302 / 16"
baseParametersHttps="1 302 / 32"
baseHTTPScerts="/etc/certs/server.crt /etc/certs/server.key"
optHTTPScerts="/etc/certs/ca.pem"
optKeepAliveTimeHTTP="keep-alive-timeout=15"
optKeepAliveMaxReqsHTTP="keep-alive-max-request=15"
optKeepAliveTimeHTTPS="keep-alive-timeout=60"
optKeepAliveMaxReqsHTTPS="keep-alive-max-request=500"
optHttpsPriority_prefix="https-priority-string=PERFORMANCE"
optHttpsPriority_str=""
optIndexPage_prefix="index-page="
optIndexPage_page=""
httpd_tmpf_conf="/tmp/httpd_tmp_conf"
optHostIP='host-ip-address'
optHostName='host-name'
cmclient -v optIndexPage_page GETV "Device.UserInterface.X_ADB_IndexPage"
help_iptables_all -A GUI${chainSuffix}In ! -p tcp -j RETURN
help_iptables_all -A GUI${chainSuffix}In -p tcp -m multiport ! --dports ${dports} -j RETURN
help_iptables_all -A GUI${chainSuffix}In -p tcp -m mark --mark 0xffff/0xffff -j RETURN
help_iptables_all -A GUI${chainSuffix}Out ! -p tcp -j RETURN
help_iptables_all -A GUI${chainSuffix}Out -p tcp -m multiport ! --sports ${dports} -j RETURN
help_iptables -R GUI${chainSuffix}In_ 1 -s 0.0.0.1/32 -d 0.0.0.1/32 -j DROP
help_ip6tables -R GUI${chainSuffix}In_ 1 -s ::/128 -d ::/128 -j DROP
help_ip6tables -R GUI${chainSuffix}Out_ 1 -s ::/128 -d ::/128 -j DROP
resolve_hostnames() {
	[ "$1" != 'namelist' ] && local namelist
	[ "$1" != 'addr' ] && local addr
	[ "$1" != 'host' ] && local host
	[ "$1" != 'name' ] && local name
	namelist=''
	cmclient -v host GETO 'Device.Hosts.X_ADB_HostName'
	for host in $host; do
		while read addr name; do
			if [ "$addr" = '127.0.0.1' -o "$addr" = "$2" ]; then
				for name in $name; do
					namelist="${namelist:+$namelist,}${name}"
				done
			fi
			addr=''
			name=''
		done <<-EOF
			$(help_resolve_hostname "$host")
		EOF
	done
	eval "$1"='$namelist'
}
configure_if_rule() {
	local remote=$1 type_local=$2 chainSuffix=$3 \
		iface=$4 dports=$5 ipv6_global=$6 ifname=$7 \
		a ip6 dst="" src="" has_ifname if_ipv4addr='' if_hostname='' tmp
	[ -d /sys/class/net/${ifname} ] && has_ifname='true' || has_ifname='false'
	[ "$has_ifname" = 'true' ] && listenIf="${listenIf} $ifname"
	rm -f /tmp/resolve_${ifname}.tmp
	cmclient -v a GETV "$iface.[Enable=true].IPv4Address.[Enable=true].IPAddress"
	case "$ifname" in
	ppp*) ;;
	*)
		dst="1"
		src="1"
		;;
	esac
	for a in $a; do
		if [ "$remote" = 1 -a "$newX_ADB_AccessControlEnable" = "true" ]; then
			help_iptables -t nat -A NATSkip_GUI${chainSuffix} -i ${ifname} ${dst:+-d $a} -p tcp -m multiport --dports ${dports} -j NATSkip_GUIRemote_ACL
		else
			help_iptables -t nat -A NATSkip_GUI${chainSuffix} -i ${ifname} ${dst:+-d $a} -p tcp -m multiport --dports ${dports} -j ACCEPT
		fi
		help_iptables -A GUI${chainSuffix}In -i ${ifname} ${dst:+-d $a} -j CONNMARK --set-mark 8/8
		help_iptables -A GUI${chainSuffix}In -i ${ifname} ${dst:+-d $a} -j GUI${chainSuffix}In_
		help_iptables -A GUI${chainSuffix}Out -o ${ifname} ${src:+-s $a} -j GUI${chainSuffix}Out_
		if [ "$has_ifname" = 'true' ]; then
			[ -z "$if_ipv4addr" ] && if_ipv4addr="$optHostIP=$a" ||
				if_ipv4addr="$if_ipv4addr,$a"
			resolve_hostnames 'tmp' "$a"
			if [ -n "$tmp" ]; then
				[ -z "$if_hostname" ] && if_hostname="$optHostName=$tmp" ||
					if_hostname="$if_hostname,$tmp"
			fi
		fi
	done
	[ "$chainSuffix" = "Local" ] && help_iptables -A GUILocalIn -i ${ifname} -j DROP
	if [ "$ipv6_global" = "true" ]; then
		cmclient -v ip6 GETV "$iface.[Enable=true].IPv6Address.[Enable=true].[IPAddressStatus=Preferred].IPAddress"
		for ip6 in $ip6; do
			help_ip6tables -A GUI${chainSuffix}In -i ${ifname} -d ${ip6} -j GUI${chainSuffix}In_
			help_ip6tables -A GUI${chainSuffix}Out -o ${ifname} -s ${ip6} -j GUI${chainSuffix}Out_
		done
	fi
	[ "$chainSuffix" = "Local" ] && help_ip6tables -A GUILocalIn -i ${ifname} -j DROP
	eval "ipv4addr_${ifname}"='$if_ipv4addr'
	eval "hostname_${ifname}"='$if_hostname'
}
configure_https_prioritystring() {
	TLSVersion="$1"
	optHttpsPriority_str="${optHttpsPriority_prefix}"
	case "$TLSVersion" in
	*Auto*)
		optHttpsPriority_str="${optHttpsPriority_str}:-VERS-SSL3.0"
		;;
	*)
		for version in TLS1.2 TLS1.1 TLS1.0 SSL3.0; do
			case "$TLSVersion" in
			*${version}*)
				optHttpsPriority_str="${optHttpsPriority_str}:+VERS-${version}"
				;;
			*)
				optHttpsPriority_str="${optHttpsPriority_str}:-VERS-${version}"
				;;
			esac
		done
		;;
	esac
	optHttpsPriority_str="${optHttpsPriority_str}:-ARCFOUR-128"
	optHttpsPriority_str="${optHttpsPriority_str}:-DHE-RSA"
}
listenIf=""
if [ -n "$interface" ]; then
	set -f
	IFS=","
	set -- $interface
	unset IFS
	set +f
	for intf; do
		cmclient -v ifstatus GETV $intf.Status
		if [ "$ifstatus" = "Up" ]; then
			help_lowlayer_ifname_get ifname "$intf"
			[ -z "$ifname" ] && continue
			configure_if_rule "$remote" "$local" "$chainSuffix" "$intf" "$dports" "$ipv6_global" "$ifname"
		fi
	done
else
	cmclient -v tmp GETV Device.IP.InterfaceNumberOfEntries
	if [ "$tmp" = "1" ]; then
		local uif_obj
		cmclient -v uif_obj GETO "Device.IP.Interface.[X_ADB_Upstream=true]"
		help_lowlayer_ifname_get brname "$uif_obj"
		[ "${brname%%[0-9]}" = "br" ] && upstream="true"
	fi
	cmclient -v i GETO Device.IP.Interface.[Enable=true].[X_ADB_Upstream=${upstream}].[Status=Up]
	for i in $i; do
		help_lowlayer_ifname_get ifname "$i"
		[ -z "$ifname" ] && continue
		configure_if_rule "$remote" "$local" "$chainSuffix" "$i" "$dports" "$ipv6_global" "$ifname"
	done
fi
if [ $remote -eq 1 ]; then
	cmclient -v TLSClientCheck_remote GETV Device.UserInterface.RemoteAccess.X_ADB_TLSClientCheck
	if [ -n "$TLSClientCheck_remote" ]; then
		[ "$TLSClientCheck_remote" = "All" ] &&
			TLSClientCheck_remote="CertInvalid,CertSignerNotFound,CertRevoked,CertExpired,CertNotActivated"
		optCA="${optHTTPScerts} ${TLSClientCheck_remote}"
	fi
	cmclient -v TLSVersion_remote GETV Device.UserInterface.RemoteAccess.X_ADB_TLSVersion
	if [ -n "$TLSVersion_remote" ]; then
		configure_https_prioritystring "$TLSVersion_remote"
	fi
fi
if [ $local -eq 1 ]; then
	cmclient -v TLSClientCheck_local GETV Device.UserInterface.X_ADB_LocalAccess.X_ADB_TLSClientCheck
	if [ -n "$TLSClientCheck_local" ]; then
		[ "$TLSClientCheck_local" = "All" ] &&
			TLSClientCheck_local="CertInvalid,CertSignerNotFound,CertRevoked,CertExpired,CertNotActivated"
		optCA="${optHTTPScerts} ${TLSClientCheck_local}"
	fi
	cmclient -v TLSVersion_local GETV Device.UserInterface.X_ADB_LocalAccess.X_ADB_TLSVersion
	if [ -n "$TLSVersion_local" ]; then
		configure_https_prioritystring "$TLSVersion_local"
	fi
fi
cfgHTTPSKey="/tmp/cfg/httpd/server.key"
cfgHTTPSCert="/tmp/cfg/httpd/server.crt"
tmpHTTPSKey="/tmp/httpd/certs/server.key"
tmpHTTPSCert="/tmp/httpd/certs/server.crt"
HTTPSCertpl="/etc/certs/server.tpl"
IFS=","
set -- $protocols
unset IFS
for p; do
	if [ "$p" = "HTTPS" ]; then
		if [ "$HTTPSUniqueKey" = "true" ]; then
			if [ ! -f "$cfgHTTPSKey" ]; then
				mkdir -p "${cfgHTTPSKey%/*}"
				https_utils --generate-privkey --outfile "$cfgHTTPSKey" \
					--sec-param $keySecLevel >/dev/console
				[ $? = 0 ] || rm "$cfgHTTPSKey"
			fi
			if [ ! -f "$cfgHTTPSCert" ]; then
				mkdir -p "${cfgHTTPSCert%/*}"
				cmclient -v sn GETV "Device.DeviceInfo.SerialNumber"
				cmclient -v mac GETV "Device.X_ADB_FactoryData.BaseMACAddress"
				rnd=$(tr -Cd "0-9" </dev/urandom | head -c 18)
				export sn mac rnd
				https_utils --generate-self-signed --outfile "$cfgHTTPSCert" \
					--load-privkey "$cfgHTTPSKey" \
					--template "$HTTPSCertpl" \
					--outfile "$cfgHTTPSCert" >/dev/console
				[ $? = 0 ] || rm "$cfgHTTPSCert"
			fi
			if [ -f "$cfgHTTPSKey" -a ! -f "$tmpHTTPSKey" ]; then
				mkdir -p -m 0755 "${tmpHTTPSKey%/*}"
				cp "$cfgHTTPSKey" "$tmpHTTPSKey"
				chmod 644 "$tmpHTTPSKey"
			fi
			if [ -f "$cfgHTTPSCert" -a ! -f "$tmpHTTPSCert" ]; then
				mkdir -p -m 0755 "${tmpHTTPSCert%/*}"
				cp "$cfgHTTPSCert" "$tmpHTTPSCert"
				chmod 644 "$tmpHTTPSCert"
			fi
			if [ -f "$tmpHTTPSCert" -a -f "$tmpHTTPSKey" ]; then
				baseHTTPScerts="$tmpHTTPSCert $tmpHTTPSKey"
			fi
		fi
		if [ -n "$HTTPSPrimaryPort" ]; then
			for i in $listenIf; do
				writtenFiles="${writtenFiles} /tmp/httpd/${obj}_https_pri_${i}"
				echo "$baseDirs $HTTPSPrimaryPort $i $baseParametersHttps $baseHTTPScerts $optCA" >$httpd_tmpf_conf
				echo "$optKeepAliveTimeHTTPS" >>$httpd_tmpf_conf
				echo "$optKeepAliveMaxReqsHTTPS" >>$httpd_tmpf_conf
				eval echo \$ipv4addr_${i} >>$httpd_tmpf_conf
				eval echo \$hostname_${i} >>$httpd_tmpf_conf
				[ ${#optHttpsPriority_str} -ne 0 ] && echo "$optHttpsPriority_str" >>$httpd_tmpf_conf
				[ ${#optIndexPage_page} -ne 0 ] && echo "$optIndexPage_prefix$optIndexPage_page" >>$httpd_tmpf_conf
				if [ "$setX_ADB_Reset" = "1" -o "$setReset" = "1" ] ||
					! help_is_equal_file "$httpd_tmpf_conf" "/tmp/httpd/${obj}_https_pri_${i}"; then
					mv $httpd_tmpf_conf /tmp/httpd/${obj}_https_pri_${i}
				fi
			done
		fi
		if [ -n "$HTTPSSecondaryPort" ]; then
			for i in $listenIf; do
				writtenFiles="${writtenFiles} /tmp/httpd/${obj}_https_sec_${i}"
				echo "$baseDirs $HTTPSSecondaryPort $i $baseParametersHttps $baseHTTPScerts $optCA" >$httpd_tmpf_conf
				echo "$optKeepAliveTimeHTTPS" >>$httpd_tmpf_conf
				echo "$optKeepAliveMaxReqsHTTPS" >>$httpd_tmpf_conf
				eval echo \$ipv4addr_${i} >>$httpd_tmpf_conf
				eval echo \$hostname_${i} >>$httpd_tmpf_conf
				[ ${#optHttpsPriority_str} -ne 0 ] && echo "$optHttpsPriority_str" >>$httpd_tmpf_conf
				[ ${#optIndexPage_page} -ne 0 ] && echo "$optIndexPage_prefix$optIndexPage_page" >>$httpd_tmpf_conf
				if [ "$setX_ADB_Reset" = "1" -o "$setReset" = "1" ] ||
					! help_is_equal_file "$httpd_tmpf_conf" "/tmp/httpd/${obj}_https_sec_${i}"; then
					mv $httpd_tmpf_conf /tmp/httpd/${obj}_https_sec_${i}
				else
					rm $httpd_tmpf_conf
				fi
			done
		fi
	elif [ "$p" = "HTTP" ]; then
		if [ -n "$HTTPPrimaryPort" ]; then
			for i in $listenIf; do
				writtenFiles="${writtenFiles} /tmp/httpd/${obj}_http_pri_${i}"
				echo "$baseDirs $HTTPPrimaryPort $i $baseParameters" >$httpd_tmpf_conf
				echo "$optKeepAliveTimeHTTP" >>$httpd_tmpf_conf
				echo "$optKeepAliveMaxReqsHTTP" >>$httpd_tmpf_conf
				eval echo \$ipv4addr_${i} >>$httpd_tmpf_conf
				eval echo \$hostname_${i} >>$httpd_tmpf_conf
				[ ${#optIndexPage_page} -ne 0 ] && echo "$optIndexPage_prefix$optIndexPage_page" >>$httpd_tmpf_conf
				if [ "$setX_ADB_Reset" = "1" -o "$setReset" = "1" ] ||
					! help_is_equal_file "$httpd_tmpf_conf" "/tmp/httpd/${obj}_http_pri_${i}"; then
					mv $httpd_tmpf_conf /tmp/httpd/${obj}_http_pri_${i}
				else
					rm $httpd_tmpf_conf
				fi
			done
		fi
		if [ -n "$HTTPSecondaryPort" ]; then
			for i in $listenIf; do
				writtenFiles="${writtenFiles} /tmp/httpd/${obj}_http_sec_${i}"
				echo "$baseDirs $HTTPSecondaryPort $i $baseParameters" >$httpd_tmpf_conf
				echo "$optKeepAliveTimeHTTP" >>$httpd_tmpf_conf
				echo "$optKeepAliveMaxReqsHTTP" >>$httpd_tmpf_conf
				eval echo \$ipv4addr_${i} >>$httpd_tmpf_conf
				eval echo \$hostname_${i} >>$httpd_tmpf_conf
				[ ${#optIndexPage_page} -ne 0 ] && echo "$optIndexPage_prefix$optIndexPage_page" >>$httpd_tmpf_conf
				if [ "$setX_ADB_Reset" = "1" -o "$setReset" = "1" ] ||
					! help_is_equal_file "$httpd_tmpf_conf" "/tmp/httpd/${obj}_http_sec_${i}"; then
					mv $httpd_tmpf_conf /tmp/httpd/${obj}_http_sec_${i}
				else
					rm $httpd_tmpf_conf
				fi
			done
		fi
	fi
done
[ "$newEnable" = "true" -a "$newX_ADB_AccessControlEnable" = "true" ] &&
	cmclient SET -u "${tmpiptablesprefix##*/}" "${obj}".X_ADB_ACLRule.[Enable=true].[Status=Disabled].Refresh true
if [ "$newX_ADB_AccessControlEnable" = "true" ]; then
	help_iptables -R GUI${chainSuffix}In_ 1 -s 0.0.0.1/32 -d 0.0.0.1/32 -j DROP
	help_iptables -R GUI${chainSuffix}Out_ 1 -s 0.0.0.1/32 -d 0.0.0.1/32 -j DROP
	help_ip6tables -R GUI${chainSuffix}In_ 1 -s ::/128 -d ::/128 -j DROP
else
	help_iptables_all -R GUI${chainSuffix}In_ 1 -j ACCEPT
	help_iptables_all -R GUI${chainSuffix}Out_ 1 -j ACCEPT
fi
for i in /tmp/httpd/${obj}*; do
	case "$writtenFiles" in
	*"$i"*) ;;

	*)
		rm $i
		;;
	esac
done
if ! pgrep httpd; then
	help_svc_start "httpd -u nobody"
fi
exit 0
