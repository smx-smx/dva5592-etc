#!/bin/sh
#bcm:*,net,dsl*
#sync:skipcycles
. /etc/ah/target.sh
dslGetInfo() {
	local buf=$(xdsl_get_info $phy_line)
	local _mode=${buf##*Mode:			}
	local _xtmmode=${buf##*TPS-TC:			}
	local NEWLINE='
'
	case "${_mode%%$NEWLINE*}" in
	"G.DMT"*)
		newMode="G.992.1_Annex_A"
		encap="G.992.3_Annex_K_ATM"
		;;
	"G.lite"*)
		newMode="G.992.2"
		encap="G.992.3_Annex_K_ATM"
		;;
	"T1.413"*)
		newMode="T1.413"
		encap="G.992.3_Annex_K_ATM"
		;;
	"ADSL2+ AnnexM"*)
		newMode="G.992.5_Annex_M"
		encap="G.992.3_Annex_K_ATM"
		;;
	"ADSL2+"*)
		newMode="G.992.5_Annex_A"
		encap="G.992.3_Annex_K_ATM"
		;;
	"RE-ADSL2"*)
		newMode="G.992.3_Annex_L"
		encap="G.992.3_Annex_K_ATM"
		;;
	"ADSL2 AnnexM"*)
		newMode="G.992.3_Annex_M"
		encap="G.992.3_Annex_K_ATM"
		;;
	"ADSL2"*)
		newMode="G.992.3_Annex_A"
		encap="G.992.3_Annex_K_ATM"
		;;
	"VDSL2"*)
		newMode="G.993.2_Annex_A"
		case "${_xtmmode%%$NEWLINE*}" in
		"ATM"*) encap="G.993.2_Annex_K_ATM" ;;
		"PTM"*) encap="G.993.2_Annex_K_PTM" ;;
		esac
		;;
	"G.fast"*)
		newMode="G.9701"
		case "${_xtmmode%%$NEWLINE*}" in
		"ATM"*) encap="G.993.2_Annex_K_ATM" ;;
		"PTM"*) encap="G.993.2_Annex_K_PTM" ;;
		esac
		;;
	esac
}
checkRestartLine() {
	local ds us
	[ "$1" = "NoSignal" ] && return
	cmclient -v us GETV $dsl_channel_path.UpstreamCurrRate
	cmclient -v ds GETV $dsl_channel_path.DownstreamCurrRate
	[ "$ds" = "0" -a "$us" != "0" ] && echo "Restarting $dsl_line_path" >/dev/console && cmclient SET $dsl_line_path.X_ADB_Reset true
}
phy_line=${OBJ##*.}
dsl_line_path="Device.DSL.Line.$((phy_line + 1))"
dsl_channel_path="Device.DSL.Channel.$((phy_line + 1))"
cmclient -v oldLinkStatus GETV ${dsl_line_path}.LinkStatus
if [ "$OP" = "training" ]; then
	cmclient SET ${dsl_line_path}.LinkStatus Initializing
	local PTMLink
	cmclient -v PTMLink GETO Device.PTM.Link
	if [ -n "$PTMLink" -a ! -x /etc/ah/DslBonding.sh ]; then
		local ifname
		cmclient -v ifname GETV "${PTMLink}.Name"
		[ -n "$ifname" ] || exit 0
		cmclient -v mtu GETV "${PTMLink}.X_ADB_MTU"
		if [ ! -d "/sys/class/net/${ifname}" ]; then
			local portID MACAddress
			. /etc/ah/helper_dsl.sh
			. /etc/ah/helper_serialize.sh
			dsl_dev_exists atm && /etc/ah/ATMLink.sh del $dsl_channel_path
			help_get_ptm_port_id portID "$PTMLink"
			MACAddress=$(help_get_ptm_mac_address "$PTMLink")
			cmclient SET -u "PTMLink$PTMLink" "$PTMLink".Status Error
			xtm_add_connection ${portID}.1
			xtm_add_queue ${portID}.1 400 0 rr 10 0 0 0
			xtm_create_network_device ${portID}.1 "$ifname"
			help_serialize_unlock "get_mac_lock"
			ifconfig "$ifname" hw ether "$MACAddress"
			[ $mtu -gt 0 ] && ip link set "$ifname" mtu "$mtu"
			ip link set "$ifname" up
		else
			ip link set "$ifname" down
			ip link set "$ifname" up
		fi
	fi
	exit 0
fi
[ "$OP" = "estlink" ] && cmclient SET ${dsl_line_path}.LinkStatus EstablishingLink && exit 0
cmclient -v tmp GETV ${dsl_line_path}.Enable
if [ "$tmp" = "true" ]; then
	local old_status
	cmclient -v old_status GETV ${dsl_line_path}.Status
	[ "$OP" = "idle" ] && cmclient SETM "${dsl_line_path}.Status=Down	${dsl_line_path}.LinkStatus=NoSignal" &&
		checkRestartLine $oldLinkStatus && exit 0
	[ "$OP" = "add" ] && newStatus="Up" && linkStatus="Up"
	[ "$OP" = "add" ] && set_wan_type DSL
	[ "$OP" = "phy" ] && cmclient SET ${dsl_line_path}.X_ADB_PhyReconf true
	[ "$OP" = "remove" ] && newStatus="Down" && linkStatus="NoSignal" && [ "$old_status" = "Dormant" ] && newStatus="Dormant"
	if [ "$linkStatus" != "$oldLinkStatus" ]; then
		local ifname logEv="Down"
		cmclient -v ifname GETV ${dsl_line_path}.Name
		[ "$linkStatus" = "Up" ] && logEv="Up"
		logger -t cm "ADSL interface ${ifname}: $logEv" -p 6
	fi
	cmclient SET ${dsl_line_path}.LinkStatus "$linkStatus"
	if [ "$newStatus" = "Up" ]; then
		dslGetInfo
		if [ -x /etc/ah/DslBonding.sh ]; then
			cmclient -v bg GETO "Device.DSL.BondingGroup.[Enable!true]"
			if [ -n "$bg" ]; then
				{
					sleep 10
					case $(xtm_bonding_status) in
					*"TM Bonded"*)
						read -r bg _ <<-EOF
							$bg
						EOF
						cmclient SET "Device.ATM.Link.[LowerLayers=Device.DSL.Channel.1].LowerLayers" $bg >/dev/null
						cmclient SET "Device.PTM.Link.[LowerLayers=Device.DSL.Channel.1].LowerLayers" $bg >/dev/null
						cmclient SET "Device.DSL.BondingGroup.[Enable!true].Enable" true
						cmclient SAVE
						cmclient REBOOT
						exit 0
						;;
					esac
				} &
			fi
		fi
		cmclient -v oldEncap GETV ${dsl_channel_path}.LinkEncapsulationUsed
		setm_params="${dsl_line_path}.StandardUsed=${newMode}"
		setm_params="$setm_params	${dsl_channel_path}.LinkEncapsulationUsed=${encap}"
		[ -n "$oldEncap" ] && setm_params="$setm_params	${dsl_channel_path}.X_ADB_PreviousLinkEncapsulationUsed=${oldEncap}"
		cmclient SETM "$setm_params"
	fi
	cmclient SET ${dsl_line_path}.Status "$newStatus"
	[ "$newStatus" = "Down" ] && checkRestartLine $oldLinkStatus
else
	cmclient SETM "${dsl_line_path}.LinkStatus=Disabled	${dsl_line_path}.Status=Down"
fi
exit 0
