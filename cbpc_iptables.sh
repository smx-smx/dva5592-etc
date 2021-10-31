#!/bin/sh

. /etc/ah/helper_firewall.sh

mode=$1
  case  "$mode"  in
    "IPT")

	type=$2
	dest_ip=$3
	mac_add=$4
	dport=$5
	onport=$6
	onip=$7
	res=""

	if [ "$dport" = "443" ]; then
		onport="3130"

		if [ "$type" = "D" ]; then
			res=`iptables-save -t nat |grep -i "\-A CbpcRedirect \-d "$dest_ip"\/32 \-p tcp \-m mac \-\-mac\-source "$mac_add" \-m tcp \-\-dport "$dport" \-m comment \-\-comment \"nocache\" \-j REDIRECT"`
		fi

		if [ ! -n "$res" ] && [ "$type" = "D" ]; then
			null=""
		else
			help_iptables_no_cache -t nat -"$type" CbpcRedirect -d "$dest_ip" -p tcp -m mac --mac-source "$mac_add" --dport "$dport" -j REDIRECT --to-port "$onport" >/dev/null
		fi

	else
		if [ "$type" = "D" ]; then
			res=`iptables-save -t mangle |grep -i "\-A CbpcRedirect \-d "$dest_ip"\/32 \-p tcp \-m state \-\-state ESTABLISHED \-m mac \-\-mac\-source "$mac_add" "`
		fi

		if [ ! -n "$res" ] && [ "$type" = "D" ]; then
			null=""
		else
			help_iptables_no_cache -t mangle -"$type" CbpcRedirect -d "$dest_ip" -p tcp -m state --state ESTABLISHED -m mac --mac-source "$mac_add" -m multiport --dport "$dport",21  -j TPROXY --on-port "$onport"  --tproxy-mark 0xffff --on-ip "$onip" >/dev/null
		fi
	fi

	;;

    "IPTWAN")

	type=$2
	dest_ip=$3
	mac_add=$4
	dport=$5
	onport=$6

	help_iptables_no_cache -t mangle -"$type" PC --destination "$dest_ip" -p tcp -m mac --mac-source "$mac_add" --dport "$dport"  -j RETURN >/dev/null

	;;


     "SET-TOD-ENA")

	# the .policy.1 is 'Low' policy is read only
	# SET used to call the Handler /etc/ah/ParentalControl.sh with env symbol $setTimeOfDayEnable = "1"
	if [ -x "/etc/ah/RestrictedHost.sh" ]; then
		cmclient -v tod_enable GETV "Device.X_ADB_ParentalControl.Policy.1.TimeOfDayEnable"
		cmclient SET Device.X_ADB_ParentalControl.Policy.1.TimeOfDayEnable $tod_enable
	fi
	;;

      "TIME-CUR_POL")

	type=$2
	mac=$3
	policyID=$4

	cmclient -v dev GETO "Device.X_ADB_ParentalControl.PolicyDeviceAssociation.*.[MacAddress="${mac}"]"
	if [ "$type" = "SET" ]; then
		cmclient -v pol GETO "Device.X_ADB_ParentalControl.Policy.*.[PolicyID="${policyID}"]"
		cmclient -u "noUpdate" SET "${dev}.CurrentPolicy ${pol}" >/dev/null
		dt=`date -u +%FT%TZ`
		#echo "${type} ${mac} Device.CurrentPolicy = ${pol}" >/dev/console
	else
		#preass=`cmclient GET "${dev}.PreAssignedPolicy"`
		preass=""
		cmclient -u "noUpdate" SET "${dev}.CurrentPolicy ${preass}" >/dev/null
		dt="0001-01-01T00:00:00Z"
		#echo "${type} ${mac} Device.CurrentPolicy = ${preass}" >/dev/console
	fi
	#echo "${type} ${mac} Device.PolicyOverrideTimestamp = ${dt}" >/dev/console

	cmclient -u "noUpdate" SET "${dev}.PolicyOverrideTimestamp ${dt}" >/dev/null
	### cmclient SET Device.X_ADB_ParentalControl.UrlFilterRefresh true ## TODO, this should be triggered when CurrentPolicy changes.
	;;

	*)
	;;
  esac

