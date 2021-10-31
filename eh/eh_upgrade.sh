#!/bin/sh
#inotify:/tmp/upgrade
. /etc/ah/helper_svc.sh
case "$OBJ" in
cfg-backup_*)
	[ ! -p "/tmp/upgrade/$OBJ" ] && exit 0
	IFS="_"
	set -- $OBJ
	unset IFS
	shift
	/usr/sbin/backup-conf.sh "$@" "/tmp/upgrade/$OBJ"
	exit 0
	;;
cfg-restore | cfg-restore-user)
	/usr/sbin/upgrade-conf.sh "/tmp/upgrade/$OBJ"
	;;
upgrade-prepare*)
	[ "$OBJ" = "upgrade-prepare-usb" ] && _src="usb"
	plist="cwmp"
	/usr/sbin/upgrade-prepare.sh "${_src}" $plist
	;;
fw.bin)
	help_svc_stop_multi ec nhttpd httpd
	mkdir -p /tmp/cfg/GUI
	echo -n "0;OK" >/tmp/cfg/GUI/reportfwupgrade
	/usr/sbin/upgrade.sh "/tmp/upgrade/$OBJ"
	res=$?
	echo -n "$res;" >/tmp/cfg/GUI/reportfwupgrade
	tail -n 1 /tmp/upgrade.log >>/tmp/cfg/GUI/reportfwupgrade
	reboot
	;;
fw.url)
	help_svc_stop ec nhttpd httpd
	mkdir -p /tmp/cfg/GUI
	echo -n "0;OK" >/tmp/cfg/GUI/reportfwupgrade
	/usr/sbin/upgrade.sh "$(cat "/tmp/upgrade/$OBJ")"
	res=$?
	echo -n "$res;" >/tmp/cfg/GUI/reportfwupgrade
	tail -n 1 /tmp/upgrade.log >>/tmp/cfg/GUI/reportfwupgrade
	reboot
	;;
swmodule.txt)
	if [ -x /etc/ah/SW-DeploymentUnit.sh ]; then
		rm -f /tmp/swmodule.log
		i=1
		while read -r line; do
			eval par$i='$line'
			i=$((i + 1))
		done <"/tmp/upgrade/$OBJ"
		/etc/ah/SW-DeploymentUnit.sh "$par1" "$par2" "$par3" "$par4" "$par5" "$par6" "$par7" "$par8"
		echo -n $? >/tmp/swmodule.log
		chmod a+w /tmp/swmodule.log
	fi
	;;
cwmp.pem)
	cp "/tmp/upgrade/$OBJ" /tmp/cfg/CWMP/ca.pem
	;;
cwmp2.pem)
	cp "/tmp/upgrade/$OBJ" /tmp/cfg/CWMP2/ca.pem
	;;
syslog_ca.pem)
	cp "/tmp/upgrade/$OBJ" "/etc/certs/$OBJ"
	;;
ctrl-cacert-production.pem)
	cp "/tmp/upgrade/$OBJ" "/etc/certs/$OBJ"
	;;
*)
	exit 0
	;;
esac
rm -f /tmp/upgrade/"$OBJ"
