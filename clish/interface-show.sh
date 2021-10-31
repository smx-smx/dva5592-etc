#!/bin/sh
. /etc/clish/clish-commons.sh
. /etc/ah/IPv6_helper_functions.sh 2>/dev/null
get_alias() {
	cmclient GETV "$1.Alias"
}
get_show_tr_list() {
	local iface="$1"
	local tr_each tr_all
	if [ "$iface" = "all" ]; then
		shift
		for each_tr; do
			[ "$each_tr" = "Device.WiFi.SSID" ] &&
				cmclient_GETO_Access each_tr "$each_tr" 1 ||
				cmclient -v each_tr GETO "$each_tr"
			tr_all="${tr_all:+$tr_all }$each_tr"
		done
	else
		tr_all="$(cli_or_tr_alias_to_tr_obj "$iface")"
	fi
	[ -n "$tr_all" ] && echo "$tr_all" || die "ERROR: $iface is not found"
}
show_everything() {
	local show_function="$1"
	local argument_list="$2"
	local each_argument
	for each_argument in $argument_list; do
		eval $show_function '"$each_argument"'
	done
}
oneline_get_value() {
	local tr_path="$1"
	local result
	cmclient -v result GETV "$tr_path"
	echo "$result"
}
interface_show_stats() {
	local this="$1"
	local rx tx status i
	cmclient -v status GETV "$this.Status"
	cmclient -v alias_name GETV "${this%%.Port.*}.Alias"
	[ "${status}" != "Up" ] && echo "ERROR: $alias_name is not UP. Stats is not available"
	return
	echo
	echo "Statistics for $alias_name:"
	print_horizontal_line 79
	print_3_col_row "" "Sent" "Received"
	print_horizontal_line 79
	for i in Bytes Packets Errors; do
		cmclient -v rx GETV "${this}.Stats.${i}Received"
		cmclient -v tx GETV "${this}.Stats.${i}Sent"
		print_3_col_row "$i" "$rx" "$tx"
	done
	print_horizontal_line 79
}
is_eth_under_bridge() {
	local tr_iface="$1"
	local bridge=""
	cmclient -v bridge GETO "Device.Bridging.Bridge.*.[Port.*.LowerLayers=$tr_iface]"
	cmclient -v br_alias GETV "${bridge%%.Port*}.Alias"
	cmclient -v iface_alias GETV "${tr_iface}.Alias"
	[ -n "$bridge" ] && printf "\n%s is a part of %s bridge.\n" "${iface_alias}" "${br_alias}"
}
interface_vlan_show() {
	local vlan_obj="$1"
	local vlan_id
	local tmp_var i
	cmclient -v vlan_id GETV "${vlan_obj}.Alias"
	echo
	show_split_text "VLAN" "$vlan_id"
	print_horizontal_line
	for i in Enable Status VLANID; do
		show_from_cm "$vlan_obj" "$i"
	done
	show_split_text "LowerLayers" "${vlan_id%%.*}"
	cmclient -v tmp_var GETV "$vlan_obj.X_ADB_8021pPrio"
	[ "$tmp_var" = "-1" ] && tmp_var="-"
	show_split_text "X_ADB_8021pPrio" "$tmp_var"
	print_horizontal_line
	interface_show_stats "$vlan_obj"
	is_eth_under_bridge "$vlan_obj"
	interface_ppp_show_by_ll "$vlan_obj"
	interface_ip_show "$vlan_obj"
	echo
}
interface_ethernet_show() {
	local ethernet_obj="$1"
	local tmp_var i
	cmclient -v eth_alias GETV "${ethernet_obj}.Alias"
	echo
	show_split_text "Ethernet" "${eth_alias}"
	print_horizontal_line
	for i in Enable Status Upstream MACAddress DuplexMode \
		X_ADB_RateSupported X_ADB_STP X_ADB_MediaType; do
		show_from_cm "$ethernet_obj" "$i"
	done
	cmclient -v tmp_var GETV "$ethernet_obj.MaxBitRate"
	[ "$tmp_var" = "-1" ] && tmp_var="Auto"
	show_split_text "MaxBitRate" "$tmp_var"
	print_horizontal_line
	interface_show_stats "$ethernet_obj"
	is_eth_under_bridge "$ethernet_obj"
	interface_ethernet_link_show "$ethernet_obj"
	echo
}
interface_pppoe_show() {
	local this="$1"
	echo
	echo "PPPoE:"
	print_horizontal_line
	for i in \
		SessionID ACName ServiceName \
		X_ADB_LocalMACAddress X_ADB_RemoteMACAddress; do
		show_from_cm "$this.PPPoE" "$i"
	done
	print_horizontal_line
}
interface_ppp_auth_show() {
	local this="$1"
	local i
	echo
	echo "Authorization:"
	print_horizontal_line
	for i in \
		AuthenticationProtocol X_ADB_CurrentAuthenticationProtocol \
		Username; do
		show_from_cm "$this" "$i"
	done
	print_horizontal_line
}
interface_ppp_show() {
	local this="$1"
	local this_alias
	local i low status
	local is_pppoe=0
	local old_default_col_width="$DEFAULT_FIRST_COL_WIDTH"
	DEFAULT_FIRST_COL_WIDTH="45"
	echo
	cmclient -v this_alias GETV "${this}.Alias"
	echo
	show_split_text "PPP" "$this_alias:"
	print_horizontal_line
	for i in Enable Status ConnectionStatus \
		LastConnectionError AutoDisconnectTime \
		IdleDisconnectTime EncryptionProtocol CompressionProtocol \
		MaxMRUSize CurrentMRUSize ConnectionTrigger \
		LCPEcho LCPEchoRetry IPCPEnable IPv6CPEnable \
		X_ADB_PayloadCompressionProtocol \
		X_ADB_PayloadCompressionProtocolMaxCodeSize; do
		show_from_cm "$this" "$i"
	done
	cmclient -v low GETV "$this.LowerLayers"
	cmclient -v status GETV "$this.ConnectionStatus"
	if [ "${low%.*}" = "Device.Ethernet.Link" ]; then
		cmclient -v low GETV "$low.LowerLayers"
	fi
	cmclient -v low_alias GETV "${low}.Alias"
	print_2_col_row "Interface" "$low_alias"
	case "$low" in
	Device.ATM.Link*)
		print_2_col_row "PPP Type" "PPPoA"
		;;
	*)
		print_2_col_row "PPP Type" "PPPoE"
		is_pppoe=1
		;;
	esac
	print_horizontal_line
	interface_ppp_auth_show "$this"
	[ "$is_pppoe" -eq 1 ] && interface_pppoe_show "$this"
	if [ "$status" = "Connected" ]; then
		local ipcp
		cmclient -v ipcp GETV "$this.IPCPEnable"
		[ "$ipcp" = "true" ] && interface_ipcp_show "$this"
		cmclient -v ipcp GETV "$this.IPv6CPEnable"
		[ "$ipcp" = "true" ] && interface_ipv6cp_show "$this"
	fi
	DEFAULT_FIRST_COL_WIDTH="$old_default_col_width"
	interface_ip_show "$this"
	interface_show_stats "$this"
	echo
}
interface_ppp_show_by_ll() {
	local this i
	local input_id="$1"
	cmclient -v this GETO "Device.PPP.Interface.*.[LowerLayers=$input_id]"
	[ -z "$this" -o -z "$input_id" ] && return 1
	for i in $this; do
		interface_ppp_show "$i"
	done
}
interface_ethernet_link_show() {
	local ll="$1"
	local i obj
	[ -n "$ll" ] || return
	cmclient -v obj GETO "Device.Ethernet.Link.*.[LowerLayers=$ll]"
	for i in $obj; do
		interface_ppp_show_by_ll "$i"
		interface_ip_show "$i"
	done
}
interface_bridge_show() {
	local bridge_obj="$1"
	local printf_args="%-7s | %-7s | %-15s | %-10s | %-15s | %-7s\n"
	local obj_man_port objs obj tmp_obj i
	echo
	cmclient -v obj_man_port GETO "${bridge_obj}.Port.*.[ManagementPort=true]"
	[ -z "$obj_man_port" ] && printf "ERROR: Management port for bridge $(get_alias $bridge_obj) is not found\n" && return 0
	show_split_text "Bridge" "$(get_alias $bridge_obj)"
	print_horizontal_line "75"
	for i in Enable Status Standard X_ADB_AllowLANRouting \
		X_ADB_MulticastIsolation X_ADB_Mediaroom; do
		show_from_cm "$bridge_obj" "$i"
	done
	print_horizontal_line "75"
	echo
	echo "Ports:"
	print_horizontal_line "75"
	printf "$printf_args" "Name" "Alias" "ManagementPort" "Interface" "Status" "Enable"
	print_horizontal_line "75"
	printf "$printf_args" \
		"$(oneline_get_value ${obj_man_port}.Name)" \
		"$(oneline_get_value ${obj_man_port}.Alias)" \
		"$(oneline_get_value ${obj_man_port}.ManagementPort)" \
		"" \
		"$(oneline_get_value ${obj_man_port}.Status)" \
		"$(oneline_get_value ${obj_man_port}.Enable)"
	cmclient -v objs GETV "${obj_man_port}.LowerLayers"
	if [ -n "$objs" ]; then
		for obj in $(list_print "$objs"); do
			cmclient -v tmp_obj GETV "${obj}.LowerLayers"
			printf "$printf_args" \
				"" \
				"$(oneline_get_value ${obj}.Alias)" \
				"$(oneline_get_value ${obj}.ManagementPort)" \
				"$(get_alias $tmp_obj)" \
				"$(oneline_get_value ${obj}.Status)" \
				"$(oneline_get_value ${obj}.Enable)"
		done
	fi
	print_horizontal_line "75"
	echo
	echo "VLANs:"
	cmclient -v objs GETO "${bridge_obj}.VLAN"
	if [ -n "$objs" ]; then
		print_horizontal_line "75"
		printf_args="%-10s | %-10s | %-10s | %-10s\n"
		printf "$printf_args" "Alias" "Name" "VLAN ID" "Enable"
		print_horizontal_line "75"
		for obj in $objs; do
			printf "$printf_args" \
				"$(oneline_get_value ${obj}.Alias)" \
				"$(oneline_get_value ${obj}.Name)" \
				"$(oneline_get_value ${obj}.VLANID)" \
				"$(oneline_get_value ${obj}.Enable)"
		done
	fi
	print_horizontal_line "75"
	echo
	echo "VLAN ports:"
	cmclient -v objs GETO "${bridge_obj}.VLANPort"
	if [ -n "$objs" ]; then
		print_horizontal_line "75"
		printf_args="%-10s | %-10s | %-10s | %-10s | %-10s\n"
		printf "$printf_args" "Alias" "Untagged" "VLAN" "Port" "Enable"
		print_horizontal_line "75"
		local tmp_vlan tmp_port
		for obj in $objs; do
			cmclient -v tmp_vlan GETV "${obj}.VLAN"
			cmclient -v tmp_port GETV "${obj}.Port"
			printf "$printf_args" \
				"$(oneline_get_value ${obj}.Alias)" \
				"$(oneline_get_value ${obj}.Untagged)" \
				"$(oneline_get_value ${tmp_vlan}.Alias)" \
				"$(oneline_get_value ${tmp_port}.Alias)" \
				"$(oneline_get_value ${obj}.Enable)"
		done
	fi
	print_horizontal_line "75"
	echo
	echo "Filters:"
	cmclient -v i GETV "${bridge_obj}.Standard"
	if [ "${i}" = "802.1D-2004" ]; then
		cmclient -v objs GETO "Device.Bridging.Filter.*.[Bridge=$bridge_obj]"
	else
		cmclient -v tmp_obj GETO "${bridge_obj}.VLAN"
		objs=""
		for obj in $tmp_obj; do
			cmclient -v obj GETO "Device.Bridging.Filter.*.[Bridge=$obj]"
			objs="${objs:+$objs }$obj"
		done
	fi
	if [ -n "$objs" ]; then
		print_horizontal_line "75"
		printf_args="%-10s | %-10s | %-10s | %-10s\n"
		printf "$printf_args" "Alias" "Interface" "Status" "Enable"
		print_horizontal_line "75"
		for obj in $objs; do
			cmclient -v tmp_obj GETV "${obj}.Interface"
			printf "$printf_args" \
				"$(oneline_get_value ${obj}.Alias)" \
				"$(get_alias ${tmp_obj%%.Port*})" \
				"$(oneline_get_value ${obj}.Status)" \
				"$(oneline_get_value ${obj}.Enable)"
		done
	fi
	print_horizontal_line "75"
	echo
	interface_ip_show "$bridge_obj"
	echo
}
interface_dot11radio_show() {
	local radio_obj="$1"
	local tmp_param i
	local old_default_col_width="$DEFAULT_FIRST_COL_WIDTH"
	DEFAULT_FIRST_COL_WIDTH="35"
	echo
	show_split_text "Radio" "$(get_alias $radio_obj)"
	print_horizontal_line
	for i in Enable Status AutoChannelSupported \
		AutoChannelRefreshPeriod AutoChannelEnable \
		ChannelsInUse Channel OperatingStandards Upstream \
		MaxBitRate OperatingFrequencyBand IEEE80211hSupported \
		IEEE80211hEnabled RegulatoryDomain \
		X_ADB_BasicDataTransmitRates \
		X_ADB_OperationalDataTransmitRates X_ADB_MulticastRate2G \
		X_ADB_WMMGlobalEnable X_ADB_WMMGlobalNoAck; do
		show_from_cm "$radio_obj" "$i"
	done
	cmclient -v tmp_param GETV "$radio_obj.TransmitPower"
	[ "$transmit_power" = "-1" ] && tmp_param="Auto"
	show_split_text "TransmitPower" "$tmp_param"
	for i in X_ADB_gmodeProtection X_ADB_nProtection GuardInterval \
		OperatingChannelBandwidth ExtensionChannel X_ADB_AMPDU \
		X_ADB_STBC_Rx X_ADB_STBC_Tx; do
		show_from_cm "$radio_obj" "$i"
	done
	cmclient -v tmp_param GETV "$radio_obj.MCS"
	[ "$tmp_param" = "-1" ] && tmp_param="Auto"
	show_split_text "MCS" "$tmp_param"
	print_horizontal_line
	echo
	DEFAULT_FIRST_COL_WIDTH="$old_default_col_width"
}
interface_ap_wps_show() {
	local ap_obj="$1"
	local wps_obj i
	[ "${ap_obj%.*}" = "Device.WiFi.SSID" ] && cmclient -v ap_obj GETO "Device.WiFi.AccessPoint.*.[SSIDReference=$ap_obj]"
	wps_obj="$ap_obj.WPS"
	[ -z "$ap_obj" ] && return 1
	echo
	echo "WPS:"
	print_horizontal_line
	for i in Enable ConfigMethodsSupported ConfigMethodsEnabled X_ADB_Status X_ADB_ConfigurationState; do
		show_from_cm "$wps_obj" "$i"
	done
	print_horizontal_line
}
interface_ap_sequrity_show() {
	local ap_obj="$1"
	local security_obj security_mode i
	[ "${ap_obj%.*}" = "Device.WiFi.SSID" ] && cmclient -v ap_obj GETO "Device.WiFi.AccessPoint.*.[SSIDReference=$ap_obj]"
	security_obj="$ap_obj.Security"
	[ -z "$ap_obj" ] && return 1
	cmclient -v security_mode GETV "$security_obj.ModeEnabled"
	echo "Security mode: $security_mode"
	[ "$security_mode" = "None" ] || print_horizontal_line
	case "$security_mode" in
	"WEP"*)
		show_from_cm "$security_obj" "X_ADB_WEPKeyMode"
		print_horizontal_line
		;;
	"WPA"*"Personal")
		for i in RekeyingInterval X_ADB_EncryptionMode; do
			show_from_cm "$security_obj" "$i"
		done
		print_horizontal_line
		;;
	"WPA"*"Enterprise")
		local old_default_col_width="$DEFAULT_FIRST_COL_WIDTH"
		DEFAULT_FIRST_COL_WIDTH="35"
		for i in \
			RekeyingInterval \
			RadiusServerIPAddr RadiusServerPort \
			SecondaryRadiusServerIPAddr SecondaryRadiusServerPort; do
			show_from_cm "$security_obj" "$i"
		done
		DEFAULT_FIRST_COL_WIDTH="$old_default_col_width"
		print_horizontal_line
		;;
	"None")
		:
		;;
	*)
		echo "Mode $security_mode not yet supported"
		;;
	esac
}
interface_wifi_show() {
	local ssid_obj="$1"
	local old_default_col_width="$DEFAULT_FIRST_COL_WIDTH"
	local ap_obj i status
	cmclient -v ap_obj GETO "Device.WiFi.AccessPoint.*.[SSIDReference=$ssid_obj]"
	DEFAULT_FIRST_COL_WIDTH="35"
	[ -z "$ssid_obj" -o -z "$ap_obj" ] && return 0
	echo
	show_split_text "WIFI" "$(get_alias $ssid_obj)"
	print_horizontal_line
	for i in Enable Status SSIDAdvertisementEnabled RetryLimit \
		WMMCapability UAPSDCapability WMMEnable UAPSDEnable \
		AssociatedDeviceNumberOfEntries X_ADB_LongRetryLimit \
		X_ADB_MaxAssocLimit X_ADB_MulticastToUnicastEnable X_ADB_APIsolation \
		X_ADB_WirelessSegregation X_ADB_LocationDescription; do
		show_from_cm "$ap_obj" "$i"
	done
	for i in BSSID MACAddress SSID X_ADB_MacMode; do
		show_from_cm "$ssid_obj" "$i"
	done
	print_horizontal_line
	echo
	interface_ap_sequrity_show "$ap_obj"
	interface_ap_wps_show "$ap_obj"
	DEFAULT_FIRST_COL_WIDTH="$old_default_col_width"
	cmclient -v status GETV "$ssid_obj.Status"
	[ "${status}" = "Up" ] && interface_show_stats "$ssid_obj"
	is_eth_under_bridge "$ssid_obj"
	echo
	local ip="$(ll_obj_to_ip_obj $ssid_obj)"
	[ -n "$ip" ] && interface_ip_show_table "$ip"
	echo
}
interface_xdsl_show() {
	local dsl_line_obj="$1"
	local i
	echo
	show_split_text "DSL" "$(get_alias $dsl_line_obj)"
	print_horizontal_line
	for i in Enable Status AllowedProfiles CurrentProfile Upstream \
		LinkStatus StandardsSupported StandardsUsed UpstreamMaxBitRate \
		DownstreamMaxBitRate UpstreamNoiseMargin DownstreamNoiseMargin \
		FirmwareVersion PowerManagementState SNRMpbus SNRMpbdsTRELLISds TRELLISus LineNumber UpstreamAttenuation DownstreamAttenuation \
		UpstreamPower DownstreamPower XTURVendor XTURCountry XTUCVendor \
		XTUCCountry X_ADB_AllowedStandards X_ADB_XTURModelShort X_ADB_SRA \
		X_ADB_G992DTF X_ADB_V43 X_ADB_BitSwap X_ADB_PhyR X_ADB_GINP \
		X_ADB_MonitorTone X_ADB_ToggleJ43B43 X_ADB_Annex; do
		show_from_cm "$dsl_line_obj" "$i"
	done
	print_horizontal_line
	echo
}
interface_atm_show() {
	local atm_obj="$1"
	local link_type i
	local old_default_col_width="$DEFAULT_FIRST_COL_WIDTH"
	DEFAULT_FIRST_COL_WIDTH="35"
	echo
	show_split_text "ATM" "$(get_alias $atm_obj)"
	print_horizontal_line
	for i in Enable Status AAL LinkType DestinationAddress Encapsulation \
		QoS.QoSClass QoS.PeakCellRate QoS.SustainableCellRate \
		QoS.MaximumBurstSize VCSearchList FCSPreserved X_ADB_DisableOAMPing; do
		show_from_cm "$atm_obj" "$i"
	done
	show_split_text "LowerLayers" "$(get_alias $(ip_interface_get_cli_ll $atm_obj))"
	print_horizontal_line
	DEFAULT_FIRST_COL_WIDTH="$old_default_col_width"
	interface_show_stats "$atm_obj"
	cmclient -v link_type GETV "$atm_obj.LinkType"
	case "$link_type" in
	EoA)
		interface_ethernet_link_show "$atm_obj"
		;;
	IPoA)
		interface_ip_show "$atm_obj"
		;;
	PPPoA)
		interface_ppp_show_by_ll "$atm_obj"
		;;
	esac
	echo
}
interface_ptm_show() {
	local ptm_obj="$1"
	local i
	echo
	show_split_text "PTM" "$(get_alias $ptm_obj)"
	print_horizontal_line
	for i in Enable Status MACAddress X_ADB_MTU; do
		show_from_cm "$ptm_obj" "$i"
	done
	show_split_text "LowerLayers" "$(get_alias $(ip_interface_get_cli_ll $ptm_obj))"
	print_horizontal_line
	echo
	interface_show_stats "$ptm_obj"
	interface_ethernet_link_show "$ptm_obj"
	echo
}
interface_ip_show_table_entry() {
	local printf_args="%-10s |  %-10s  |  %-7s  |  %-15s |  %s\n"
	printf "$printf_args" "Source" "Status" "Enable" "IP address" "Subnet mask"
	print_horizontal_line 79
	interface_ip_show_table_entry_without_hdr "$1"
}
interface_ip_show_table_entry_without_hdr() {
	local printf_args="%-10s |  %-10s  |  %-7s  |  %-15s |  %s\n"
	local addr="$1"
	printf "$printf_args" \
		"$(oneline_get_value $addr.AddressingType)" \
		"$(oneline_get_value $addr.Status)" \
		"$(oneline_get_value $addr.Enable)" \
		"$(oneline_get_value $addr.IPAddress)" \
		"$(oneline_get_value $addr.SubnetMask)"
}
interface_ip_show_table() {
	local this="$1"
	local ip_vector addr
	local printf_args="%-10s |  %-10s  |  %-7s  |  %-15s |  %s\n"
	cmclient -v ip_vector GETO "$this.IPv4Address"
	if [ -n "$ip_vector" ]; then
		echo
		echo "IPv4 settings:"
		print_horizontal_line 79
		printf "$printf_args" "Source" "Status" "Enable" "IP address" "Subnet mask"
		print_horizontal_line 79
		for addr in $ip_vector; do
			interface_ip_show_table_entry_without_hdr "$addr"
		done
		print_horizontal_line 79
	fi
	echo
	echo "IPv6 settings:"
	print_horizontal_line 140
	cmclient -v addr GETV "$this.IPv6Enable"
	if [ "$addr" = "false" ]; then
		echo "IPv6 is disabled"
		print_horizontal_line 140
		return
	fi
	cmclient -v ip_vector GETO "$this.IPv6Address"
	if [ -n "$ip_vector" ]; then
		printf_args="%-15s |  %-8s  |  %-6s  |  %-7s  |  %-40s |  %s\n"
		printf "$printf_args" "Origin" "Status" "Enable" "Anycast" "IP address" "Prefix"
		print_horizontal_line 140
		for addr in $ip_vector; do
			local pr anycast
			cmclient -v pr GETV "$addr.Prefix"
			cmclient -v pr GETV "$pr.Prefix"
			cmclient -v anycast GETV "$addr.Anycast"
			[ "$anycast" = "false" ] && anycast="No" || anycast="Yes"
			printf "$printf_args" \
				"$(oneline_get_value $addr.Origin)" \
				"$(oneline_get_value $addr.Status)" \
				"$(oneline_get_value $addr.Enable)" \
				"$anycast" \
				"$(oneline_get_value $addr.IPAddress)" \
				"$pr"
		done
		print_horizontal_line 140
	fi
	cmclient -v mtu GETV $this.MaxMTUSize
	if [ -n "$mtu" ]; then
		echo
		print_horizontal_line 79
		show_split_text "MaxMTUSize" "$mtu"
		print_horizontal_line 79
	fi
}
interface_ip_show_forwarding() {
	local ip_obj="$1"
	local this ip_fwd metric i
	local printf_arg="%-7s  |  %-15s  |  %-15s  |  %-15s  |  %-5s\n"
	cmclient -v ip_fwd GETO "Device.Routing.*.Router.IPv4Forwarding.[Interface=$ip_obj]"
	[ -z "$ip_fwd" ] && return
	echo
	echo "IP Forwarding:"
	print_horizontal_line 79
	printf "$printf_arg" "Enable" "Destination" "Gateway" "Genmask" "Metric"
	print_horizontal_line 79
	for this in $ip_fwd; do
		cmclient -v metric GETV "$this.ForwardingMetric"
		[ "$metric" = "-1" ] && metric=""
		enable="$(oneline_get_value $this.Enable)"
		destIPAddress="$(oneline_get_value $this.DestIPAddress)"
		gatewayIPAddress="$(oneline_get_value $this.GatewayIPAddress)"
		destMask="$(oneline_get_value $this.DestSubnetMask)"
		if [ "$destIPAddress" = "" ]; then
			destIPAddress="0.0.0.0"
		fi
		if [ "$destMask" = "" ]; then
			destMask="0.0.0.0"
		fi
		printf "$printf_arg" "$enable" "$destIPAddress" "$gatewayIPAddress" "$destMask" "$metric"
	done
	print_horizontal_line 79
}
interface_ip_show_nat() {
	local this="$1"
	local nat_objs i
	echo
	echo "NAT:"
	print_horizontal_line
	cmclient -v nat_objs GETO "Device.NAT.InterfaceSetting.[Interface=$this]"
	if [ -n "$nat_objs" ]; then
		print_2_col_row "Entry" "Enable"
		print_horizontal_line
		for i in $nat_objs; do
			print_2_col_row "$(get_alias $i)" "$(oneline_get_value $i.Enable)"
		done
	else
		echo "Not configured"
	fi
	print_horizontal_line
}
interface_ip_show_dns_entry_without_hdr() {
	local i="$1"
	print_3_col_row "$(oneline_get_value $i.Enable)" \
		"$(oneline_get_value $i.Type)" \
		"$(oneline_get_value $i.DNSServer)"
}
interface_ip_show_dns_entry() {
	print_3_col_row "Enable" "Type" "Server"
	interface_ip_show_dns_entry_without_hdr "$1"
	print_horizontal_line 79
}
interface_ip_show_dns() {
	local this="$1"
	local dns_objs
	local i
	cmclient -v dns_objs GETO "Device.DNS.Client.Server.[Interface=$this]"
	[ -z "$dns_objs" ] && return
	echo
	echo "DNS:"
	print_horizontal_line 79
	print_3_col_row "Enable" "Type" "Server"
	print_horizontal_line 79
	for i in $dns_objs; do
		interface_ip_show_dns_entry_without_hdr "$i"
	done
	print_horizontal_line 79
}
interface_ip_show() {
	local obj
	local that
	case "${1}" in
	Device.IP.*)
		obj="${1}"
		;;
	*)
		obj="$(ll_obj_to_ip_obj ${1})"
		[ -z "$obj" ] && return
		;;
	esac
	for that in $obj; do
		interface_ip_show_table "$that"
		interface_ip_show_forwarding "$that"
		interface_ip_show_dns "$that"
		interface_ip_show_nat "$that"
	done
}
interface_ipcp_show() {
	local this="$1"
	local i vs
	echo
	echo "IPCP:"
	print_horizontal_line
	for i in LocalIPAddress RemoteIPAddress DNSServers \
		PassthroughEnable; do
		show_from_cm "$this.IPCP" "$i"
	done
	cmclient -v vs GETV "$this.PassthroughDHCPPool"
	[ -n "$vs" ] && print_2_col_row "Passthrough DHCP Pool" "$(get_alias $vs)"
	print_horizontal_line
}
interface_ipv6cp_show() {
	local this="$1"
	local i
	echo
	echo "IPv6CP:"
	print_horizontal_line
	for i in LocalInterfaceIdentifier RemoteInterfaceIdentifier; do
		show_from_cm "$this.IPv6CP" "$i"
	done
	print_horizontal_line
}
interface_ip_counters() {
	local if_obj="$1"
	interface_show_stats "$if_obj"
}
type="$1"
ifname="$2"
case "$type" in
"vlan")
	show_action="interface_vlan_show"
	show_argument="$(get_show_tr_list $ifname Device.Ethernet.VLANTermination)"
	;;
"ethernet")
	show_action="interface_ethernet_show"
	show_argument="$(get_show_tr_list $ifname Device.Ethernet.Interface)"
	;;
"bridge")
	show_action="interface_bridge_show"
	show_argument="$(get_show_tr_list $ifname Device.Bridging.Bridge)"
	;;
"dot11radio")
	show_action="interface_dot11radio_show"
	show_argument="$(get_show_tr_list $ifname Device.WiFi.Radio)"
	;;
"wifi")
	show_action="interface_wifi_show"
	show_argument="$(get_show_tr_list $ifname Device.WiFi.SSID)"
	;;
"IP")
	show_action="interface_ip_show"
	show_argument="$ifname"
	;;
"interface_ip_show_table_entry")
	show_action="interface_ip_show_table_entry"
	show_argument="$2"
	;;
"interface_ip_show_dns_entry")
	show_action="interface_ip_show_dns_entry"
	show_argument="$2"
	;;
"atm")
	show_action="interface_atm_show"
	show_argument="$(get_show_tr_list $ifname Device.ATM.Link)"
	;;
"xdsl")
	show_action="interface_xdsl_show"
	show_argument="$(get_show_tr_list $ifname Device.DSL.Line)"
	;;
"ptm")
	show_action="interface_ptm_show"
	show_argument="$(get_show_tr_list $ifname Device.PTM.Link)"
	;;
"ppp")
	show_action="interface_ppp_show"
	show_argument="$(get_show_tr_list $ifname Device.PPP.Interface)"
	;;
"ip_counters")
	show_action="interface_ip_counters"
	show_argument="$(get_show_tr_list $ifname Device.Ethernet.Interface Device.WiFi.SSID Device.ATM.Link Device.PTM.Link)"
	;;
"ip_counters_obj")
	show_action="interface_show_stats"
	show_argument="${ifname}"
	;;
"ap_security")
	show_action="interface_ap_sequrity_show"
	show_argument="$(get_show_tr_list $ifname Device.WiFi.SSID)"
	;;
"ap_wps")
	show_action="interface_ap_wps_show"
	show_argument="$(get_show_tr_list $ifname Device.WiFi.SSID)"
	;;
*)
	die "ERROR: Unknown interface type $type"
	;;
esac
[ -n "$show_action" -a -n "$show_argument" ] && show_everything "$show_action" "$show_argument"
