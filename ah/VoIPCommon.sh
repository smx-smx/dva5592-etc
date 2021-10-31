#!/bin/sh
command -v help_lowlayer_ifname_get >/dev/null || . /etc/ah/helper_ifname.sh
command -v help_iptables >/dev/null || . /etc/ah/helper_firewall.sh
ERR=255
OK=0
RELOAD=1
NO=0
YES=1
VOIP_CTRLIF_ADDR="local:/tmp/voip_socket"
. /etc/ah/helper_provisioning.sh
ROOT_CONF_DIR="/etc/cm/conf/"
provservId="Services.VoiceService.1"
service_reload() {
	local retpost=1
	help_post_provisioning_add "Device.Services.VoiceService.1.X_ADB_ConfReload" "true" "Default"
	retpost=$?
	if [ $retpost -eq 0 ]; then
		: >/etc/voip/reload
	fi
}
init_natskip() {
	local suffix=$1 portMin=$2 portMax=$3 multipleIfEnable="" interfaceList="" IPAddress="" retval
	cmclient -v multipleIfEnable GETV Device.Services.VoiceService.1.Capabilities.X_ADB_ProfileOutboundInterface
	help_iptables -t nat -F NATSkip_VoIP_$suffix
	case "$multipleIfEnable" in
	"true")
		cmclient -v interfaceList GETV Device.Services.VoiceService.1.VoiceProfile.*.X_ADB_OutboundInterface
		;;
	*)
		cmclient -v interfaceList GETV Device.Services.VoiceService.1.X_ADB_OutboundInterface
		;;
	esac
	for interfaceList in $interfaceList; do
		help_lowlayer_ifname_get ifname "$interfaceList"
		cmclient -v IPAddress GETV ${interfaceList}.[Enable=true].[X_ADB_Upstream=true].IPv4Address.[Enable=true].IPAddress
		for IPAddress in $IPAddress; do
			help_iptables -t nat -A NATSkip_VoIP_$suffix -i "$ifname" -d "$IPAddress" -p udp --dport "$portMin${portMax:+:$portMax}" -j ACCEPT
		done
	done
	help_iptables commit
	Voip_Active
	retval=$?
	iptable_reconf_NATSkip_VoIP "$retval"
}
Voip_Active() {
	local act
	cmclient -v act GETO "Services.VoiceService.[X_ADB_Enable=true].VoiceProfile.[Enable=Enabled].Line.[Enable=Enabled]"
	[ -n "$act" ] && return 1
	return 0
}
iptable_reconf_IP_PHONE() {
	local retval=$1
	local bridgeName
	for bridgeName in $(cmclient GETV Device.Bridging.Bridge.*.Port.1.Name); do
		if iptables -t nat -L NATIpPhone | grep -q IP_PHONE_"$bridgeName"; then
			if iptables -t nat -L IP_PHONE_"$bridgeName" -n | grep -q RETURN; then
				if [ $retval -eq 1 ]; then
					help_iptables -t nat -D IP_PHONE_"$bridgeName" -j RETURN
				fi
			else
				if [ $retval -eq 0 ]; then
					help_iptables -t nat -I IP_PHONE_"$bridgeName" -j RETURN
				fi
			fi
		fi
	done
}
iptable_reconf_NATSkip_VoIP() {
	local suffix="SIP SIP2 FaxT38 RTP" suff retval=$1
	for suff in $suffix; do
		if iptables -t nat -L NATSkip_VoIP_"$suff" -n | grep -q ACCEPT; then
			if iptables -t nat -L NATSkip_VoIP_"$suff" -n | grep -q RETURN; then
				if [ $retval -eq 1 ]; then
					help_iptables -t nat -D NATSkip_VoIP_"$suff" -j RETURN
				fi
			else
				if [ $retval -eq 0 ]; then
					help_iptables -t nat -I NATSkip_VoIP_"$suff" -j RETURN
				fi
			fi
		fi
	done
}
reconf_voip_iptables() {
	local retval
	Voip_Active
	retval=$?
	iptable_reconf_IP_PHONE "$retval"
	iptable_reconf_NATSkip_VoIP "$retval"
}
checkloadconf_region() {
	local type="$1"
	local tr104ver="$2"
	local coderesult=0
	local changedvalue=""
	local newvalue=""
	case "$tr104ver" in
	"ver2" | "Ver2")
		changedvalue="$changedRegion"
		newvalue="$newRegion"
		;;
	"ver1" | "Ver1")
		changedvalue="$changedX_ADB_Region"
		newvalue="$newX_ADB_Region"
		;;
	"*")
		echo "Invalid tr104-version type '$tr104ver':"
		exit 1
		;;
	esac
	if [ -n "$changedvalue" ] && [ "$changedvalue" -eq 1 ]; then
		coderesult=1
		case "$type" in
		"Tone" | "tone")
			if [ -n "$(cmclient -u voip GETO ${provservId}.Tone)" ]; then
				if [ -s "${ROOT_CONF_DIR}$newvalue/factory_voip_tone.$newvalue.xml" ]; then
					coderesult=2
				else
					coderesult=3
				fi
			fi
			;;
		"Ring" | "ring")
			if [ -n "$(cmclient -u voip GETO ${provservId}.POTS.Ringer)" ]; then
				if [ -s "${ROOT_CONF_DIR}$newvalue/factory_voip_v2.$newvalue.xml" ]; then
					coderesult=2
				else
					coderesult=3
				fi
			fi
			;;
		"V2" | "v2")
			if [ -n "$(cmclient -u voip GETO ${provservId}.POTS)" ]; then
				if [ -s "${ROOT_CONF_DIR}$newvalue/factory_voip_ring.$newvalue.xml" ]; then
					coderesult=2
				else
					coderesult=3
				fi
			fi
			;;
		"All" | "all")
			if [ -n "$(cmclient -u voip GETO ${provservId}.POTS)" ] &&
				[ -n "$(cmclient -u voip GETO ${provservId}.POTS.Ringer)" ] &&
				[ -n "$(cmclient -u voip GETO ${provservId}.Tone)" ]; then
				if [ -s "${ROOT_CONF_DIR}$newvalue/factory_voip_ring.$newvalue.xml" ] &&
					[ -s "${ROOT_CONF_DIR}$newvalue/factory_voip_v2.$newvalue.xml" ] &&
					[ -s "${ROOT_CONF_DIR}$newvalue/factory_voip_tone.$newvalue.xml" ]; then
					coderesult=2
				else
					coderesult=3
				fi
			fi
			;;
		"Test" | "test")
			echo "Testing Region value is changed for Tr-104 '$tr104ver'"
			;;
		"*")
			echo "Invalid type '$type':"
			exit 1
			;;
		esac
	fi
	if [ $coderesult -eq 3 ]; then
		echo "Not found Configuratiofn for '$type' and Region '$newvalue'"
	fi
	return $coderesult
}
