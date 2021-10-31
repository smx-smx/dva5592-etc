#!/bin/sh
. /etc/ah/helper_wwan.sh
command -v help_serialize >/dev/null || . /etc/ah/helper_serialize.sh
wwan_get_signalpercent()
{
[ "$1" = val ] || local val
wwanmodem_get_signaldbm val || return 1
val=$(((val+113)*100/62))
[ "$val" -lt 0 ] && val=0
[ "$val" -gt 100 ] && val=100
eval $1='${val:-0}'
}
wwan_handleget()
{
local proto ok arg val active_sim
help_wwan_checkproto proto || return 1
for arg
do
val=
case "$arg" in
SignalStrengthPercent)
wwan_get_signalpercent val
;;
SignalStrengthDBm)
wwanmodem_get_signaldbm val
;;
AccessTechnology)
wwanmodem_get_accesstech val
;;
LocationAreaCode)
wwanmodem_get_lac val
;;
CellID)
wwanmodem_get_cellid val
;;
PeakReceiveRate)
cmclient -v active_sim GETV Device.X_ADB_MobileModem.Interface.1.ActiveSIMCard
[ "$obj" = "${active_sim}.Stats" ] && wwanmodem_get_peak_receive_rate val
;;
PeakSendRate)
cmclient -v active_sim GETV Device.X_ADB_MobileModem.Interface.1.ActiveSIMCard
[ "$obj" = "${active_sim}.Stats" ] && wwanmodem_get_peak_send_rate val
;;
esac
echo $val
done
}
