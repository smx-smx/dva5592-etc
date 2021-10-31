#!/bin/sh /etc/rc.common
exec 1>/dev/null
exec 2>/dev/null
. /etc/ah/target.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_svc.sh
. /etc/ah/helper_mac.sh
. /etc/ah/IPv6_helper_functions.sh
. /etc/ah/IPv6_helper_firewall.sh
START=11
STOP=97
CFG_FILES=""
[ -x /etc/ah/CWMP2.sh ] && CFG_DIRS="CWMP2"
CFG_DIRS=${CFG_DIRS:+$CFG_DIRS }"CWMP GUI dropbear"
YAFF=/sbin/yaff
title_echo() {
	local _prtstr="$1" uptime
	read -r uptime _ </proc/uptime
	printf '\n\n -- \033[1;44m %s \033[m [\033[1;33m%s\033[m]\n\n' "$_prtstr" "$uptime" >/dev/console
}
service_echo() {
	printf '[\033[1;34m*\033[m] \033[36m%s\033[m\n' "$1" >/dev/console
}
service_echo_start() {
	service_echo "Starting $1" >/dev/console
}
service_echo_end() {
	echo "[$1 ready]" >/dev/console
}
info_echo() {
	printf '- \033[33m%s\033[m\n' "$1" >/dev/console
}
align_tr098() {
	local cm98_ready
	cmclient -v cm98_ready GETV Device.DeviceInfo.X_ADB_TR098Ready
	if [ $rebuildTR098 -eq 1 -o "$cm98_ready" = false ]; then
		info_echo " CM TR-98 Reconf Start (B)"
		/etc/ah/TR098_AlignAll.sh
		cmclient SET Device.DeviceInfo.X_ADB_TR098Ready true
		cmclient SAVE
		info_echo " CM TR-98 Reconf End"
	else
		info_echo " CM TR-98 ready"
	fi
}
init_mac_address() {
	local _base="" _mac="" _pE="" _pW="" _pH="" i _b="n" _r=
	cmclient -v _base GETV "Device.X_ADB_FactoryData.BaseMACAddress"
	_mac="$_base"
	local llp2
	cmclient -v llp2 GETO Device.Bridging.Bridge.Port.[ManagementPort=false].[LowerLayers~Ethernet]
	for llp2 in $llp2; do
		break
	done
	if [ -n "$llp2" ]; then
		llp2="$llp2".LowerLayers
		testnotalias=."[Alias!%(%($llp2).Alias)]"
	else
		testnotalias=""
	fi
	cmclient -v i GETO Device.Ethernet.Interface."[Alias=%(%($llp2).Alias)]"
	if [ ${#i} -gt 0 ]; then
		_pE="${_pE}${i}.MACAddress=${_mac}	"
		help_inc_mac_address _mac "$_mac" 1
	fi
	case "${_mac##*:[a-f0-9]}" in
	"d" | "e" | "f")
		cmclient -v i GETO Device.Ethernet.Interface"$testnotalias"
		for i in $i; do
			_pE="${_pE}${i}.MACAddress=${_mac}	"
			help_inc_mac_address _mac "$_mac" 1
		done
		cmclient -v _r GETO Device.WiFi.Radio
		for _r in $_r; do
			cmclient -v _b GETO "Device.WiFi.SSID.[LowerLayers=$_r]"
			for _b in $_b; do
				_pW="${_pW}$_b.MACAddress=$_mac	$_b.BSSID=$_mac	"
				help_inc_mac_address _mac "$_mac" 1
			done
		done
		cmclient -v i GETO Device.HPNA.Interface
		for i in $i; do
			_pH="${_pH}${i}.X_ADB_MACAddress=${_mac}	"
			help_inc_mac_address _mac "$_mac" 1
		done
		;;
	*)
		cmclient -v _r GETO Device.WiFi.Radio
		for _r in $_r; do
			cmclient -v _b GETO "Device.WiFi.SSID.[LowerLayers=$_r]"
			for _b in $_b; do
				_pW="${_pW}$_b.MACAddress=$_mac	$_b.BSSID=$_mac	"
				help_inc_mac_address _mac "$_mac" 1
			done
		done
		cmclient -v i GETO Device.Ethernet.Interface"$testnotalias"
		for i in $i; do
			_pE="${_pE}${i}.MACAddress=${_mac}	"
			help_inc_mac_address _mac "$_mac" 1
		done
		cmclient -v i GETO Device.HPNA.Interface
		for i in $i; do
			_pH="${_pH}${i}.X_ADB_MACAddress=${_mac}	"
			help_inc_mac_address _mac "$_mac" 1
		done
		;;
	esac
	cmclient -u "EthernetIf" SETM "${_pE}"
	cmclient -u "WiFiSSID" SETM "${_pW}"
	[ -n "$_pH" ] && cmclient SETM "${_pH}"
}
help_start_object() {
	local _path="$1" _message="$2" _only_true="$3" _user="$4" _refresh="$5" _refresh_always="$6" _enable_check=""
	cmclient -v _enable_check GETV "$_path"
	[ ${#_refresh} -ne 0 ] && _path="$_refresh"
	if [ "$_enable_check" = "true" -o "$_refresh_always" = "true" ]; then
		[ ${#_message} -ne 0 ] && service_echo_start "$_message"
		if [ "$_only_true" != "true" ]; then
			if [ -n "$_user" ]; then
				cmclient -u "$_user" SET "$_path" false
			else
				cmclient SET "$_path" false
			fi
		fi
		if [ ${#_user} -ne 0 ]; then
			cmclient -u "$_user" SET "$_path" true
		else
			cmclient SET "$_path" true
		fi
		[ ${#_message} -ne 0 ] && service_echo_end "$_message"
	fi
}
init_eth() {
	local _jumbo wanEth intfHandled ethName i=0
	init_eh "eh_ethup.sh"
	cmclient -v _jumbo GETV Device.Ethernet.X_ADB_MaxSupportedMTUSize
	[ ${_jumbo} -gt 1500 ] && ethsw_set_jumbo_enable
	cmclient -v wanEth GETO "Device.Ethernet.Interface.[Upstream=true]"
	for wanEth in $wanEth; do
		cmclient -v intfHandled GETO "Device.X_ADB_InterfaceMonitor.[Enable=true].Group.*.Interface.[MonitoredInterface=$wanEth].[Enable=true]"
		cmclient -v ethName GETV "${wanEth}.Name"
		[ ${#intfHandled} -eq 0 ] && (
			while [ $((i = i + 1)) -le 10 ]; do
				sleep 1
				if [ -e "/tmp/${ethName}_ready" ]; then
					service_echo "WAN Ethernet Interfaces - Power UP! (B)"
					start_eth_power "true" "$wanEth"
					break
				fi
			done
		) &
		[ ${_jumbo} -gt 1500 ] && ip link set "${ethName}" mtu ${_jumbo}
	done
}
init_dsl() {
	local wanDsl mod_path mode="" intfHandled
	for mod_path in /lib/modules/*; do
		[ -L "$mod_path" ] && continue
	done
	if [ ! -f "${mod_path}/adsldd.ko" ]; then
		if [ -f /tmp/cfg/xdsl-mode ]; then
			read mode </tmp/cfg/xdsl-mode
		else
			[ -f "${mod_path}/adsldd-isdn.ko" ] && mode="isdn"
			[ -f "${mod_path}/adsldd-pots.ko" ] && mode="pots"
		fi
	fi
	insmod adsldd${mode:+-$mode}
	cmclient -v wanDsl GETO "Device.DSL.Line"
	if [ ${#wanDsl} -eq 0 ]; then
		touch /tmp/cfg/cache/xdslctl
		return
	fi
	init_eh "eh_dslup.sh"
	info_echo "Init DSL Line"
	if [ -x /etc/ah/DslBonding.sh ]; then
		xtmctl start --intf allint --bondingenable
	else
		xtmctl start --intf allint
	fi
	xtmctl operate intf --state 0x01 enable
	for wanDsl in $wanDsl; do
		if [ -x /etc/ah/DslBonding.sh ]; then
			cmclient SET "$wanDsl.Enable" "true"
		else
			cmclient -v intfHandled GETO "Device.X_ADB_InterfaceMonitor.[Enable=true].Group.*.Interface.[MonitoredInterface=$wanDsl].[Enable=true]"
			[ ${#intfHandled} -eq 0 ] && cmclient SET "$wanDsl.[Enable=true].Enable" "true"
		fi
	done
}
init_eh() {
	if [ -x /etc/eh/delay/"$1" ]; then
		cp /etc/eh/delay/"$1" /tmp/
		mv /tmp/"$1" /tmp/eh/
	fi
}
disable_upstream_obj() {
	local _path="$1" _upstream="$2" _obj="" _obj_enable=""
	cmclient -v _obj GETO "$_path.*.[Upstream=$_upstream].[Enable=true]"
	for _obj in $_obj; do
		cmclient -u boot SET "$_obj.Enable" "false"
		cmclient SET "$_obj.Enable" "true"
	done
}
system_config() {
	echo "localhost" >/proc/sys/kernel/hostname
	hostname localhost
	config_get conloglevel "$cfg" conloglevel
	config_get buffersize "$cfg" buffersize
	[ -z "$conloglevel" -a -z "$buffersize" ] || dmesg ${conloglevel:+-n $conloglevel} ${buffersize:+-s $buffersize}
}
getMainSSIDs() {
	local _r _s _ret=""
	cmclient -v _r GETO Device.WiFi.Radio
	for _r in $_r; do
		cmclient -v _s GETO "Device.WiFi.SSID.[Name=%($_r.Name)].[LowerLayers=$_r]"
		[ "${#_s}" -gt 0 ] && _ret="$_ret $_s"
	done
	eval $1='$_ret'
}
mergeFactoryData() {
	local p v
	for p in SerialNumber HardwareVersion ProductClass Manufacturer ManufacturerOUI ModelName; do
		cmclient -v v GETV Device.X_ADB_FactoryData.${p}
		[ ${#v} -ne 0 ] && cmclient SET Device.DeviceInfo.${p} "$v"
	done
	local ssid tail ap pv pf= fpv= i=1
	getMainSSIDs ssid
	for ssid in $ssid; do
		[ "$i" = 1 ] && tail="" || tail=$i
		cmclient -v ap GETO "Device.WiFi.AccessPoint.[SSIDReference=$ssid]"
		for p in \
			WiFiSSID$tail $ssid.SSID \
			WiFiWEPKey$tail $ap.Security.WEPKey \
			WiFiKeyPassphrase$tail $ap.Security.KeyPassphrase; do
			if [ -z "$pf" ]; then
				pf="$p"
				continue
			fi
			cmclient -v pv GETV "$p"
			cmclient -v fpv GETV Device.X_ADB_FactoryData.${pf}
			case "$pf" in
			WiFiSSID*) [ ${#fpv} -gt 0 -a "$pv" = "yapsie-wlan" ] && pv="" ;;
			esac
			[ ${#pv} -eq 0 ] && cmclient SETE "$p" "$fpv"
			pf=""
		done
		i=$((i + 1))
	done
	[ -x /etc/ah/CustomFactory.sh ] && /etc/ah/CustomFactory.sh
}
deviceinfo_to_factorydata() {
	sed \
		-e '/Manufacturer/{N;N;/$/d}' \
		-e '/ManufacturerOUI/{N;N;/$/d}' \
		-e '/ModelName/{N;N;/$/d}' \
		-e '/HardwareVersion/{N;N;/$/d}' \
		-e '/ProductClass/{N;N;/$/d}' \
		-e '/X_ADB_FactoryMode/{N;N;/$/d}' \
		-e s/X_ADB_BaseMACAddress/BaseMACAddress/ \
		-e s/X_ADB_MaxMACAddress/MaxMACAddress/ \
		-e s/X_ADB_SSID/WiFiSSID/ \
		-e s/X_ADB_WEPKey/WiFiWEPKey/ \
		-e s/X_ADB_KeyPassphrase/WiFiKeyPassphrase/ \
		-e s/Device\.DeviceInfo/Device\.X_ADB_FactoryData/ \
		${1} >${2}
}
checkFactoryData() {
	local failure=0 forceProductionMode=0 factoryMode=""
	if [ -x /sbin/yacs ]; then
		if yacs check conf_factory; then
			echo "yacs: converting deviceinfo.xml"
			if yacs conv_factory conf_factory >/tmp/deviceinfo.xml; then
				mkdir -p /tmp/factory
				mv /tmp/deviceinfo.xml /tmp/factory/deviceinfo.xml
				cmclient CONF /tmp/factory/
				[ -e /tmp/cfg/FactoryData.xml ] && productionMode=1
				return
			fi
			failure=1
		fi
	elif [ -x $YAFF ]; then
		if yaff r conf_factory >/tmp/conf_factory.gz; then
			if gunzip -c /tmp/conf_factory.gz >/tmp/deviceinfo.tar; then
				if ! tar -C /tmp -xf /tmp/deviceinfo.tar; then
					mv /tmp/deviceinfo.tar /tmp/deviceinfo.xml
				fi
				if [ -e /tmp/deviceinfo.xml ]; then
					deviceinfo_to_factorydata /tmp/deviceinfo.xml /tmp/factory/deviceinfo.xml
					rm /tmp/deviceinfo.xml
					cmclient CONF /tmp/factory/
					return
				fi
			fi
		fi
		failure=1
	fi
	if [ -z "$(grep $factoryDevice /proc/mounts)" ]; then
		mount -t yaffs $factoryDevice /tmp/factory
	fi
	[ -e /tmp/cfg/FactoryData.xml ] && rm -f /tmp/factory/deviceinfo.xml
	cmclient CONF /tmp/factory/
	cmclient -v factoryMode GETV Device.X_ADB_FactoryData.FactoryMode
	if [ "$factoryMode" = "true" ]; then
		forceProductionMode=1
	fi
	[ $forceProductionMode -eq 0 ] && [ -s /tmp/factory/deviceinfo.xml ] && return
	cmclient GET Device.X_ADB_FactoryData.
	if [ $failure -eq 0 ]; then
		productionMode=1
	else
		cmclient DUMPDM FactoryData /tmp/factory/deviceinfo.xml
	fi
	return
}
get_mtd_dev() {
	local partition name
	while read -r partition _ _ name; do
		case "$name" in
		\"${2}\")
			partition=${partition%:}
			break
			;;
		esac
	done </proc/mtd
	eval $1="/dev/mtdblock${partition#mtd}"
}
confUpgradeCheck() {
	cmclient -v curVer GETV "Device.DeviceInfo.AdditionalSoftwareVersion"
	curVer="${curVer##*_}"
	prevVer=""
	if [ ! -x /tmp/cfg/conf_upgrade.sh ] && [ -x /etc/cm/conf_upgrade.sh ]; then
		cp /etc/cm/conf_upgrade.sh /tmp/cfg/conf_upgrade.sh
	fi
	[ -x /sbin/yacs ] && yacs check conf_rg_main && [ "$(yacs get conf_rg_main merged)" != "merged = \"true\"" ] && return
	[ -s /tmp/cfg/current_version ] && read prevVer </tmp/cfg/current_version && prevVer="${prevVer##*_}"
	if [ -x /tmp/cfg/conf_upgrade.sh ] && [ ! -x /etc/cm/conf_upgrade.sh ]; then
		info_echo "Migration from ${prevVer} to ${curVer} ...removing customized conf_upgrade"
		rm /tmp/cfg/conf_upgrade.sh
	fi
	case "$prevVer" in
	*.*.*.*) ;;

	*.*.*)
		prevVer="$prevVer.9999"
		;;
	esac
	case "$curVer" in
	*.*.*.*) ;;

	*.*.*)
		curVer="$curVer.9999"
		;;
	esac
	if [ "$curVer" != "$prevVer" ]; then
		realVer="${realVer%%-*}"
		versionChanged=1
		if [ -n "$prevVer" ]; then
			prevMajor=${prevVer%%.*}
			__prevVer=${prevVer#*.}
			prevMinor=${__prevVer%%.*}
			__prevVer=${__prevVer#*.}
			prevSub=${__prevVer%%.*}
			__prevVer=${__prevVer#*.}
			prevBuild=${__prevVer%%.*}
			prevCmp=$(expr $prevMajor \* 256 \* 256 \* 256 \* 256 + $prevMinor \* 256 \* 256 \* 256 + $prevSub \* 256 \* 256 + $prevBuild)
			curMajor=${curVer%%.*}
			__curVer=${curVer#*.}
			curMinor=${__curVer%%.*}
			__curVer=${__curVer#*.}
			curSub=${__curVer%%.*}
			__curVer=${__curVer#*.}
			curBuild=${__curVer%%.*}
			curCmp=$(expr $curMajor \* 256 \* 256 \* 256 \* 256 + $curMinor \* 256 \* 256 \* 256 + $curSub \* 256 \* 256 + $curBuild)
		fi
		if [ -z "$prevVer" ] || [ $curCmp -gt $prevCmp ]; then
			if [ -x /etc/cm/conf_upgrade.sh ]; then
				cp /etc/cm/conf_upgrade.sh /tmp/cfg/conf_upgrade.sh
			fi
		fi
		if [ -x /tmp/cfg/conf_upgrade.sh ]; then
			if [ -z "$prevVer" ] || ! /tmp/cfg/conf_upgrade.sh "$prevVer" "$curVer" "$currentImage" check; then
				sleep 5
				if [ -n "$prevVer" ]; then
					echo "User settings migration from platform version ${prevVer:-<unknown>} to ${curVer} is"
					echo "unsupported. Default settings restore is needed. Login and stop the boot"
					echo "process now to skip. Warning: the device may become unusable then."
					echo -n "Restore to default settings in 30s"
					for i in $(seq 30 -1 0); do
						[ $i -gt 9 ] && printf "\010\010\010\010 ${i}s"
						[ $i -eq 9 ] && printf "\010\010\010\010 ${i}s \010"
						[ $i -lt 9 ] && printf "\010\010\010 ${i}s"
						sleep 1
					done
					echo
				fi >/dev/console
				restoreNeeded=1
			else
				upgradeNeeded=1
			fi
		else
			[ $versionChanged -eq 1 ] && upgradeNeeded=1
		fi
	fi
}
confUpgrade() {
	if [ $curCmp -gt $prevCmp ]; then
		cmclient CONFUP /etc/cm/conf/
	fi
	if [ -x /tmp/cfg/conf_upgrade.sh ]; then
		/tmp/cfg/conf_upgrade.sh "$prevVer" "$curVer" "$currentImage"
	fi
	[ -x /etc/ah/CallControl_upgrade.sh ] && /etc/ah/CallControl_upgrade.sh
}
start_cleandynentries() {
	local ipv4_entry ipv6_route tbd save=0
	service_echo "Cleaning dynamic entries..."
	cmclient -v tbd DELE "Device.Routing.Router.*.IPv6Forwarding.*.[Origin=RA]"
	[ ERROR"${tbd#ERROR}" = "$tbd" ] || save=1
	cmclient -v tbd DELE "Device.X_ADB_Time.Event.*.[Alias>IPv6Prefix]"
	[ ERROR"${tbd#ERROR}" = "$tbd" ] || save=1
	[ $save -eq 1 ] && cmclient SAVE
	cmclient SETE "Device.Routing.Router.[Enable=true].Status" Enabled
}
start_timezone() {
	cmclient GETV Device.Time.LocalTimeZone >/tmp/TZ
}
start_ebtables() {
	if [ -x /usr/sbin/ebtables ]; then
		local basemac mac_mask="FF:FF:FF:FF:FF:00"
		cmclient -v basemac GETV Device.X_ADB_FactoryData.BaseMACAddress
		ebtables -t nat -N BridgeFilter -P DROP
		ebtables -t nat -N BF_BOARDPASS -P RETURN
		ebtables -t nat -A BF_BOARDPASS -s "$basemac"/"$mac_mask" -j ACCEPT
		ebtables -t nat -A BF_BOARDPASS --logical-in br0 -d "$basemac"/"$mac_mask" -j ACCEPT
		ebtables -t nat -A BF_BOARDPASS --logical-in br0 -p ARP -d FF:FF:FF:FF:FF:FF -j ACCEPT
		ebtables -t nat -N WiFiSegregation -P RETURN
		ebtables -t nat -A PREROUTING -j WiFiSegregation
		ebtables -t nat -A BridgeFilter -j BF_BOARDPASS
		ebtables -t filter -N IGMPlan -P DROP
		if [ -x /etc/ah/RestrictedHost.sh ]; then
			ebtables -t nat -N RO -P RETURN
			ebtables -t nat -A PREROUTING -j RO
			ebtables -t filter -N RO -P RETURN
		fi
		ebtables -t filter -A FORWARD -l ipox --igmp-type ! 17 -j IGMPlan
		if [ -x /etc/ah/RestrictedHost.sh ]; then
			ebtables -t filter -N RO_INPUT -P RETURN
			ebtables -t filter -A FORWARD -j RO
			ebtables -t filter -A INPUT -j RO_INPUT
		fi
		[ -d /proc/net/yatta ] && ebtables -t nat -I POSTROUTING -d Broadcast -j SKIPFC
	fi
	[ -x /etc/ah/RestrictedHost.sh ] && /etc/ah/RestrictedHost.sh init
}
start_iptables() {
	local x
	help_iptables -t nat -N RtspRedirect
	help_iptables -t nat -A PREROUTING -j RtspRedirect
	help_iptables -t nat -N NATSkip_GUIRemote
	help_iptables -t nat -A PREROUTING -j NATSkip_GUIRemote
	help_iptables -t nat -N NATSkip_GUILocal
	help_iptables -t nat -A PREROUTING -j NATSkip_GUILocal
	help_iptables -t nat -N NATSkip_HTTPRemote
	help_iptables -t nat -A PREROUTING -j NATSkip_HTTPRemote
	help_iptables -t nat -N NATSkip_HTTPLocal
	help_iptables -t nat -A PREROUTING -j NATSkip_HTTPLocal
	help_iptables -t nat -N NATSkip_CMWS
	help_iptables -t nat -A PREROUTING -j NATSkip_CMWS
	help_iptables -t nat -N NATSkip_ACS
	help_iptables -t nat -A PREROUTING -j NATSkip_ACS
	if [ -x /etc/ah/CWMP2.sh ]; then
		help_iptables -t nat -N NATSkip_CWMP2
		help_iptables -t nat -A PREROUTING -j NATSkip_CWMP2
	fi
	if [ -x /sbin/swcagent ]; then
		help_iptables -t nat -N NATSkip_SwcAgentIn
		help_iptables -t nat -A PREROUTING -j NATSkip_SwcAgentIn
	fi
	help_iptables -t nat -N NATSkip_SSHRemote
	help_iptables -t nat -A PREROUTING -j NATSkip_SSHRemote
	help_iptables -t nat -N NATSkip_GUIRemote_ACL
	help_iptables -t nat -N NATSkip_SSHRemote_ACL
	help_iptables -t nat -N NATSkip_TelnetRemote_ACL
	help_iptables -t nat -N NATSkip_SSHLocal
	help_iptables -t nat -A PREROUTING -j NATSkip_SSHLocal
	help_iptables -t nat -N NATSkip_TelnetRemote
	help_iptables -t nat -A PREROUTING -j NATSkip_TelnetRemote
	help_iptables -t nat -N NATSkip_TelnetLocal
	help_iptables -t nat -A PREROUTING -j NATSkip_TelnetLocal
	for x in FaxT38 RTP; do
		help_iptables -t nat -N NATSkip_VoIP_$x
		help_iptables -t nat -A PREROUTING -j NATSkip_VoIP_$x
	done
	for x in SIP SIP2; do
		help_iptables -t nat -N NATSkip_VoIP_$x
		help_iptables -t nat -A PREROUTING -j NATSkip_VoIP_$x
	done
	help_iptables -t nat -N SnatMapping
	help_iptables -t nat -A POSTROUTING -j SnatMapping
	help_iptables -t nat -N PortMapping
	help_iptables -t nat -A PREROUTING -j PortMapping
	help_iptables -t nat -N Rtsp_dnat
	help_iptables -t nat -A PREROUTING -j Rtsp_dnat
	help_iptables -t nat -N Rtsp_snat
	help_iptables -t nat -A POSTROUTING -j Rtsp_snat
	help_iptables -N ForwardDeny
	help_iptables -N ForwardDeny_TOD
	help_iptables -N ForwardAllow
	help_iptables -N ForwardAllow_MC
	help_iptables -A ForwardAllow_MC -m pkttype --pkt-type multicast -j ACCEPT
	help_iptables -N ForwardAllow_DMZ
	help_iptables -N ForwardAllow_PortMapping
	help_iptables -N ForwardAllow_Rtsp
	help_iptables -N ForwardAllow_PPPoERelay
	help_iptables -A FORWARD -j ForwardAllow
	help_iptables -A ForwardAllow -j ForwardAllow_MC
	help_iptables -A ForwardAllow -j ForwardAllow_DMZ
	help_iptables -A ForwardAllow -j ForwardAllow_Rtsp
	help_iptables -A ForwardAllow -j ForwardAllow_PPPoERelay
	help_iptables -A FORWARD -j ForwardDeny
	help_iptables -A ForwardDeny -j ForwardDeny_TOD
	help_iptables -t mangle -N SIP
	help_iptables -t mangle -A PREROUTING -j SIP
	if [ -x /etc/ah/CaptivePortal.sh ]; then
		help_iptables -t mangle -N CP
		help_iptables -t mangle -A PREROUTING ! -i pr+ -j CP
	fi
	if [ -x /etc/ah/RestrictedHost.sh ]; then
		help_iptables -t mangle -N RO
		help_iptables -t mangle -A PREROUTING -j RO
	fi
	help_iptables -t mangle -N IPsec
	help_iptables -t mangle -A POSTROUTING -j IPsec
	help_iptables -t filter -N Firewall
	help_iptables -t filter -A FORWARD -j Firewall
	help_iptables -t filter -N InputDeny
	help_iptables -t filter -N FirewallIn
	help_iptables -t filter -N ServicesIn
	help_iptables -t filter -N SambaIn
	help_iptables -t filter -N ServicesIn_LocalServices
	help_iptables -t filter -N ServicesIn_LocalACLServices
	help_iptables -t filter -I INPUT -j SambaIn
	help_iptables -t filter -A INPUT -i lo -j ACCEPT
	help_iptables -t filter -A INPUT -j InputDeny
	help_iptables -t filter -A INPUT -j ServicesIn
	help_iptables -t filter -A INPUT -j FirewallIn
	help_iptables -t filter -N InputDeny.wan
	help_iptables -t filter -I InputDeny -j InputDeny.wan
	help_iptables -t filter -N DNSIn
	help_iptables -t filter -N DNSOut
	help_iptables -t filter -N NTPIn
	help_iptables -t filter -N NTPOut
	help_iptables -t filter -N CWMPOut
	help_iptables -t filter -N CWMPIn
	if [ -x /etc/ah/CWMP2.sh ]; then
		help_iptables -t filter -N CWMP2Out
		help_iptables -t filter -N CWMP2In
	fi
	help_iptables -t filter -N SSHRemoteIn_
	help_iptables -t filter -N SSHRemoteIn
	help_iptables -t filter -N SSHRemoteOut_
	help_iptables -t filter -N SSHRemoteOut
	help_iptables -t filter -N SSHLocalIn_
	help_iptables -t filter -N SSHLocalIn
	help_iptables -t filter -N SSHLocalOut_
	help_iptables -t filter -N SSHLocalOut
	help_iptables -t filter -N GUIRemoteOut_
	help_iptables -t filter -N GUIRemoteOut
	help_iptables -t filter -N GUIRemoteIn_
	help_iptables -t filter -N GUIRemoteIn
	help_iptables -t filter -N GUILocalOut_
	help_iptables -t filter -N GUILocalOut
	help_iptables -t filter -N GUILocalIn_
	help_iptables -t filter -N GUILocalIn
	help_iptables -t filter -N DHCPServices
	help_iptables -t filter -I SSHRemoteIn_ -j LOG --log-prefix "SSH_ACL:" --log-level 2
	help_iptables -t filter -I SSHLocalIn_ -j LOG --log-prefix "SSH_ACL:" --log-level 2
	help_iptables -t filter -I SSHRemoteIn_ -j ACCEPT
	help_iptables -t filter -I SSHLocalIn_ -j ACCEPT
	help_iptables -t filter -A SSHRemoteIn_ -j DROP
	help_iptables -t filter -A SSHLocalIn_ -j DROP
	help_iptables -t filter -I SSHRemoteOut_ -j ACCEPT
	help_iptables -t filter -I SSHLocalOut_ -j ACCEPT
	help_iptables -t filter -A SSHRemoteOut_ -j DROP
	help_iptables -t filter -A SSHLocalOut_ -j DROP
	help_iptables -t filter -N CMWSIn
	help_iptables -t filter -N TelnetRemoteIn_
	help_iptables -t filter -N TelnetRemoteIn
	help_iptables -t filter -N TelnetRemoteOut_
	help_iptables -t filter -N TelnetRemoteOut
	help_iptables -t filter -N TelnetLocalIn_
	help_iptables -t filter -N TelnetLocalIn
	help_iptables -t filter -N TelnetLocalOut_
	help_iptables -t filter -N TelnetLocalOut
	help_iptables -t filter -I TelnetRemoteIn_ -j LOG --log-prefix "Telnet_ACL:" --log-level 2
	help_iptables -t filter -I TelnetLocalIn_ -j LOG --log-prefix "Telnet_ACL:" --log-level 2
	help_iptables -t filter -I TelnetRemoteIn_ -j ACCEPT
	help_iptables -t filter -I TelnetLocalIn_ -j ACCEPT
	help_iptables -t filter -A TelnetRemoteIn_ -j DROP
	help_iptables -t filter -A TelnetLocalIn_ -j DROP
	help_iptables -t filter -I TelnetRemoteOut_ -j ACCEPT
	help_iptables -t filter -I TelnetLocalOut_ -j ACCEPT
	help_iptables -t filter -A TelnetRemoteOut_ -j DROP
	help_iptables -t filter -A TelnetLocalOut_ -j DROP
	help_iptables -t filter -N FTPRemoteIn
	help_iptables -t filter -N FTPLocalIn
	help_iptables -t filter -N HTTPRemoteIn
	help_iptables -t filter -N HTTPLocalIn
	help_iptables -t filter -N IGMPProxyIn
	help_iptables -t filter -N RtspOut
	help_iptables -t filter -N RtspIn
	help_iptables -t filter -N SNMPIn
	help_iptables -t filter -A ServicesIn -j DNSIn
	help_iptables -t filter -A ServicesIn -j NTPIn
	help_iptables -t filter -A ServicesIn -j CWMPIn
	if [ -x /etc/ah/CWMP2.sh ]; then
		help_iptables -t filter -A ServicesIn -j CWMP2In
	fi
	if [ -x /sbin/swcagent ]; then
		help_iptables -t filter -N SwcAgentIn
		help_iptables -t filter -A ServicesIn -j SwcAgentIn
	fi
	help_iptables -t filter -A ServicesIn_LocalServices -j SSHRemoteIn
	help_iptables -t filter -A ServicesIn_LocalServices -j SSHLocalIn
	help_iptables -t filter -A ServicesIn_LocalServices -j GUIRemoteIn
	help_iptables -t filter -A ServicesIn_LocalServices -j GUILocalIn
	help_iptables -t filter -A ServicesIn_LocalServices -j HTTPRemoteIn
	help_iptables -t filter -A ServicesIn_LocalServices -j HTTPLocalIn
	help_iptables -t filter -A ServicesIn -j DHCPServices
	help_iptables -t filter -A ServicesIn -j RtspIn
	help_iptables -t filter -A ServicesIn_LocalServices -j SNMPIn
	help_iptables -t filter -A ServicesIn -j CMWSIn
	help_iptables -t filter -A ServicesIn_LocalServices -j TelnetRemoteIn
	help_iptables -t filter -A ServicesIn_LocalServices -j TelnetLocalIn
	help_iptables -t filter -A ServicesIn -j FTPRemoteIn
	help_iptables -t filter -A ServicesIn -j FTPLocalIn
	help_iptables -t filter -A ServicesIn -j IGMPProxyIn
	if [ -f "/usr/sbin/httpd" ]; then
		help_iptables -t filter -I GUIRemoteIn_ -j LOG --log-prefix "GUI_ACL:" --log-level 2
		help_iptables -t filter -I GUILocalIn_ -j LOG --log-prefix "GUI_ACL:" --log-level 2
		help_iptables -t filter -I GUIRemoteIn_ -j ACCEPT
		help_iptables -t filter -I GUILocalIn_ -j ACCEPT
		help_iptables -t filter -A GUIRemoteIn_ -j DROP
		help_iptables -t filter -A GUILocalIn_ -j DROP
		help_iptables -t filter -I GUIRemoteOut_ -j ACCEPT
		help_iptables -t filter -I GUILocalOut_ -j ACCEPT
		help_iptables -t filter -A GUIRemoteOut_ -j DROP
		help_iptables -t filter -A GUILocalOut_ -j DROP
	fi
	help_iptables -t filter -N OutputAllow
	help_iptables -t filter -N OutputAllow_LocalServices
	help_iptables -t filter -N OutputAllow_LocalACLServices
	help_iptables -t filter -N ServicesOut
	help_iptables -t filter -N FirewallOut
	help_iptables -t filter -N SambaOut
	help_iptables -t filter -I OUTPUT -j SambaOut
	help_iptables -t filter -A OUTPUT -o lo -j ACCEPT
	help_iptables -t filter -A OUTPUT -j OutputAllow
	help_iptables -t filter -A OUTPUT -j RtspOut
	help_iptables -t filter -A OUTPUT -j FirewallOut
	help_iptables -t filter -A OutputAllow_LocalServices -j CWMPOut
	if [ -x /etc/ah/CWMP2.sh ]; then
		help_iptables -t filter -A OutputAllow_LocalServices -j CWMP2Out
	fi
	help_iptables -t filter -A OutputAllow_LocalServices -j GUIRemoteOut
	help_iptables -t filter -A OutputAllow_LocalServices -j GUILocalOut
	help_iptables -t filter -A OutputAllow_LocalServices -j SSHRemoteOut
	help_iptables -t filter -A OutputAllow_LocalServices -j SSHLocalOut
	help_iptables -t filter -A OutputAllow_LocalServices -j TelnetRemoteOut
	help_iptables -t filter -A OutputAllow_LocalServices -j TelnetLocalOut
	help_iptables -t filter -A OutputAllow_LocalServices -j DNSOut
	help_iptables -t filter -A OutputAllow_LocalServices -j NTPOut
	help_iptables -t mangle -N Flows
	help_iptables -t mangle -A PREROUTING -j Flows
	help_iptables -t mangle -A POSTROUTING -j Flows
	help_iptables -t mangle -A POSTROUTING -m mark --mark 0x00000000/0x00E00000 -j CLASSIFY --set-class 0:0
	help_iptables -t mangle -A POSTROUTING -m mark --mark 0x00200000/0x00E00000 -j CLASSIFY --set-class 0:1
	help_iptables -t mangle -A POSTROUTING -m mark --mark 0x00400000/0x00E00000 -j CLASSIFY --set-class 0:2
	help_iptables -t mangle -A POSTROUTING -m mark --mark 0x00600000/0x00E00000 -j CLASSIFY --set-class 0:3
	help_iptables -t mangle -A POSTROUTING -m mark --mark 0x00800000/0x00E00000 -j CLASSIFY --set-class 0:4
	help_iptables -t mangle -A POSTROUTING -m mark --mark 0x00A00000/0x00E00000 -j CLASSIFY --set-class 0:5
	help_iptables -t mangle -A POSTROUTING -m mark --mark 0x00C00000/0x00E00000 -j CLASSIFY --set-class 0:6
	help_iptables -t mangle -A POSTROUTING -m mark --mark 0x00E00000/0x00E00000 -j CLASSIFY --set-class 0:7
	help_iptables -t mangle -N PortMapping
	help_iptables -t mangle -A PREROUTING -j PortMapping
	help_iptables -t mangle -N Classes
	help_iptables -t mangle -A PREROUTING -j Classes
	help_iptables -t mangle -N SambaOut
	help_iptables -t mangle -I OUTPUT -j SambaOut
	help_iptables -t mangle -N LocalFlows
	help_iptables -t mangle -A OUTPUT -j LocalFlows
	help_iptables -t mangle -N LocalQoE
	help_iptables -t mangle -A OUTPUT -j LocalQoE
	help_iptables -t mangle -N LocalClasses
	help_iptables -t mangle -A OUTPUT -j LocalClasses
	help_iptables -t mangle -N OutputClasses
	help_iptables -t mangle -A POSTROUTING -j OutputClasses
	help_iptables -t mangle -N SnatMapping
	help_iptables -t mangle -A POSTROUTING -j SnatMapping
	help_iptables -t nat -N DMZ
	help_iptables -t nat -A PREROUTING -j DMZ
	help_iptables -t nat -N DMZ_SNAT
	help_iptables -t nat -A PREROUTING -j DMZ_SNAT
	help_iptables -t nat -N SNAT_DMZ
	help_iptables -t nat -A POSTROUTING -j SNAT_DMZ
	help_iptables -t nat -N NATSkip_IPsec
	help_iptables -t nat -A PREROUTING -j NATSkip_IPsec
	help_iptables -t nat -N SNATSkip_IPsec
	help_iptables -t nat -A POSTROUTING -j SNATSkip_IPsec
	help_iptables -t mangle -N DMZ
	help_iptables -t mangle -I PREROUTING -j DMZ
	help_iptables -t mangle -N DMZOut
	help_iptables -t mangle -I POSTROUTING -j DMZOut
	help_iptables -t mangle -I POSTROUTING -m conntrack --ctstatus EXPECTED -m connmark --mark 0/4 -j CONNMARK --set-mark 4/6
	help_iptables -t mangle -N SambaIn
	help_iptables -t mangle -I PREROUTING -j SambaIn
	help_iptables -t mangle -I POSTROUTING -j SambaOut
	help_iptables -t mangle -N SKIP_Yatta
	help_iptables -t mangle -I PREROUTING -j SKIP_Yatta
	help_iptables -t mangle -A SKIP_Yatta -p udp -m multiport --sports 67,68 -j SKIPFC
	if [ -x /bin/fcctl -a -d /proc/net/yatta ]; then
		local match_vxlan="-p udp --dport 4789" marking="--set-mark 0x2/0x2"
		help_iptables -t mangle -A SKIP_Yatta ${match_vxlan} -j RETURN
		help_iptables -t mangle -A SKIP_Yatta -j SKIPFC
		help_iptables -t mangle -A SKIP_Yatta -j CONNMARK "$marking"
		help_iptables -t mangle -N FC_SKIP_VXLAN
		help_iptables -t mangle -A FC_SKIP_VXLAN ${match_vxlan} -j SKIPLOG
		help_iptables -t mangle -A FC_SKIP_VXLAN ${match_vxlan} -j RETURN
		help_iptables -t mangle -A FC_SKIP_VXLAN -j SKIPFC
		help_iptables -t mangle -A FC_SKIP_VXLAN -j CONNMARK "$marking"
		help_iptables -t mangle -I OUTPUT -j FC_SKIP_VXLAN
	fi
	if [ -x /sbin/voip ]; then
		help_iptables -t nat -N NATIpPhone
		help_iptables -t nat -A POSTROUTING -j NATIpPhone
	fi
	if [ -x /etc/ah/CaptivePortal.sh -o -x /etc/ah/ConnectivityChecker.sh ]; then
		help_iptables -t nat -N CP
		help_iptables -t nat -A PREROUTING ! -i pr+ -j CP
	fi
	if [ -f /sbin/cbpc-dnsp ]; then
		help_iptables -t nat -N CbpcRedirect
		help_iptables -t nat -A PREROUTING -j CbpcRedirect
		help_iptables -t mangle -N CbpcRedirect
	fi
	if [ -f /sbin/tproxyd ]; then
		help_iptables -t mangle -N PC
		help_iptables -t mangle -N PC_HTTPS
		help_iptables -t mangle -N PC_HTTP10
		help_iptables -t mangle -N PC_HTTP11
		help_iptables -t mangle -N PC_MATCH_WL
		help_iptables -t mangle -A PC_MATCH_WL -j CONNMARK --set-mark 0x1/0x1
		help_iptables -t mangle -A PC_MATCH_WL -j RETURN
	fi
	if [ -x /etc/ah/RestrictedHost.sh ]; then
		help_iptables -t mangle -N RO_INPUT
		help_iptables -t mangle -I INPUT -j RO_INPUT
	fi
	help_iptables -t mangle -I INPUT -j SambaIn
	help_iptables -t mangle -I POSTROUTING -o ppp+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
	help_iptables commit
	unset tmpiptablesprefix
	hwqos_init_iptables_chains
}
start_ip6tables() {
	help_ip6tables -N Basic
	help_ip6tables -N ForwardDeny
	help_ip6tables -N ForwardAllow
	help_ip6tables -N ForwardAllow_MC
	help_ip6tables -A ForwardAllow_MC -m pkttype --pkt-type multicast -j ACCEPT
	help_ip6tables -N ForwardAllow_Rtsp
	help_ip6tables -N ForwardAllow_PPPoERelay
	help_ip6tables -A FORWARD -j Basic
	help_ip6tables -A FORWARD -j ForwardAllow
	help_ip6tables -A ForwardAllow -j ForwardAllow_MC
	help_ip6tables -A ForwardAllow -j ForwardAllow_Rtsp
	help_ip6tables -A ForwardAllow -j ForwardAllow_PPPoERelay
	help_ip6tables -A FORWARD -j ForwardDeny
	help_ip6tables -t mangle -N SIP
	help_ip6tables -t mangle -A PREROUTING -j SIP
	help_ip6tables -t mangle -N IPsec
	help_ip6tables -t mangle -A POSTROUTING -j IPsec
	help_ip6tables -t filter -N Firewall
	help_ip6tables -t filter -A FORWARD -j Firewall
	help_ip6tables -t filter -N BasicIn
	help_ip6tables -t filter -N InputDeny
	help_ip6tables -t filter -N FirewallIn
	help_ip6tables -t filter -N ServicesIn
	help_ip6tables -t filter -N ServicesIn_LocalServices
	help_ip6tables -t filter -N ServicesIn_LocalACLServices
	help_ip6tables -t filter -A INPUT -i lo -j ACCEPT
	help_ip6tables -t filter -A INPUT -j BasicIn
	help_ip6tables -t filter -A INPUT -j InputDeny
	help_ip6tables -t filter -A INPUT -j ServicesIn
	help_ip6tables -t filter -A INPUT -j FirewallIn
	help_ip6tables -t filter -N InputDeny.wan
	help_ip6tables -t filter -I InputDeny -j InputDeny.wan
	help_ip6tables -t filter -N DNSIn
	help_ip6tables -t filter -N DNSOut
	help_ip6tables -t filter -N NTPIn
	help_ip6tables -t filter -N NTPOut
	help_ip6tables -t filter -N CWMPOut
	help_ip6tables -t filter -N CWMPIn
	if [ -x /etc/ah/CWMP2.sh ]; then
		help_ip6tables -t filter -N CWMP2Out
		help_ip6tables -t filter -N CWMP2In
	fi
	help_ip6tables -t filter -N SSHRemoteIn
	help_ip6tables -t filter -N SSHRemoteIn_
	help_ip6tables -t filter -N SSHRemoteOut_
	help_ip6tables -t filter -N SSHRemoteOut
	help_ip6tables -t filter -N SSHLocalIn
	help_ip6tables -t filter -N SSHLocalIn_
	help_ip6tables -t filter -N SSHLocalOut_
	help_ip6tables -t filter -N SSHLocalOut
	help_ip6tables -t filter -N GUIRemoteIn_
	help_ip6tables -t filter -N GUIRemoteIn
	help_ip6tables -t filter -N GUIRemoteOut_
	help_ip6tables -t filter -N GUIRemoteOut
	help_ip6tables -t filter -N GUILocalIn_
	help_ip6tables -t filter -N GUILocalIn
	help_ip6tables -t filter -N GUILocalOut_
	help_ip6tables -t filter -N GUILocalOut
	if [ -f "/usr/sbin/httpd" ]; then
		help_ip6tables -t filter -I GUIRemoteIn_ -j LOG --log-prefix "GUI_ACL:" --log-level 2
		help_ip6tables -t filter -I GUILocalIn_ -j LOG --log-prefix "GUI_ACL:" --log-level 2
		help_ip6tables -t filter -I GUIRemoteIn_ -j ACCEPT
		help_ip6tables -t filter -I GUILocalIn_ -j ACCEPT
		help_ip6tables -t filter -A GUIRemoteIn_ -j DROP
		help_ip6tables -t filter -A GUILocalIn_ -j DROP
		help_ip6tables -t filter -I GUIRemoteOut_ -j ACCEPT
		help_ip6tables -t filter -I GUILocalOut_ -j ACCEPT
		help_ip6tables -t filter -A GUIRemoteOut_ -j DROP
		help_ip6tables -t filter -A GUILocalOut_ -j DROP
	fi
	help_ip6tables -t filter -N DHCPServicesOut
	help_ip6tables -t filter -N DHCPServicesPoolOut
	help_ip6tables -t filter -N DHCPServicesIn
	help_ip6tables -t filter -N DHCPServicesPoolIn
	help_ip6tables -t filter -I SSHRemoteIn_ -j LOG --log-prefix "SSH_ACL:" --log-level 2
	help_ip6tables -t filter -I SSHLocalIn_ -j LOG --log-prefix "SSH_ACL:" --log-level 2
	help_ip6tables -t filter -I SSHRemoteIn_ -j ACCEPT
	help_ip6tables -t filter -I SSHLocalIn_ -j ACCEPT
	help_ip6tables -t filter -A SSHRemoteIn_ -j DROP
	help_ip6tables -t filter -A SSHLocalIn_ -j DROP
	help_ip6tables -t filter -I SSHRemoteOut_ -j ACCEPT
	help_ip6tables -t filter -I SSHLocalOut_ -j ACCEPT
	help_ip6tables -t filter -A SSHRemoteOut_ -j DROP
	help_ip6tables -t filter -A SSHLocalOut_ -j DROP
	help_ip6tables -t filter -N CMWSIn
	help_ip6tables -t filter -N TelnetRemoteIn
	help_ip6tables -t filter -N TelnetLocalIn
	help_ip6tables -t filter -N TelnetRemoteIn_
	help_ip6tables -t filter -N TelnetLocalIn_
	help_ip6tables -t filter -I TelnetRemoteIn_ -j LOG --log-prefix "Telnet_ACL:" --log-level 2
	help_ip6tables -t filter -I TelnetLocalIn_ -j LOG --log-prefix "Telnet_ACL:" --log-level 2
	help_ip6tables -t filter -I TelnetRemoteIn_ -j ACCEPT
	help_ip6tables -t filter -I TelnetLocalIn_ -j ACCEPT
	help_ip6tables -t filter -A TelnetRemoteIn_ -j DROP
	help_ip6tables -t filter -A TelnetLocalIn_ -j DROP
	help_ip6tables -t filter -N TelnetRemoteOut
	help_ip6tables -t filter -N TelnetLocalOut
	help_ip6tables -t filter -N TelnetRemoteOut_
	help_ip6tables -t filter -N TelnetLocalOut_
	help_ip6tables -t filter -I TelnetRemoteOut_ -j ACCEPT
	help_ip6tables -t filter -I TelnetLocalOut_ -j ACCEPT
	help_ip6tables -t filter -A TelnetRemoteOut_ -j DROP
	help_ip6tables -t filter -A TelnetLocalOut_ -j DROP
	help_ip6tables -t filter -N FTPRemoteIn
	help_ip6tables -t filter -N FTPLocalIn
	help_ip6tables -t filter -N IGMPProxyIn
	help_ip6tables -t filter -N RtspOut
	help_ip6tables -t filter -N RtspIn
	help_ip6tables -t filter -N SNMPIn
	help_ip6tables -t filter -A ServicesIn -j DNSIn
	help_ip6tables -t filter -A ServicesIn -j NTPIn
	help_ip6tables -t filter -A ServicesIn -j CWMPIn
	if [ -x /etc/ah/CWMP2.sh ]; then
		help_ip6tables -t filter -A ServicesIn -j CWMP2In
	fi
	help_ip6tables -t filter -A ServicesIn_LocalServices -j SSHRemoteIn
	help_ip6tables -t filter -A ServicesIn_LocalServices -j SSHLocalIn
	help_ip6tables -t filter -A ServicesIn_LocalServices -j GUIRemoteIn
	help_ip6tables -t filter -A ServicesIn_LocalServices -j GUILocalIn
	help_ip6tables -t filter -A ServicesIn_LocalServices -j DHCPServicesIn
	help_ip6tables -t filter -A DHCPServicesIn -j DHCPServicesPoolIn
	help_ip6tables -t filter -A ServicesIn -j RtspIn
	help_ip6tables -t filter -A ServicesIn -j SNMPIn
	help_ip6tables -t filter -A ServicesIn -j CMWSIn
	help_ip6tables -t filter -A ServicesIn_LocalServices -j TelnetRemoteIn
	help_ip6tables -t filter -A ServicesIn_LocalServices -j TelnetLocalIn
	help_ip6tables -t filter -A ServicesIn -j FTPRemoteIn
	help_ip6tables -t filter -A ServicesIn -j FTPLocalIn
	help_ip6tables -t filter -A ServicesIn -j IGMPProxyIn
	help_ip6tables -t filter -N OutputAllow
	help_ip6tables -t filter -N OutputAllow_LocalServices
	help_ip6tables -t filter -N OutputAllow_LocalACLServices
	help_ip6tables -t filter -N BasicOut
	help_ip6tables -t filter -N FirewallOut
	help_ip6tables -t filter -A OUTPUT -o lo -j ACCEPT
	help_ip6tables -t filter -A OUTPUT -j BasicOut
	help_ip6tables -t filter -A OUTPUT -j OutputAllow
	help_ip6tables -t filter -A OUTPUT -j RtspOut
	help_ip6tables -t filter -A OUTPUT -j FirewallOut
	help_ip6tables -t filter -A OutputAllow_LocalServices -j CWMPOut
	if [ -x /etc/ah/CWMP2.sh ]; then
		help_ip6tables -t filter -A OutputAllow_LocalServices -j CWMP2Out
	fi
	help_ip6tables -t filter -A OutputAllow_LocalServices -j GUIRemoteOut
	help_ip6tables -t filter -A OutputAllow_LocalServices -j GUILocalOut
	help_ip6tables -t filter -A OutputAllow_LocalServices -j SSHRemoteOut
	help_ip6tables -t filter -A OutputAllow_LocalServices -j SSHLocalOut
	help_ip6tables -t filter -A OutputAllow_LocalServices -j TelnetRemoteOut
	help_ip6tables -t filter -A OutputAllow_LocalServices -j TelnetLocalOut
	help_ip6tables -t filter -A OutputAllow_LocalServices -j DHCPServicesOut
	help_ip6tables -t filter -A OutputAllow_LocalServices -j DNSOut
	help_ip6tables -t filter -A OutputAllow_LocalServices -j NTPOut
	help_ip6tables -t filter -A DHCPServicesOut -j DHCPServicesPoolOut
	help_ip6tables -t mangle -N Flows
	help_ip6tables -t mangle -A PREROUTING -j Flows
	help_ip6tables -t mangle -A POSTROUTING -j Flows
	help_ip6tables -t mangle -A POSTROUTING -m mark --mark 0x00000000/0x00E00000 -j CLASSIFY --set-class 0:0
	help_ip6tables -t mangle -A POSTROUTING -m mark --mark 0x00200000/0x00E00000 -j CLASSIFY --set-class 0:1
	help_ip6tables -t mangle -A POSTROUTING -m mark --mark 0x00400000/0x00E00000 -j CLASSIFY --set-class 0:2
	help_ip6tables -t mangle -A POSTROUTING -m mark --mark 0x00600000/0x00E00000 -j CLASSIFY --set-class 0:3
	help_ip6tables -t mangle -A POSTROUTING -m mark --mark 0x00800000/0x00E00000 -j CLASSIFY --set-class 0:4
	help_ip6tables -t mangle -A POSTROUTING -m mark --mark 0x00A00000/0x00E00000 -j CLASSIFY --set-class 0:5
	help_ip6tables -t mangle -A POSTROUTING -m mark --mark 0x00C00000/0x00E00000 -j CLASSIFY --set-class 0:6
	help_ip6tables -t mangle -A POSTROUTING -m mark --mark 0x00E00000/0x00E00000 -j CLASSIFY --set-class 0:7
	help_ip6tables -t mangle -N Classes
	help_ip6tables -t mangle -A PREROUTING -j Classes
	help_ip6tables -t mangle -N LocalFlows
	help_ip6tables -t mangle -A OUTPUT -j LocalFlows
	help_ip6tables -t mangle -N LocalClasses
	help_ip6tables -t mangle -A OUTPUT -j LocalClasses
	help_ip6tables -t mangle -N OutputClasses
	help_ip6tables -t mangle -A POSTROUTING -j OutputClasses
	/etc/ah/IPv6rd.sh "init"
	help_ip6tables commit
	unset tmpiptablesprefix
}
start_nat() {
	/etc/ah/NATInterfaceSetting.sh init
	service_echo_start "Port Mapping"
	/etc/ah/NATPortMapping.sh init
	service_echo_end "Port Mapping"
}
init_dev_route() {
	local ip_object table_idx mark mark_mask
	cmclient -v ip_object GETO "Device.IP.Interface"
	for ip_object in $ip_object; do
		table_idx=${ip_object##*Interface.}
		table_idx=${table_idx%%.}
		mark=$((table_idx * 256))
		table_idx="$((table_idx + 1000))"
		mark_mask="0xff00"
		ip rule add fwmark $mark/$mark_mask table $table_idx pref 30000 iif lo
		ip route add unreachable default metric 100 table $table_idx
	done
}
init_bridges() {
	local dots=0
	while [ -f /tmp/starting_hostapd ] && [ -d /sys/class/net/wl0 ]; do
		sleep 1
		dots=$((dots + 1))
		if [ $dots -gt 60 ]; then
			info_echo "WARINING: HOSTAPD init failure - going on without WiFi..."
			break
		fi
	done
	init_eh "eh_ipv6.sh"
	info_echo "Init Bridges ($dots)"
	[ -f /etc/ah/SDN.sh ] && /etc/ah/SDN.sh "init"
	/etc/ah/BridgingBridge.sh "init"
	[ -f /etc/ah/SDN.sh ] && /etc/ah/SDN.sh "setup"
}
start_ipv6_services() {
	service_echo_start "IPv6 services"
	local enable_ra=''
	cmclient -v enable_ra SET "Device.RouterAdvertisement.[Enable=true].Enable" "true"
	[ ERROR"${enable_ra#ERROR}" = "$enable_ra" ] || info_echo "Radvd start"
	info_echo "DHCPv6 init"
	/etc/ah/DHCPv6Server.sh init
}
init_procfs() {
	local i
	for i in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
		echo 1 >"$i"
	done
	echo 0 >/proc/sys/net/ipv6/conf/default/disable_ipv6
	echo 0 >/proc/sys/net/ipv6/conf/lo/disable_ipv6
	cmclient -v ipv6_glob_enable GETV "Device.IP.IPv6Enable"
	ipv6_proc_enable "$ipv6_glob_enable" "all"
	if [ "$ipv6_glob_enable" = "true" ]; then
		cmclient SET -u "IP_IPv6Device.IP" Device.IP.IPv6Status Enabled
	else
		cmclient -u "boot" SET Device.NeighborDiscovery.InterfaceSetting.[Enable=true].Status Error_Misconfigured
	fi
	cmclient -v ipv6_neigh_enable GETV "Device.NeighborDiscovery.Enable"
	if [ -z "$ipv6_neigh_enable" ]; then
		ipv6_neigh_enable="false"
	fi
	ipv6_neigh_proc_enable "$ipv6_neigh_enable" "all"
}
start_eth_power() {
	local _upstream="$1" _ethObj="$2" _name="" _enable=""
	cmclient -v _enable GETV "$_ethObj.Enable"
	if [ "$_upstream" = "false" ]; then
		cmclient -v _name GETV "Device.Ethernet.Interface.*.[Enable=true].[Upstream=$_upstream].Name"
		for _name in $_name; do
			printf '[\033[1;34m%s\033[m] %s\n' "$_name" "up" >/dev/console
			ethsw_power "$_name" "up"
		done
	elif [ "$_enable" = "true" ]; then
		cmclient -v _name GETV "$_ethObj.Name"
		if [ ${#_name} -ne 0 ]; then
			printf '[\033[1;34m%s\033[m] %s\n' "$_name" "up" >/dev/console
			ethsw_power "$_name" "up"
		fi
	fi
}
start_swap() {
	service_echo_start "Swap Disk (RAM)"
	if [ -e /sys/devices/virtual/block/zram0/disksize ]; then
		echo 3145728 >/sys/devices/virtual/block/zram0/disksize
		(
			mkswap /dev/zram0
			swapon /dev/zram0
		) &
	fi
	service_echo_end "Swap Disk (RAM)"
}
post_moduleload() {
	chmod a+r /proc/net/ip_conntrack
	chmod a+r /proc/net/nf_conntrack
}
user_passwd() {
	local smbenable
	cmclient -v smbenable GETV "Services.StorageService.1.NetworkServer.SMBEnable"
	cmclient SET "Services.StorageService.1.NetworkServer.SMBEnable" "false"
	cmclient SET "Device.Services.StorageService.1.UserAccount.[Enable=true].X_ADB_Refresh" "true"
	cmclient SET "Device.Services.StorageService.1.UserGroup.[Enable=true].X_ADB_Refresh" "true"
	cmclient SET "Services.StorageService.1.NetworkServer.SMBEnable" "$smbenable"
	cmclient SET "Device.Users.User.[Enable=true].Enable" "true"
}
create_acl_local_rules() {
	local x
	cmclient -v x GETV "$1.X_ADB_AccessControlEnable"
	[ "$x" = "false" ] && return
	help_iptables_all -A ServicesIn_LocalACLServices -j ${2}In
	help_iptables_all -A OutputAllow_LocalACLServices -j ${2}Out
}
multiboard_override_config_dir() {
	local board_id=
	[ -e /usr/sbin/multi-boards.sh ] && help_get_boardid board_id
	[ -n "$board_id" -a -d "/etc/cm/conf/$board_id" ] && confDirs="$confDirs /etc/cm/conf/$board_id/"
}
default_config_dirs() {
	confDirs="/etc/cm/conf/"
	multiboard_override_config_dir
	[ $# -gt 0 ] && confDirs="$confDirs $*"
}
start() {
	mkdir -p /tmp/upgrade /tmp/eh /tmp/ec_time
	help_svc_wait
	help_svc_start 'logd' 'logd' '' 'cmclient SET -u boot Device.X_ADB_SystemLog.[Enable=true].Enable true'
	logc s t 'kernel*' 7 0 0 0
	logc s t 'cm*' 7 0 0 0
	read currentImage _ </etc/version
	title_echo "Base System Init"
	system_config
	chmod 770 /tmp/upgrade
	cp /etc/eh/eh_*.sh /tmp/eh/
	touch /tmp/starting_hostapd
	[ ! -d /tmp/cfg/$currentImage ] && rm -rf /tmp/cfg/cache/*
	service_echo_start "Event Controller"
	help_svc_start ec
	[ -f /usr/sbin/dhd-nvram.sh ] && . /usr/sbin/dhd-nvram.sh
	service_echo "Loading Drivers and Kernel Modules"
	(
		touch /tmp/loading_modules
		load_modules /etc/modules.d/*
		rm -f /tmp/loading_modules
		post_moduleload
	) &
	ifconfig lo 127.0.0.1 up
	echo "127.0.0.1 localhost. localhost" >/tmp/hosts
	[ -h /etc/hosts ] || (
		rm /etc/hosts
		ln -s /tmp/hosts /etc/hosts
	)
	[ "$currentImage" != "recovery" ] && mkdir -p /tmp/wlan/config
	mkdir -p /tmp/cfg
	mkdir -p /tmp/factory
	service_echo_start "Configuration Load"
	get_mtd_dev cfgDevice conf_fs
	get_mtd_dev factoryDevice conf_factory
	while ! grep -q yaffs /proc/filesystems; do
		sleep 0.1
	done
	mount -t yaffs $cfgDevice /tmp/cfg
	[ -x /sbin/yacs ] || mount -t yaffs $factoryDevice /tmp/factory
	mkdir -p /tmp/cfg/cache
	for l in $CFG_FILES $CFG_DIRS; do
		ln -s /tmp/cfg/$l /tmp/
	done
	service_echo_start "Configuration Manager (B)"
	cm
	help_svc_start cm cm attach-reboot
	[ -f /etc/ah/WatchDog.sh ] && echo $(pidof cm) >/tmp/cm.pid
	help_load_dom
	productionMode=0
	checkFactoryData
	cmclient CONF /etc/cm/version/
	restoreNeeded=0
	loadMulticonfig=0
	configMulticonf=""
	confUploaded=0
	upgradeNeeded=0
	confOverride=0
	versionChanged=0
	if [ $productionMode -eq 1 ] && [ -s /etc/cm/prod/factory_prod.xml ]; then
		printf "%s\n" "Please note: the device is now in" \
			"     ___        _                  __  __         _" \
			"    | __|_ _ __| |_ ___ _ _ _  _  |  \/  |___  __| |___" \
			"    | _/ _\` / _|  _/ _ \ '_| || | | |\/| / _ \/ _\` / -_)" \
			"    |_|\__,_\__|\__\___/_|  \_, | |_|  |_\___/\__,_\___|" \
			"                            |__/" \
			"as this was forced or no factory parameters haven't been" \
			"stored yet. Just issue:" \
			"" \
			"	restore default-setting" \
			"" \
			"from CLI main view if you want to go back to regular device operation." >/dev/console
		confDirs="/etc/cm/prod/"
		multiboard_override_config_dir
		[ -f /etc/ah/TR098_AlignAll.sh ] && rebuildTR098=0
		deleteConfDir=0
		for cdir in ${confDirs}; do
			cmclient CONF "${cdir}"
		done
		cmclient -v ifStack GETV Device.InterfaceStackNumberOfEntries
		[ "$ifStack" = "0" -o -z "$ifStack" ] && /etc/ah/InterfaceStack.sh init
		cmclient SET Device.X_ADB_FactoryData.FactoryMode true
		ln -s /etc/clish/prod /tmp/clish
	else
		confUpgradeCheck
		ln -s /etc/clish /tmp/clish
		if [ -d /tmp/cfg/${currentImage}_new ]; then
			[ -e /tmp/cfg/${currentImage}_new/data.xml ] && confUploaded=1 ||
				rm -rft /tmp/cfg /tmp/cfg/${currentImage}_new
		fi
		[ -f /tmp/cfg/${currentImage}/Device.xml ] || restoreNeeded=1
		[ -d /tmp/cfg/multiconf_load/ ] && loadMulticonfig=1
		if [ $confUploaded -eq 1 ]; then
			confDirs="/tmp/cfg/${currentImage}_new/"
			configMulticonf="$confDirs/VendorConfig.xml"
			[ -f /etc/ah/TR098_AlignAll.sh ] && rebuildTR098=1
			deleteConfDir=1
		elif [ $restoreNeeded -eq 1 ]; then
			confDirs="/tmp/cfg/customer_conf/"
			if [ -e "$confDirs/default.xml" ]; then
				echo "Load customer default config" >/dev/console
				cmclient SETEM "Device.DeviceInfo.X_ADB_CustomerDefault=Save	Device.DeviceInfo.X_ADB_CustomerDefaultStatus=Active"
			else
				echo "Load distro default config" >/dev/console
				default_config_dirs
			fi
			if [ -d "$confDirs/CWMP" ]; then
				rm -frt /tmp/cfg /tmp/cfg/CWMP
				cp -a -f $confDirs/CWMP /tmp/cfg/CWMP >/dev/console
				echo "restored CWMP certificate" >/dev/console
			fi
			if [ -d "$confDirs/CWMP2" -a -x /etc/ah/CWMP2.sh ]; then
				rm -frt /tmp/cfg /tmp/cfg/CWMP2
				cp -a -f $confDirs/CWMP2 /tmp/cfg/ >/dev/console
				echo "restored CWMP2 certificate" >/dev/console
			fi
			rm -rf /tmp/cfg/${currentImage}
			[ -f /etc/ah/TR098_AlignAll.sh ] && rebuildTR098=1
			deleteConfDir=0
		elif [ $loadMulticonfig -eq 1 ]; then
			confDirs="/tmp/cfg/multiconf_load/"
			configMulticonf="$confDirs/VendorConfig.xml"
			[ -f /tmp/cfg/multiconf_load/data.xml ] || default_config_dirs "$confDirs"
			[ -f /etc/ah/TR098_AlignAll.sh ] && rebuildTR098=1
			deleteConfDir=0 ## canot use, cause in confDirs might be cm factory configuration
		else
			confDirs="/tmp/cfg/${currentImage}/"
			[ -f /etc/ah/TR098_AlignAll.sh ] && rebuildTR098=0
			deleteConfDir=0
		fi
		cmclient CONF /tmp/factory/
		cmclient CONF /tmp/factory/tr181/
		for cdir in ${confDirs}; do
			cmclient CONF "${cdir}"
		done
		cmclient SETE "Device.Services.VoiceService.1.X_DLINK_OutboundInterface Device.IP.Interface.2"
		[ $restoreNeeded -eq 1 -a -d "/etc/cm/notify/" ] && cmclient CONFNOTIFY "/etc/cm/notify/"
		if [ ! -e "/tmp/cfg/customer_conf/default.xml" -a $restoreNeeded -eq 1 -a $confUploaded -eq 0 ]; then
			local fprofile="/tmp/cfg/active_profile"
			local profile=""
			[ -e "${fprofile}" ] && read profile <"${fprofile}"
			if [ -z "$profile" -o ! -d "/etc/cm/conf/${profile}" ]; then
				cmclient -v profile GETV DeviceInfo.X_ADB_ProfileType
				echo ${profile} >${fprofile}
			fi
			if [ "$profile" != "Default" ]; then
				cmclient CONF "/etc/cm/conf/${profile}/"
				cmclient SETE DeviceInfo.X_ADB_ProfileType "$profile"
			fi
		fi
		[ -d "/tmp/cfg/notify/" ] && cmclient CONFNOTIFY "/tmp/cfg/notify/"
		cmclient -v ifStack GETV Device.InterfaceStackNumberOfEntries
		[ "$ifStack" = "0" -o -z "$ifStack" ] && /etc/ah/InterfaceStack.sh init
		mergeFactoryData
		[ -d /tmp/cfg/${currentImage}_override ] && confOverride=1
		if [ $confOverride -eq 1 ]; then
			local conf custom_obj
			custom_obj="Device.X_ADB_CustomConf.[ConfigurationSet=RestoreConf]"
			cmclient -v conf GETV "$custom_obj.GroupName"
			for conf in $conf; do
				[ -f "/tmp/cfg/${currentImage}_override/${conf}.xml" ] &&
					cmclient -u "boot" SET "$custom_obj.[GroupName=${conf}].Apply" "true"
			done
			if [ -f "/tmp/cfg/${currentImage}_override/CWMP_State.xml" ]; then
				cmclient DELE Device.ManagementServer.X_ADB_CWMPState.ValueChange
				cmclient DELE Device.ManagementServer.X_ADB_CWMPState.Diagnostics
				cmclient DELE Device.ManagementServer.X_ADB_CWMPState.DUStateChangeComplete
			fi
			if [ -f "/tmp/cfg/${currentImage}_override/CWMP2_State.xml" ]; then
				cmclient DELE Device.X_ADB_ManagementServer.X_ADB_CWMPState.ValueChange
				cmclient DELE Device.X_ADB_ManagementServer.X_ADB_CWMPState.Diagnostics
			fi
			cmclient CONF /tmp/cfg/${currentImage}_override/
			custom_obj="Device.X_ADB_CustomConf.[ConfigurationSet=CustomConf]"
			cmclient -v conf GETV "$custom_obj.GroupName"
			for conf in $conf; do
				[ -f "/tmp/cfg/${currentImage}_override/${conf}.xml" ] &&
					cmclient -u "boot" SET "$custom_obj.[GroupName=${conf}].Apply" "true"
			done
		fi
		if [ -n "$configMulticonf" -a -f "$configMulticonf" ]; then
			cmclient DELE Device.DeviceInfo.VendorConfigFile
			mkdir -p /tmp/multiconf_conf_tmp/
			cp "$configMulticonf" /tmp/multiconf_conf_tmp/
			cmclient CONF /tmp/multiconf_conf_tmp/
			rm -rf /tmp/multiconf_conf_tmp/
		fi
		[ $upgradeNeeded -eq 1 ] && confUpgrade
		[ $deleteConfDir -eq 1 ] && rm -rf ${confDirs}
		[ $loadMulticonfig -eq 1 ] && rm -rft /tmp/cfg/ /tmp/cfg/multiconf_load/
	fi
	[ $restoreNeeded -eq 1 ] && /etc/ah/CustomConf.sh "save"
	cmclient SAVEPATH /tmp/cfg/${currentImage}
	if [ -f /etc/ah/TR098_AlignAll.sh ]; then
		[ $upgradeNeeded -eq 1 -o $confUploaded -eq 1 -o $restoreNeeded -eq 1 -o $rebuildTR098 -eq 1 -o $versionChanged -eq 1 ] && rm -rf /tmp/cfg/cache/* && cmclient SAVE
	else
		[ $upgradeNeeded -eq 1 -o $confUploaded -eq 1 -o $restoreNeeded -eq 1 -o $versionChanged -eq 1 ] && rm -rf /tmp/cfg/cache/* && cmclient SAVE
	fi
	[ $confOverride -eq 1 ] && rm -rf /tmp/cfg/${currentImage}_override
	echo "$curVer" >/tmp/cfg/current_version
	cmclient CONF /etc/cm/version/
	info_echo " CM TR-181 ready"
	/etc/ah/TR181_DeviceSummary.sh
	if [ -f /etc/ah/TR098_AlignAll.sh ]; then
		align_tr098
		/etc/ah/TR098_DeviceSummary.sh
	fi
	for d in $CFG_DIRS; do
		if [ ! -d /tmp/cfg/$d ]; then
			mkdir -p /tmp/cfg/$d
		fi
	done
	mkdir /var/cache
	chmod a+rwx /var/cache
	service_echo_end "Configuration Load"
	help_start_object "Device.X_ADB_SystemLog.Enable" "System Log" "true" "boot"
	help_start_object "Device.X_ADB_LED.Enable" "LEDs (B)" "true" "boot" &
	init_mac_address
	touch /tmp/cm_ready
	if [ -f /tmp/cfg/GUI/reportfwupgrade ]; then
		mv /tmp/cfg/GUI/reportfwupgrade /tmp/reportfwupgrade
		chmod 0644 /tmp/reportfwupgrade
		chown nobody:root /tmp/reportfwupgrade
	fi
	if [ -x /sbin/yacs ]; then
		read is_main </etc/version
		if [ "$is_main" = "main" ]; then
			if yacs conv conf_rg_main >/dev/console 2>&1; then
				echo cmclient SAVE
				cmclient SAVE
			fi
		fi
	fi
	if [ -f /etc/ah/AdminAccessAllowed.sh ]; then
		local is_factory
		cmclient -v is_factory GETV Device.X_ADB_FactoryData.FactoryMode
		if [ "$is_factory" = "true" ]; then
			cmclient SET Device.UserInterface.X_ADB_AdminAccessAllowed true
		else
			/etc/ah/AdminAccessAllowed.sh init
		fi
	fi
	user_passwd &
	start_cleandynentries &
	service_echo "Probing for usb devices..."
	(
		/etc/ah/ah_usb_probe.sh
		init_eh eh_usbdevices.sh
	) &
	cmclient -v software_version GETV Device.DeviceInfo.SoftwareVersion
	cmclient -v platform_version GETV Device.DeviceInfo.X_ADB_PlatformSoftwareVersion
	service_echo "Epicentro Software Version: $software_version"
	service_echo "Epicentro Platform Version: $platform_version"
	/etc/ah/Hosts.sh init
	mkdir -p /tmp/ppp
	touch /tmp/ppp/pap-secrets /tmp/ppp/chap-secrets
	mkdir -p /tmp/dropbear /tmp/inetd
	chmod 700 /tmp/dropbear
	if [ ! -s /tmp/dropbear/dropbear_rsa_host_key ]; then
		info_echo "SSH: Generating RSA key"
		rm /tmp/dropbear/dropbear_rsa_host_key
		dropbearkey -t rsa -f /tmp/dropbear/dropbear_rsa_host_key
	fi
	if [ ! -s /tmp/dropbear/dropbear_ecdsa_host_key ]; then
		info_echo "SSH: Generating ECDSA key"
		rm /tmp/dropbear/dropbear_ecdsa_host_key
		dropbearkey -t ecdsa -f /tmp/dropbear/dropbear_ecdsa_host_key
	fi
	while [ -f /tmp/loading_modules ]; do
		lsmod | grep -q \
			ip6t_ &&
			rm -f /tmp/loading_modules && break
		sleep 1
	done
	help_start_object "Device.DeviceInfo.X_ADB_PowerManagement.Enable" "PowerManagement" "true" "boot"
	init_procfs
	start_swap
	service_echo_start "Yatta Transport Fast Forwarding"
	/etc/ah/Yatta.sh init
	service_echo_end "Yatta Transport Fast Forwarding"
	mkdir -p /tmp/dns
	if [ -f "/usr/sbin/httpd" ]; then
		mkdir /tmp/httpd
		cp /www/conf/http/* /tmp/httpd
	fi
	if [ -x /etc/ah/helper_loopback.sh ]; then
		cmclient -u "init" SET "Device.IP.Interface.[Loopback=true].[Enable=true].Enable" "true"
	fi
	mkdir /tmp/init_iptables
	[ ! -s /tmp/cfg/cache/xdslctl ] && init_dsl
	init_eth
	service_echo "InterfaceMonitor Init"
	cmclient SET "Device.X_ADB_InterfaceMonitor.[Enable=true].Enable" "true"
	service_echo_start "Firewall"
	cachedFirewallv4=0
	cachedFirewallv6=0
	if [ -s /tmp/cfg/cache/iptables ]; then
		if iptables-restore </tmp/cfg/cache/iptables; then
			cachedFirewallv4=1
			if [ -s /tmp/cfg/cache/ip6tables ]; then
				if ip6tables-restore </tmp/cfg/cache/ip6tables; then
					cachedFirewallv6=1
				fi
			fi
			cmclient SETE "Device.UserInterface.RemoteAccess.X_ADB_ACLRule.[Enable=true].Status" "Enabled"
			cmclient SETE "Device.UserInterface.X_ADB_LocalAccess.X_ADB_ACLRule.[Enable=true].Status" "Enabled"
		fi
	fi
	[ $cachedFirewallv6 -eq 0 ] && start_ip6tables
	if [ $cachedFirewallv4 -eq 0 ]; then
		start_iptables
		/etc/ah/Firewall.sh init
		create_acl_local_rules Device.UserInterface.X_ADB_LocalAccess GUILocal
		create_acl_local_rules Device.UserInterface.RemoteAccess GUIRemote
		[ -x /etc/ah/DoS.sh ] && /etc/ah/DoS.sh init "ipv4"
		help_iptables commit
		unset tmpiptablesprefix
		cmclient SET "Device.UserInterface.RemoteAccess.X_ADB_ACLRule.[Enable=true].Refresh" "true"
		cmclient SET "Device.UserInterface.X_ADB_LocalAccess.X_ADB_ACLRule.[Enable=true].Refresh" "true"
		iptables-save | grep -v -- '--comment "nocache"' >/tmp/cfg/cache/iptables
	fi
	if [ $cachedFirewallv6 -eq 0 -a -x /usr/sbin/ip6tables-save ]; then
		[ -x /etc/ah/DoS.sh ] && /etc/ah/DoS.sh init "ipv6"
		ip6tables-save | grep -v -- '--comment "nocache"' >/tmp/cfg/cache/ip6tables
	fi
	create_acl_local_rules Device.ManagementServer CWMP
	create_acl_local_rules Device.X_ADB_SSHServer.LocalAccess SSHLocal
	create_acl_local_rules Device.X_ADB_SSHServer.RemoteAccess SSHRemote
	create_acl_local_rules Device.X_ADB_TelnetServer.LocalAccess TelnetLocal
	create_acl_local_rules Device.X_ADB_TelnetServer.RemoteAccess TelnetRemote
	[ -x /etc/ah/CWMP2.sh ] && create_acl_local_rules Device.X_ADB_ManagementServer CWMP2
	help_iptables_all commit
	unset tmpiptablesprefix
	service_echo_end "Firewall"
	service_echo_start "NAT"
	start_nat
	service_echo_end "NAT"
	service_echo_start "QoS"
	/etc/ah/QoSPolicer.sh init
	/etc/ah/QoSClassification.sh init
	for i in QoS.Flow QoS.X_ADB_IngressShaper QoS.Shaper QoS.App; do
		cmclient SET $i.[Enable=true].Enable true
	done
	[ -x /etc/ah/DoS.sh ] && cmclient SET Firewall.X_ADB_DoS.[Enable=true].Enable true
	cmclient -v dfl_fwpolicy GETV "Device.QoS.DefaultForwardingPolicy" # One random parameter...
	[ ${#dfl_fwpolicy} -ne 0 ] && cmclient SET Device.QoS.DefaultForwardingPolicy "$dfl_fwpolicy"
	service_echo_end "QoS"
	rmdir /tmp/init_iptables
	if [ -f /bin/vectoringd ]; then
		service_echo_start "Vectoring daemon"
		vectoringd &
	fi
	insmod usb-storage
	title_echo "Prepare Networking"
	start_timezone
	start_ebtables &
	init_dev_route &
	info_echo "Init USB Interfaces"
	disable_upstream_obj "Device.USB.Interface" "false" &
	disable_upstream_obj "Device.USB.Interface" "true" &
	init_bridges
	[ -x /etc/ah/AAA.sh ] && /etc/ah/AAA.sh init
	title_echo "Start Networking"
	help_svc_start dns
	cmclient -v rcodes GETV Device.DNS.X_ADB_NoFallbackRCODEs
	[ -n "$rcodes" ] && echo "$rcodes" >/tmp/dns/rcodep
	cmclient -v strictipv GETV Device.DNS.X_ADB_IPVersionRestricted
	[ "$strictipv" = "true" ] && echo "1" >/tmp/dns/strict_ipv_mode
	cmclient -v strictripv GETV Device.DNS.X_ADB_ReqIPVersionOnRedirect
	[ "$strictripv" = "true" ] && echo "1" >/tmp/dns/redirect_qipv
	cmclient SET "Device.DNS.[X_ADB_TCPRestricted=true].X_ADB_TCPRestricted" true
	help_start_object "Device.DNS.Client.Enable" "DNS client" "true"
	cmclient SET "Device.DNS.Client.X_ADB_DynamicServerRule.[Enable=true].Enable" true
	cmclient SET "Device.DNS.Client.X_ADB_DynamicServerRule.[Enable=false].Enable" false
	[ -x /etc/ah/CustomWorkaround.sh ] && /etc/ah/CustomWorkaround.sh "add"
	service_echo_start "DHCP server"
	(
		cmclient SET -u boot "Device.DHCPv4.Server.[Enable=true].Enable" "true"
		service_echo_end "DHCP server"
	) &
	service_echo "LAN Ethernet Interfaces - Power UP! (B)"
	start_eth_power "false" &
	cmclient -u "boot" SET "Device.IP.Interface.[Enable=true].Enable" "true"
	service_echo_start "Filtering"
	/etc/ah/BridgingFilter.sh init
	service_echo_end "Filtering"
	[ -f /etc/sysctl.conf ] && sysctl -p -e >&-
	read -r _ mem_total _ </proc/meminfo
	if [ $mem_total -lt 32000 ]; then
		sysctl -w net.netfilter.nf_conntrack_max=4000
	fi
	cat /proc/net/yatta/ct_reserv_perc >>/proc/net/yatta/ct_reserv_perc
	if [ "$productionMode" -eq 0 ]; then
		if [ -f /etc/ah/WatchDog.sh ]; then
			service_echo_start "WatchDog"
			/etc/ah/WatchDog.sh &
		fi
	fi
	help_start_object "Device.ManagementServer.EnableCWMP" "TR-069 agent (B)" "true" "boot"
	cmclient -v _enable GETV Device.CaptivePortal.Enable
	if [ "$_enable" = "true" ]; then
		service_echo_start "Captive Portal"
		cmclient SET -u boot Device.CaptivePortal.Enable "true"
		service_echo_end "Captive Portal"
	else
		cmclient -v _enable GETV Device.CaptivePortal.X_ADB_ConnDownWarningEnable
		if [ "$_enable" = "true" ]; then
			service_echo_start "Captive Portal"
			cmclient SET -u boot Device.CaptivePortal.X_ADB_ConnDownWarningEnable "true"
			service_echo_end "Captive Portal"
		fi
	fi
	cmclient -v _enable GETV Device.X_ADB_DMZ.Enable
	if [ "$_enable" = "true" ]; then
		service_echo_start "DMZ"
		cmclient SET Device.X_ADB_DMZ.Enable "true"
		service_echo_end "DMZ"
	fi
	if [ -f /etc/ah/PublicPoolMap.sh ]; then
		service_echo_start "Public Pool"
		cmclient SET Device.X_ADB_PublicPool.Map.[Enable=true].Enable true
		service_echo_end "Public Pool"
	fi
	start_ipv6_services
	title_echo "Start Network Services"
	help_svc_start "inetd -f"
	if [ "$currentImage" != "recovery" ]; then
		help_start_object "Device.DNS.Relay.Enable" "DNS forwarder" "true"
		cmclient SET "Device.DNS.Relay.X_ADB_DynamicForwardingRule.[Enable=true].Enable" true
		cmclient SET "Device.DNS.Relay.X_ADB_DynamicForwardingRule.[Enable=false].Enable" false
		if [ -f "/etc/ah/DynamicDNS.sh" ]; then
			cmclient SET "Device.Services.X_ADB_DynamicDNS.Client.[Enable=true].Enable" true
		fi
		help_start_object "Device.Services.X_ADB_RTSPProxy.Enable" "RTSP proxy" "true"
		help_start_object "Device.Services.X_ADB_IGMPProxy.Enable" "IGMP proxy" "true" "" "Device.Services.X_ADB_IGMPProxy.Refresh" "true"
		help_start_object "Device.X_ADB_ParentalControl.Enable" "Parental Control" "true"
		help_start_object "Device.X_ADB_LicenseManager.Enable" "License Manager" "true"
		help_start_object "Device.X_ADB_QoE.DownloadDiagnostics.Report.Enable" "QoE Download Report" "true"
		help_start_object "Device.X_ADB_QoE.UploadDiagnostics.Report.Enable" "QoE Upload Report" "true"
		help_start_object "Device.UPnP.Device.Enable" "UPnP service" "true"
		help_start_object "Device.DLNA.X_ADB_Device.Enable" "DLNA service" "true"
		help_start_object "Device.Services.StorageService.NetworkServer.Enable" "SAMBA filesharing" "true" "Device.Services.StorageService.NetworkServer.X_ADB_SambaRefresh"
		help_start_object "Device.Services.X_ADB_PrinterService.Enable" "CUPS printer sharing service" "true"
		help_start_object "Device.X_ADB_SNMP.Enable" "SNMP agent" "true"
		help_start_object "Device.LLDP.X_ADB_Server.Enable" "LLDP daemon" "true" "boot"
		help_start_object "Device.Routing.RIP.Enable" "RIP daemon" "true" "boot"
		help_start_object "Device.Routing.X_ADB_RIPng.Enable" "RIPng daemon" "true" "boot"
		help_start_object "Device.Routing.X_ADB_BGP.Enable" "BGP daemon" "true" "boot"
		help_start_object "Device.Routing.X_ADB_OSPF.Enable" "OSPF daemon" "true" "boot"
		help_start_object "Device.Routing.X_ADB_OSPFv3.Enable" "OSPFv3 daemon" "true" "boot"
		help_start_object "Device.X_ADB_VRRP.Enable" "VRRP daemon" "true" "boot"
		if [ -d /sys/class/net/wl0 -a -x /bin/wpspbc ]; then
			service_echo_start "WPS/WLAN button service (B)"
			wpspbc >/dev/console 2>&1 &
		fi
		help_start_object "Device.Services.X_ADB_PPPoEProxy.Enable" "PPPoE proxy" "true"
		if [ -x /etc/ah/ExecEnv.sh ]; then
			service_echo "Startup Software Execution Environments"
			cmclient SET "Device.SoftwareModules.ExecEnv.[Enable=true].Enable" true
		fi
		ebtables -t broute -I BROUTING 1 -i wl+ -p 0x886c -j DROP
		local ws_basic ws_adv enabled_radios=""
		cmclient -v ws_basic GETV Device.WiFi.Radio.1.X_ADB_WirelessScheduler.Basic.SchedulerEnabled
		cmclient -v ws_adv GETV Device.WiFi.Radio.1.X_ADB_WirelessScheduler.Advanced.SchedulerEnabled
		if [ "$ws_basic" = "true" -o "$wl_adv" = "true" ]; then
			service_echo_start "WiFi Radio (B)"
			wifiradio_sched_start
			service_echo_end "WiFi Radio"
		else
			cmclient -v enabled_radios GETO "Device.WiFi.Radio.[Enable=true]"
			if [ -n "$enabled_radios" ]; then
				service_echo_start "WiFi Radio (B)"
				for i in $enabled_radios; do
					wifiradio_phy_start "$i"
				done
				service_echo_end "WiFi Radio"
				/etc/ah/WirelessDistributionSystem.sh init
			fi
		fi
		echo
		service_echo_start "VOIP services (B)"
		cmclient -v enable GETV "Device.QoS.App.[ProtocolIdentifier=urn:dslforum-org:sip].Enable"
		if [ "$enable" = "true" ]; then
			help_iptables -t mangle -F SIP
			help_iptables -t mangle -A SIP -p tcp --sport 5060 -j SKIPFC
			help_iptables -t mangle -A SIP -p udp --sport 5060 -j SKIPFC
			help_iptables -t mangle -A SIP -p tcp --dport 5060 -j SKIPFC
			help_iptables -t mangle -A SIP -p udp --dport 5060 -j SKIPFC
		fi
		if [ -x /etc/ah/CMWS.sh ]; then
			help_start_object "Device.X_ADB_CMWS.Enable" "CM Web Service" "true"
		fi
		if [ -x /etc/ah/CWMP2.sh ]; then
			help_start_object "Device.X_ADB_ManagementServer.EnableCWMP" "Secondary CWMP agent (B)" "true" "boot"
		fi
		if [ -x /etc/ah/IperfServer.sh ]; then
			info_echo "Init Iperf Service"
			/etc/ah/IperfServer.sh init && service_echo_start "Iperf Service" && service_echo_end "Iperf Service"
		fi
		if [ -x /sbin/swcagent ]; then
			help_start_object "Device.X_SWISSCOM-COM_Services.API.Agent.Enable" "SWC API Agent" "true"
		fi
	fi
	[ -x /etc/cadBoot.sh ] && . /etc/cadBoot.sh
	/etc/ah/ScanHosts.sh init
	/etc/ah/Time.sh init &
	title_echo "System Ready"
	cmclient SET Device.DeviceInfo.X_ADB_BootDone true
	if [ -f /etc/ah/CheckARSThresholds.sh ]; then
		cmclient -u boot SET Device.X_ADB_AnomalyReportingService.[Enable=true].Enable "true"
	fi
	if [ -f /tmp/cfg/reboot_reason ]; then
		rm /tmp/cfg/reboot_reason
	else
		logger -t "SYSTEM" -p 4 "ARS 3 - Switch-off reboot"
	fi
	/etc/ah/CheckDefaultPassword.sh
}
stop() {
	if pidof voip; then
		echo "STOP" | nc local:/tmp/voip_socket
	fi
	echo waiting 5 seconds
	sleep 5
}
