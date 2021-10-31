#!/bin/sh

[ -z "$TR181_ID" ] && exit 0
ev_msg="$1"
filter_obj=Device.IPsec.Filter.${TR181_ID}

### update TR 181
cmclient -v tun GETO Device.IPsec.Tunnel.[Filters=$filter_obj]

case $ev_msg in
	"phase1_up")
		### Redundant but safe check
		cmclient -v isa GETO "Device.IPsec.IKEv2SA.[X_ADB_ID=$PH1_ID]"
		if [ -z "$isa" ]; then
			cmclient -v isa ADD Device.IPsec.IKEv2SA
			isa="Device.IPsec.IKEv2SA.${isa}"
			setm="${isa}.Status=Up"
			setm="$setm	${isa}.Tunnel=$tun"
			setm="$setm	${isa}.LocalAddress=$LOCAL_ADDR"
			setm="$setm	${isa}.RemoteAddress=$REMOTE_ADDR"
			setm="$setm	${isa}.X_ADB_ID=$PH1_ID"
			cmclient SETM "$setm"
		fi
		;;
	"phase1_down")
		cmclient DEL Device.IPsec.IKEv2SA.[Tunnel=${tun}].[X_ADB_ID=${PH1_ID}]
		;;
	"phase1_dead")
		cmclient SETE Device.IPsec.IKEv2SA.[Tunnel=${tun}].[X_ADB_ID=${PH1_ID}].Status "Down"
		;;
esac

###	-- Common --
#	LOCAL_ADDR	LOCAL_PORT	TR181_ID
#	REMOTE_ADDR	REMOTE_PORT	REMOTE_ID
#
#	-- RW mode only --
#	XAUTH_USER
#	INTERNAL_ADDR4	INTERNAL_CIDR4	INTERNAL_NETMASK4

### customized handler
[ -e /etc/ipsec/custom_ph1.sh ] && . /etc/ipsec/custom_ph1.sh || . /etc/ipsec/common_ph1.sh

cmclient -v RWMODE GETV ${filter_obj}.X_ADB_RoadWarrior.Enable

if [ "$RWMODE" = "true" ]; then
	### Here we must check if we are starting the first ph1 tunnel or
	#   closing the last one in order to create/destroy policy/fw rules
	case $ev_msg in
		"phase1_up")
			[ -z "$INTERNAL_ADDR4" ] && return
			;;
		"phase1_down")
			cmclient -v ph1end GETO Device.IPsec.IKEv2SA.[Tunnel=${tun}]
			[ -n "$ph1end" ] && return
			;;
		*)
			return
			;;
	esac

	### So, create policy/fw rules
	cmclient -v RWTYPE GETV ${filter_obj}.X_ADB_RoadWarrior.Type

	case $RWTYPE in
		"L2TP")		l2tp_config "$ev_msg"	;;
		"Pure")		pure_config "$ev_msg"	;;
		"XAuth")	xauth_config "$ev_msg"	;;
	esac
fi
