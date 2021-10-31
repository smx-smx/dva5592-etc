#!/bin/sh /etc/rc.common

exec 1>/dev/null
exec 2>/dev/null

START=70

. /etc/ah/helper_tunnel.sh

start() {
	help_iptables -N "$FW_CHAIN_FILTERFWD"
	help_iptables -A ForwardAllow -j "$FW_CHAIN_FILTERFWD"
	help_iptables -N "$FW_CHAIN_FILTERIN"
	help_iptables -A ServicesIn -j "$FW_CHAIN_FILTERIN"

	cmclient SET "Device.X_ADB_VPN.Server.L2TP.[Enable=true].Enable" "true"
	mkdir -p /tmp/vpn/pptp
	cmclient SET "Device.X_ADB_VPN.Server.PPTP.[Enable=true].Enable" "true"
}
