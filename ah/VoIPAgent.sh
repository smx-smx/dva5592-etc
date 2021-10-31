#!/bin/sh
AH_NAME="VoipAgent"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
consoleDebug="n"
if [ "$1" = "r" ]; then
	op="r"
else
	if [ "$newIdentity" != "Voip" ]; then
		exit 0
	fi
	if [ "$changedStatus" = "0" -a $changedPriority = "0" ]; then
		exit 0
	fi
fi
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize >/dev/null
. /etc/ah/helper_functions.sh
logVoipConf="/etc/voip/agent.conf"
voip_debug_file_update() {
	echo ""
	echo "[debug]"
	if [ "$consoleDebug" = "y" ]; then
		echo "LogLevel = DEBUG"
		echo "LogOutput = CONSOLE"
		return
	fi
	level="INFO"
	case "$newPriority" in
	"7") level="DEBUG" ;;
	"6" | "5") level="INFO" ;;
	"4") level="WARNING" ;;
	"3" | "2" | "1") level="ERROR" ;;
	esac
	echo "LogLevel = $level"
	if [ "$newStatus" = "Enabled" ]; then
		echo "LogOutput = SYSLOG"
	else
		echo "LogOutput = "
	fi
}
case "$op" in
s)
	voip_debug_file_update >${logVoipConf}.tmp
	mv ${logVoipConf}.tmp $logVoipConf
	: >/etc/voip/reload
	;;
r)
	cmclient -v newPriority GETV Device.X_ADB_SystemLog.Service.*.[Identity=Voip].Priority
	cmclient -v newStatus GETV Device.X_ADB_SystemLog.Service.*.[Identity=Voip].Status
	voip_debug_file_update >${logVoipConf}
	;;
esac
exit 0
