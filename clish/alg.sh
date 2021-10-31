#!/bin/sh
. /etc/clish/clish-commons.sh
ADD="cmclient ADD "
GETO="cmclient GETO "
GETV="cmclient GETV "
alg_map() {
	case "$1" in
	ftp)
		algURN=urn:dslforum-org:ftp
		;;
	h323)
		algURN=urn:dslforum-org:h323
		;;
	icmp)
		algURN=urn:dslforum-org:icmp
		;;
	irc)
		algURN=urn:dslforum-org:irc
		;;
	pppoe)
		algURN=urn:dslforum-org:pppoe
		;;
	pptp)
		algURN=urn:dslforum-org:pptp
		;;
	rtsp)
		algURN=urn:dslforum-org:rtsp
		;;
	sip)
		algURN=urn:dslforum-org:sip
		;;
	tftp)
		algURN=urn:dslforum-org:tftp
		;;
	ipsec)
		algURN=urn:dslforum-org:ipsec
		;;
	*)
		echo $1 alg is unknown
		;;
	esac
}
alg_config() {
	alg_map $1
	obj=$($GETO Device.QoS.App.*.[ProtocolIdentifier=$algURN])
	if [ -z "$obj" ]; then
		idx=$($ADD Device.QoS.App.)
		obj=Device.QoS.App.$idx
		. /etc/clish/quick_cm.sh setm "$obj.ProtocolIdentifier=$algURN"
	fi
	. /etc/clish/quick_cm.sh setm "$obj.Enable=$2"
}
alg_show() {
	for obj in $($GETO Device.QoS.App.); do
		printf "%-7s %s\n" \
			$($GETV $obj.ProtocolIdentifier | sed 's/urn:dslforum-org://') \
			$($GETV $obj.Enable)
	done
}
case "$1" in
show)
	alg_show
	;;
ftp | h323 | icmp | irc | pppoe | pptp | rtsp | sip | tftp | ipsec)
	alg_config $1 $2
	;;
*)
	echo $0:$1 unknown command
	;;
esac
