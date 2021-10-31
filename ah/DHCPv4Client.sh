#!/bin/sh
AH_NAME="DHCPv4Client"
[ "$user" = "${AH_NAME}" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_provisioning.sh
pidfile=/tmp/dhcpc_"$obj"
close_client() {
	local pid="$1"
	kill "$pid"
	rm -f "$pidfile"
}
case "$obj" in
*.SentOption.*)
	cmclient -v _tmp GETV "${obj%%.SentOption.*}.Enable"
	[ "$op" = "s" -a "$_tmp" = "true" ] && cmclient SET "${obj%%.SentOption.*}.Enable" true
	exit 0
	;;
*.ReqOption.*)
	cmclient -v _tmp GETV "${obj%%.ReqOption.*}.Enable"
	[ "$op" = "s" -a "$_tmp" = "true" ] && cmclient SET "${obj%%.ReqOption.*}.Enable" true
	exit 0
	;;
esac
read pid <"$pidfile"
if [ "$op" = "d" ]; then
	help_post_provisioning_remove "$obj.Enable" "true"
	if [ ${#pid} -ne 0 ]; then
		close_client "$pid"
	fi
	exit 0
fi
[ "$changedStatus" = "1" ] && exit 0
[ "$changedEnable" = "0" -a "$newEnable" = "false" ] && exit 0
if [ "$setRenew" = "1" -a "$newRenew" = "true" ]; then
	[ ${#pid} -ne 0 ] && kill -USR1 "$pid"
	exit 0
fi
if [ "$setX_ADB_Release" = "1" -a "$newX_ADB_Release" = "true" ]; then
	[ ${#pid} -ne 0 ] && kill -USR2 "$pid"
	exit 0
fi
if [ "$newEnable" = "false" ]; then
	help_post_provisioning_remove "$obj.Enable" "true"
	if [ ${#pid} -ne 0 ]; then
		close_client "$pid"
		sleep 1
		if [ ${#newInterface} -ne 0 ]; then
			cmclient DEL "$newInterface.IPv4Address.[AddressingType=DHCP]"
		fi
	fi
	cmclient SETE "$obj".Status Disabled
	exit 0
fi
ifp="$newInterface"
cmclient -v ifp_enable GETV "$ifp".Enable
help_lowlayer_ifname_get ifn "$ifp"
[ -z "$ifn" -o "$ifp_enable" = "false" ] && exit 0
optBuf=""
optCust=""
customPolicy=""
if [ -x /etc/ah/CustomDHCPOption.sh ]; then
	. /etc/ah/CustomDHCPOption.sh
	customPolicy=true
fi
cmclient -v opt GETO "$obj".SentOption.[Enable=true]
for opt in $opt; do
	cmclient -v tag GETV "$opt".Tag
	cmclient -v val GETV "$opt".Value
	if [ "$customPolicy" = "true" ]; then
		custom_dhcp_option_sent "optCust" "$opt" "$tag" "$obj"
		[ ${#optCust} -gt 0 ] && optBuf="$optBuf $optCust" && continue
	fi
	case "$tag" in
	1) optBuf="$optBuf -x subnet:$val" ;;
	2) optBuf="$optBuf -x timezone:0x$val" ;;
	3) optBuf="$optBuf -x router:$val" ;;
	5) optBuf="$optBuf -x $tag:$val" ;;
	6) optBuf="$optBuf -x dns:$val" ;;
	9) optBuf="$optBuf -x lprsrv:$val" ;;
	12)
		optBuf="$optBuf -x hostname:$val"
		;;
	13) optBuf="$optBuf -x bootsize:$val" ;;
	15) optBuf="$optBuf -x domain:$val" ;;
	16) optBuf="$optBuf -x swapsrv:$val" ;;
	17) optBuf="$optBuf -x rootpath:$val" ;;
	23) optBuf="$optBuf -x ipttl:$val" ;;
	26) optBuf="$optBuf -x mtu:0x$val" ;;
	28) optBuf="$optBuf -x broadcast:$val" ;;
	33) optBuf="$optBuf -x routes:$val" ;;
	40) optBuf="$optBuf -x nisdomain:$val" ;;
	41) optBuf="$optBuf -x nissrv:$val" ;;
	42) optBuf="$optBuf -x ntpsrv:$val" ;;
	43)
		optBuf="$optBuf -x $tag:$val"
		;;
	44) optBuf="$optBuf -x wins:$val" ;;
	50)
		[ -n "$val" ] && optBuf="$optBuf -r $val"
		;;
	51) optBuf="$optBuf -x lease:$val" ;;
	53) optBuf="$optBuf -x dhcptype:$val" ;;
	54) optBuf="$optBuf -x serverid:$val" ;;
	56) optBuf="$optBuf -x message:$val" ;;
	57) optBuf="$optBuf -x $tag:$(printf "%04X" $val)" ;;
	60)
		cmclient -v type GETV "$opt.X_ADB_Type"
		if [ "$type" = "String" ]; then
			optBuf="$optBuf -x $tag:$(echo -n "$val" | hexdump -ve '/1 "%02X"')"
		else
			optBuf="$optBuf -x $tag:$val"
		fi
		;;
	61)
		optBuf="$optBuf -x $tag:$(echo -n "$val" | hexdump -ve '/1 "%02X"')"
		;;
	66) optBuf="$optBuf -x tftp:$val" ;;
	67) optBuf="$optBuf -x bootfile:$val" ;;
	77) optBuf="$optBuf -x $tag:$(echo -n "$val" | hexdump -ve '/1 "%02X"')" ;;
	118) optBuf="$optBuf -x $tag:$(printf "%02X%02X%02X%02X" $(echo "$val" | tr -s "." " "))" ;;
	119) optBuf="$optBuf -x search:$val" ;;
	120) optBuf="$optBuf -x sipsrv:$val" ;;
	121) optBuf="$optBuf -x staticroutes:$val" ;;
	124) optBuf="$optBuf -x $tag:$(echo -n "$val" | hexdump -ve '/1 "%02X"')" ;;
	125)
		subopt=""
		suboptBuf=""
		cmclient -v subopt GETO "$opt".X_ADB_SentSubOption.[Enable=true]
		for subopt in $subopt; do
			cmclient -v suboptTag GETV "$subopt".Tag
			suboptTag=$(printf %02X $suboptTag)
			cmclient -v suboptValue GETV "$subopt".Value
			if [ -z "$suboptValue" ]; then
				cmclient -v suboptReference GETV "$subopt".Reference
				cmclient -v suboptValue GETV $suboptReference
			fi
			suboptLen=$(printf %02X ${#suboptValue})
			suboptBuf=$suboptBuf$suboptTag$suboptLen$(echo -n "$suboptValue" | hexdump -ve '/1 "%02X"')
		done
		if [ ${#suboptBuf} -gt 0 ]; then
			suboptLen=$((${#suboptBuf} / 2))
			suboptLen=$(printf %02X $suboptLen)
			suboptBuf=$val$suboptLen$suboptBuf
			optBuf="$optBuf -x $tag:$suboptBuf"
		else
			optBuf="$optBuf -x $tag:$val"
		fi
		;;
	249) optBuf="$optBuf -x msstaticroutes:$val" ;;
	esac
done
cmclient -v opt GETO "$obj".ReqOption.[Enable=true]
for opt in $opt; do
	cmclient -v tag GETV "$opt".Tag
	cmclient -u ${AH_NAME} SET "${opt}.Value" ""
	case "$tag" in
	1) optBuf="$optBuf -O subnet" ;;
	2) optBuf="$optBuf -O timezone" ;;
	3) optBuf="$optBuf -O router" ;;
	6) optBuf="$optBuf -O dns" ;;
	9) optBuf="$optBuf -O lprsrv" ;;
	12) optBuf="$optBuf -O hostname" ;;
	13) optBuf="$optBuf -O bootsize" ;;
	15) optBuf="$optBuf -O domain" ;;
	16) optBuf="$optBuf -O swapsrv" ;;
	17) optBuf="$optBuf -O rootpath" ;;
	23) optBuf="$optBuf -O ipttl" ;;
	26) optBuf="$optBuf -O mtu" ;;
	28) optBuf="$optBuf -O broadcast" ;;
	33) optBuf="$optBuf -O routes" ;;
	40) optBuf="$optBuf -O nisdomain" ;;
	41) optBuf="$optBuf -O nissrv" ;;
	42) optBuf="$optBuf -O ntpsrv" ;;
	43) optBuf="$optBuf -O acsurl" ;;
	44) optBuf="$optBuf -O wins" ;;
	51) optBuf="$optBuf -O lease" ;;
	54) optBuf="$optBuf -O serverid" ;;
	56) optBuf="$optBuf -O message" ;;
	58) optBuf="$optBuf -O renewal" ;;
	59) optBuf="$optBuf -O rebind" ;;
	66) optBuf="$optBuf -O tftp" ;;
	67) optBuf="$optBuf -O bootfile" ;;
	119) optBuf="$optBuf -O search" ;;
	120) optBuf="$optBuf -O sipsrv" ;;
	121) optBuf="$optBuf -O staticroutes" ;;
	249) optBuf="$optBuf -O msstaticroutes" ;;
	esac
done
if [ ${#pid} -ne 0 ]; then
	close_client "$pid"
	i=0
	while [ -d /proc/$pid -a $i -lt 10 ]; do
		sleep 0.5
		i=$((i + 1))
	done
	if [ -d /proc/$pid ]; then
		echo "Stucked udhcpc at $obj. Killing with -9" >/dev/console
		kill -9 "$pid"
	fi
fi
cmclient -v dhcp_dscp GETV "$obj.X_ADB_DSCPMark"
dhcp_dscp=${dhcp_dscp:-0}
if help_post_provisioning_add "$obj.Enable" "true" "Default"; then
	(udhcpc -S -R -o -C $optBuf -i $ifn -D $dhcp_dscp -s /etc/ah/dhcpc.sh -p $pidfile || touch "$pidfile"_error) &
else
	exit 0
fi
while [ ! -f "$pidfile" -a ! -f $pidfile"_error" ]; do
	sleep 0.5
done
[ -f "$pidfile" ] && cmclient SETE "$obj".Status Enabled || cmclient SETE "$obj".Status Error
rm -f $pidfile"_error"
exit 0
