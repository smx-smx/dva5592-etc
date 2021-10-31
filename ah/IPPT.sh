#!/bin/sh
AH_NAME="IPPT"
[ "$user" = "${AH_NAME}${obj}" ] || [ "$user" = "DMZ" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize >/dev/null
. /etc/ah/helper_functions.sh
disable_uippt() {
	local check_dev status="$newX_ADB_PassthroughStatus" eth_name_old="$oldX_ADB_PassthroughLayer1Interface"
	if [ "$status" = "Enabled" -o "$status" = "Misconfigured" ]; then
		cmclient SET -u ${AH_NAME}${obj} Device.X_ADB_DMZ.Enable "false"
		uIppt disable >/dev/null
		brctl delif "$gw_name" ippt0 >/dev/null
		ifconfig ippt0 down >/dev/null
		if [ ${#eth_name_old} -ne 0 ]; then
			check_dev=$(expr substr "$eth_name_old" 1 3)
			[ "$check_dev" = "eth" ] && brctl addif "$gw_name" "$eth_name_old" >/dev/null
		fi
		echo "IPPT.sh disable_uippt ($eth_name_old)" >/dev/console
		echo "last_chk_ok=false" >/tmp/IPP_last_cmd.sh
	fi
}
enable_uippt() {
	local check_dev
	ifconfig ippt0 up >/dev/null
	brctl addif "$gw_name" ippt0 >/dev/null
	uIppt set_wan_ip "$wan_ip" >/dev/null
	uIppt set_gw_ip "$gw_ip" >/dev/null
	echo "last_chk_ok=true" >/tmp/IPP_last_cmd.sh
	echo "last_gw_name=$gw_name" >>/tmp/IPP_last_cmd.sh
	echo "last_wan_ip=$wan_ip" >>/tmp/IPP_last_cmd.sh
	echo "last_gw_ip=$gw_ip" >>/tmp/IPP_last_cmd.sh
	if [ "$newX_ADB_PassthroughUserDefined" = "false" ]; then
		if [ ${#eth_name} -ne 0 ]; then
			check_dev=$(expr substr "$eth_name" 1 3)
			[ "$check_dev" = "eth" ] && brctl delif "$gw_name" "$eth_name" >/dev/null
		fi
		uIppt connect ippt0 "$eth_name" >/dev/null
		uIppt set_mac "$mac" >/dev/null
		uIppt enable "$host_ip" >/dev/null
		cmclient -u "${AH_NAME}${obj}" SET Device.X_ADB_DMZ.IPAddress "$host_ip"
		echo "IPPT.sh enable_uippt: ($gw_name - $wan_ip - $gw_ip - $eth_name - $mac - $host_ip)" >/dev/console
		echo "last_mac=$mac" >>/tmp/IPP_last_cmd.sh
		echo "last_eth_name=$eth_name" >>/tmp/IPP_last_cmd.sh
		echo "last_host_ip=$host_ip" >>/tmp/IPP_last_cmd.sh
	else
		if [ ${#mac} -ne 0 ] && [ ${#host_ip} -ne 0 ]; then
			[ ${#eth_name} -ne 0 ] && brctl delif "$gw_name" "$eth_name" >/dev/null
			uIppt connect ippt0 "$eth_name" >/dev/null
			uIppt set_mac "$mac" >/dev/null
			uIppt enable "$host_ip" >/dev/null
			cmclient -u "${AH_NAME}${obj}" SET Device.X_ADB_DMZ.IPAddress "$host_ip"
			echo "IPPT.sh enable_uippt: ($gw_name - $wan_ip - $gw_ip - $eth_name - $mac - $host_ip)" >/dev/console
			echo "last_mac=$mac" >>/tmp/IPP_last_cmd.sh
			echo "last_eth_name=$eth_name" >>/tmp/IPP_last_cmd.sh
			echo "last_host_ip=$host_ip" >>/tmp/IPP_last_cmd.sh
		else
			uIppt enable "0.0.0.0" >/dev/null
			uIppt set_mac "00:00:00:00:00:00" >/dev/null
			echo "IPPT.sh enable_uippt: ($gw_name - $wan_ip - $gw_ip - 0.0.0.0)" >/dev/console
			echo "last_mac=" >>/tmp/IPP_last_cmd.sh
			echo "last_eth_name=" >>/tmp/IPP_last_cmd.sh
			echo "last_host_ip=0.0.0.0" >>/tmp/IPP_last_cmd.sh
		fi
	fi
	cmclient SET -u ${AH_NAME}${obj} Device.X_ADB_DMZ.Enable "true"
}
check_config() {
	local host="" eth_gw ip_pref ip_last host_ip_proposal hosts \
		eth_name="$newX_ADB_PassthroughLayer1Interface" ip_intf="Device.IP.Interface.1"
	cmclient -v wan_ip GETV "$newInterface.IPv4Address.1.IPAddress"
	cmclient -v gw_ip GETV "$ip_intf.IPv4Address.1.IPAddress"
	cmclient -v eth_gw GETV "$ip_intf.LowerLayers"
	cmclient -v gw_name GETV "$eth_gw.Name"
	if [ "$changedX_ADB_AssociatedHost" = "1" -a ${#newX_ADB_AssociatedHost} -ne 0 ]; then
		host="$newX_ADB_AssociatedHost"
		cmclient -v mac GETV "$host".PhysAddress
		cmclient -u "${AH_NAME}${obj}" SET Device.X_ADB_DMZ.X_ADB_PassthroughMACAddress "$mac"
	elif [ "$changedX_ADB_PassthroughMACAddress" = "1" -a ${#newX_ADB_PassthroughMACAddress} -ne 0 ]; then
		cmclient -v host GETO "Device.Hosts.Host.*.[PhysAddress=$newX_ADB_PassthroughMACAddress]"
		mac="$newX_ADB_PassthroughMACAddress"
		cmclient -u "${AH_NAME}${obj}" SET Device.X_ADB_DMZ.X_ADB_AssociatedHost "$host"
	elif [ ${#newX_ADB_AssociatedHost} -ne 0 ]; then
		host="$newX_ADB_AssociatedHost"
		cmclient -v mac GETV "$host.PhysAddress"
		cmclient -u "${AH_NAME}${obj}" SET Device.X_ADB_DMZ.X_ADB_PassthroughMACAddress "$mac"
	elif [ ${#newX_ADB_PassthroughMACAddress} -ne 0 ]; then
		cmclient -v host GETO "Device.Hosts.Host.*.[PhysAddress=$newX_ADB_PassthroughMACAddress]"
		mac="$newX_ADB_PassthroughMACAddress"
		cmclient -u "${AH_NAME}${obj}" SET Device.X_ADB_DMZ.X_ADB_AssociatedHost "$host"
	fi
	if [ "$newX_ADB_PassthroughUserDefined" = "false" ]; then
		if [ ${#host} -ne 0 ]; then
			cmclient -v host_ip GETV "$host.IPAddress"
			[ ${#gw_name} -ne 0 -a ${#gw_ip} -ne 0 -a ${#host_ip} -ne 0 -a ${#wan_ip} -ne 0 -a ${#mac} -ne 0 ] && chk_ok="true"
		fi
	else
		[ ${#host} -ne 0 ] && cmclient -v host_ip GETV "$host.IPAddress"
		if [ ${#host_ip} -eq 0 -a "$newX_ADB_PassthroughUserDefined" = "true" ]; then
			cmclient -v host_ip_proposal GETV "Device.DHCPv4.Server.Pool.1.MaxAddress"
			ip_pref=${host_ip_proposal%.*}
			ip_last=${host_ip_proposal##*.}
			cmclient -v hosts GETO "Device.Hosts.Host.[IPAddress=$host_ip_proposal]"
			while [ ${#hosts} -ne 0 ]; do
				ip_last=$((ip_last - 1))
				[ "$ip_last" -gt 2 ] && cmclient -v hosts GETO "Device.Hosts.Host.[IPAddress=$ip_pref.$ip_last]" || break
			done
			[ ${#hosts} -eq 0 ] && host_ip="$ip_pref.$ip_last"
		fi
		[ ${#gw_name} -ne 0 -a ${#gw_ip} -ne 0 -a ${#wan_ip} -ne 0 ] && chk_ok="true"
	fi
}
reconf_ippt() {
	local reconf_needed=""
	echo "last_ippt_reconf=yes" >>/tmp/IPP_last_cmd.sh
	. /tmp/IPP_last_cmd.sh
	if [ "$gw_name" != "$last_gw_name" ] || [ "$gw_ip" != "$last_gw_ip" ] || [ "$wan_ip" != "$last_wan_ip" ]; then
		reconf_needed="yes"
	fi
	if [ "$mac" != "$last_mac" ] || [ "$host_ip" != "$last_host_ip" ] || [ "$eth_name" != "$last_eth_name" ]; then
		reconf_needed="yes"
	fi
	if [ "$chk_ok" != "$last_chk_ok" ]; then
		reconf_needed="yes"
	fi
	if [ "$reconf_needed" = "yes" ]; then
		disable_uippt
		enable_ippt
	fi
}
enable_ippt() {
	if [ "$chk_ok" = "true" ]; then
		enable_uippt
		cmclient SET -u ${AH_NAME}${obj} "Device.X_ADB_DMZ.X_ADB_PassthroughStatus" "Enabled"
	else
		cmclient SET -u ${AH_NAME}${obj} "Device.X_ADB_DMZ.X_ADB_PassthroughStatus" "Misconfigured"
	fi
}
disable_ippt() {
	disable_uippt
	cmclient SET -u ${AH_NAME}${obj} "Device.X_ADB_DMZ.X_ADB_PassthroughStatus" "Disabled"
	cmclient SET -u ${AH_NAME}${obj} Device.X_ADB_DMZ.IPAddress ""
}
check_reserved_ip() {
	local setm_param="" static_obj static_mac static_ip static_ena
	if [ ${#mac} -ne 0 ] && [ ${#host_ip} -ne 0 ] && [ "$chk_ok" = "true" ]; then
		cmclient -v static_obj GETO "Device.DHCPv4.Server.Pool.1.StaticAddress.*.[Alias=IPPT_reserved_ip]"
		if [ ${#static_obj} -eq 0 ]; then
			cmclient -v static_obj ADD "Device.DHCPv4.Server.Pool.1.StaticAddress"
			static_obj="Device.DHCPv4.Server.Pool.1.StaticAddress.$static_obj"
		fi
		cmclient -v static_mac GETV "$static_obj.Chaddr"
		cmclient -v static_ip GETV "$static_obj.Yiaddr"
		cmclient -v static_ena GETV "$static_obj.Enable"
		if [ "$static_mac" != "$mac" ] || [ "$static_ip" != "$host_ip" ] || [ "$static_ena" != "true" ]; then
			setm_param="$static_obj.Alias=IPPT_reserved_ip"
			setm_param="$setm_param	$static_obj.Chaddr=$mac"
			setm_param="$setm_param	$static_obj.Yiaddr=$host_ip"
			setm_param="$setm_param	$static_obj.Enable=true"
			cmclient SETM "$setm_param"
		fi
	else
		cmclient -v static_obj GETO "Device.DHCPv4.Server.Pool.1.StaticAddress.*.[Alias=IPPT_reserved_ip]"
		if [ ${#static_obj} -ne 0 ]; then
			cmclient -v static_mac GETV "$static_obj.Chaddr"
			cmclient -v static_ip GETV "$static_obj.Yiaddr"
			cmclient -v static_ena GETV "$static_obj.Enable"
			if [ ${#static_mac} -ne 0 ] || [ ${#static_ip} -ne 0 ] || [ "$static_ena" != "false" ]; then
				setm_param="$static_obj.Alias=IPPT_reserved_ip"
				setm_param="$setm_param	$static_obj.Chaddr="
				setm_param="$setm_param	$static_obj.Yiaddr="
				setm_param="$setm_param	$static_obj.Enable=false"
				cmclient SETM "$setm_param"
			fi
		fi
	fi
}
case "$op" in
s)
	chk_ok="false"
	if [ "$changedX_ADB_UseAllocatedWAN" = "0" -a "$newX_ADB_UseAllocatedWAN" = "Normal" ]; then
		cmclient SET -u ${AH_NAME}${obj} "Device.X_ADB_DMZ.X_ADB_PassthroughStatus" "Disabled"
		check_reserved_ip
		exit 0
	fi
	if [ "$changedX_ADB_UseAllocatedWAN" = "1" -a "$newX_ADB_UseAllocatedWAN" = "Normal" ]; then
		check_config
		disable_ippt
		check_reserved_ip
		exit 0
	fi
	if [ "$changedX_ADB_UseAllocatedWAN" = "0" -a "$newX_ADB_UseAllocatedWAN" = "Passthrough" ]; then
		check_config
		reconf_ippt
		check_reserved_ip
		exit 0
	fi
	if [ "$changedX_ADB_UseAllocatedWAN" = "1" -a "$newX_ADB_UseAllocatedWAN" = "Passthrough" ]; then
		check_config
		enable_ippt
		check_reserved_ip
		exit 0
	fi
	;;
esac
exit 0
