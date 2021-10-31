#!/bin/sh
AH_NAME=WWAN
. /etc/ah/helper_wwan.sh
. /etc/ah/helper_functions.sh
command -v help_serialize >/dev/null || . /etc/ah/helper_serialize.sh
MODEM_LOCK=mmlock
wwan_initialize()
{
wwanmodem_initialize && return 0
wwan_updatestatus "ERROR" "Unable to initialize modem"
wwanmodem_reset
return 1
}
wwan_get_simobj()
{
[ "$1" != "iccid" ] && local iccid
[ "$1" != "imei" ] && local imei
[ "$1" != "sobj" ] && local sobj
[ "$1" != "setem" ] && local setem
wwanmodem_get_iccid "iccid"
wwanmodem_get_imei "imei"
sobj=""
setem=""
while [ -z "$sobj" ]; do
if [ -n "$iccid" ] ; then
cmclient -v sobj GETO X_ADB_MobileModem.SIMCard.[ICCID=${iccid}]
if [ -n "$sobj" ]; then
[ -n "$imei" ] && setem="${sobj}.IMEI=$imei	"
break
fi
elif [ -n "$imei" ] ; then
cmclient -v sobj GETO X_ADB_MobileModem.SIMCard.[IMEI=${imei}]
if [ -n "$sobj" ]; then
[ -n "$iccid" ] && setem="${sobj}.ICCID=$iccid	"
break
fi
fi
cmclient -v sobj ADD X_ADB_MobileModem.SIMCard
setem="Device.X_ADB_MobileModem.SIMCard.${sobj}.Name=SIM $sobj	"
sobj=Device.X_ADB_MobileModem.SIMCard.${sobj}
[ -n "$imei" ] && setem="${setem}${sobj}.IMEI=$imei	"
[ -n "$iccid" ] && setem="${setem}${sobj}.ICCID=$iccid	"
done
cmclient SETEM "$setem"
eval $1='$sobj'
}
wwan_simstat_align()
{
[ "$1" != sstat ] && local sstat
[ "$1" != sauthst ] && local sauthst
[ "$1" != sauthrq ] && local sauthrq
[ "$1" != sobj ] && local sobj
[ "$1" != retval ] && local retval
[ "$1" != pinen ] && local pinen
[ "$1" != pinra ] && local pinra
[ "$1" != pukra ] && local pukra
[ "$1" != setm ] && local setm
setm=""; pinen=""; pinra=""; pukra=""
sobj="$2"
retval=1
wwanmodem_get_simstat "sstat" || sstat=""
wwanmodem_get_pinra "pinra" || pinra="0"
wwanmodem_get_pukra "pukra" || pukra="0"
case $sstat in
"NOSIM")
sauthrq=None; sauthst=Error ;;
"PINREQ_WAIT")
pinen=true; sauthrq=PINRequested; sauthst=Error; retval=0 ;;
"PINREQ_DONE")
pinen=true; sauthrq=PINRequested; sauthst=Authenticated; retval=0 ;;
"PINREQ_ERROR")
pinen=true; sauthrq=PINRequested; sauthst=Error ;;
"PUKREQ_WAIT")
pinen=true; sauthrq=PUKRequested; sauthst=Error; retval=0 ;;
"PUKREQ_DONE")
pinen=true; sauthrq=PUKRequested; sauthst=Authenticated; retval=0 ;;
"PUKREQ_ERROR")
pinen=true; sauthrq=PUKRequested; sauthst=Error ;;
"SIMBLOCKED")
pinen=true; sauthrq=Error; sauthst=Error ;;
"SIMOPEN")
pinen=false; sauthrq=None; sauthst=Authenticated; retval=0 ;;
esac
setm="$sobj.AuthenticationRequest=${sauthrq}	$sobj.AuthenticationStatus=${sauthst}"
[ -n "$pinen" ] && setm="$setm	$sobj.PINEnable=${pinen}"
[ -n "$pinra" ] && setm="$setm	$sobj.PINRemainingAttempts=${pinra}"
[ -n "$pukra" ] && setm="$setm	$sobj.PUKRemainingAttempts=${pukra}"
cmclient SETEM "$setm"
eval $1='$sstat'
[ "$retval" = "1" ] && wwan_updatestatus "ERROR" "Check SIM status"
return $retval
}
wwan_validate_pinpuk()
{
local sobj="$1" sstat="$2" spin spuk
case "$sstat" in
"PIN"*)
cmclient -v spin GETV ${sobj}.PIN
if [ -z "$spin" ]; then
wwan_updatestatus "DOWN" "PIN required"
return 1
fi
wwanmodem_unlock_pin "$spin"
;;
"PUK"*)
cmclient -v spin GETV ${sobj}.PIN
cmclient -v spuk GETV ${sobj}.PUK
if [ -z "$spuk" -o -z "$spin" ]; then
wwan_updatestatus "DOWN" "PIN and PUK required"
return 1
fi
wwanmodem_unlock_puk "$spuk" "$spin"
;;
*)	### Uh?!?
wwan_updatestatus "ERROR" "unknown sim state"
return 1
;;
esac
return 0
}
wwan_trdata_align()
{
[ "$1" != "mobj" ] && local mobj
[ "$1" != "sobj" ] && local sobj
[ "$1" != "tval" ] && local tval
[ "$1" != "oper" ] && local oper
[ "$1" != "mnc" ] && local mnc
[ "$1" != "mcc" ] && local mcc
[ "$1" != "setm" ] && local setm
[ "$1" != "model" ] && local model
mobj="$2"
sobj="$3"
setm=""
wwanmodem_get_mcc "mcc" || mcc=""
wwanmodem_get_mnc "mnc" || mnc=""
setm="$mobj.Modem.MobileCountryCode=$mcc	$mobj.Modem.MobileNetworkCode=$mnc"
cmclient -v oper GETO Device.X_ADB_MobileModem.Operator.[PLMN=${mcc}${mnc}]
if [ -z "$oper" ]; then
if [ -z "$mnc" -o -z "$mcc" ]; then
wwan_updatestatus "ERROR" "Unable to retrieve PLMN"
else
wwan_updatestatus "ERROR" "Missing operator for PLMN ${mcc}${mnc}"
cmclient SETEM "$setm"
fi
return 1
fi
setm="$setm	$mobj.ActiveOperator=$oper"
setm="$setm	$sobj.SIMOperator=$oper"
cmclient -v model GETV "$mobj.Modem.ActiveModel"
if [ -n "$model" ]; then
cmclient -v tval GETV "$model.Manufacturer"
setm="$setm	$mobj.Modem.Manufacturer=$tval"
tval=""; wwanmodem_get_modemModel "tval"
if [ ${#tval} -gt 0 ]; then
setm="$setm	$mobj.Modem.Model=$tval"
else
cmclient -v tval GETV "$model.Name"
setm="$setm	$mobj.Modem.Model=$tval"
fi
fi
setm="$setm	$mobj.Modem.DataDevice=wwan0"
tval="" ; wwanmodem_get_iccid "tval" && setm="$setm	$sobj.ICCID=$tval"
tval="" ; wwanmodem_get_msin "tval" && setm="$setm	$sobj.MSIN=$tval"
tval="" ; wwanmodem_get_imei "tval" && setm="$setm	$sobj.IMEI=$tval	$mobj.Modem.IMEI=$tval"
tval="" ; wwanmodem_get_revision "tval" && setm="$setm	$mobj.Modem.Revision=$tval"
cmclient SETEM "$setm"
eval $1='$oper'
return 0
}
wwan_trdata_clear()
{
local mmodem sobj setem
help_wwan_get_usbmodem "mmodem"
setem="${mmodem}.Name=	\
${mmodem}.ActiveSIMCard=	\
${mmodem}.ActiveOperator=	\
${mmodem}.Modem.ActiveModel=	\
${mmodem}.Modem.Manufacturer=	\
${mmodem}.Modem.Model=	\
${mmodem}.Modem.Revision=	\
${mmodem}.Modem.IMEI=	\
${mmodem}.Modem.DataDevice=	\
${mmodem}.Modem.GSMNetworkRegistered=false	\
${mmodem}.Modem.GPRSNetworkAttached=false	\
${mmodem}.Modem.PDPContextActivated=false	\
${mmodem}.Modem.PDH=0	\
${mmodem}.Modem.CID=0	\
${mmodem}.Modem.MobileCountryCode=	\
${mmodem}.Modem.MobileNetworkCode="
cmclient -v sobj GETV ${mmodem}.ActiveSIMCard
[ -n "$sobj" ] && setem=${setem}"	\
${sobj}.AuthenticationRequest=None	\
${sobj}.AuthenticationStatus=None"
cmclient SETEM "$setem"
}
wwan_network_connect()
{
local oper="$1" aobj aurl user pass auth dial
cmclient -v aobj GETV $oper.DefaultAPN
: ${aobj:=$oper.APN.1}
cmclient -v aurl GETV $aobj.URL
cmclient -v user GETV $aobj.Username
cmclient -v pass GETV $aobj.Password
cmclient -v auth GETV $aobj.AuthenticationProtocol
cmclient -v dial GETV $aobj.Dial
wwanmodem_network_connect "$aurl" "$user" "$pass" "$auth" "$dial" && return 0
wwan_updatestatus "ERROR" "Unable to activate data bearer/pdp context ($aurl,$user,$pass,$auth,$dial)"
return 1
}
wwan_updatestatus()
{
local p_mode="$1" p_msg=${2} mmodem stat nattach="false"
help_wwan_get_usbmodem mmodem
case "$p_mode" in
"ERROR")
p_msg=${p_msg:-"Unable to configure the device"}
stat="Error"
wwanmodem_reset
;;
"DOWN")
p_msg=${p_msg:-"Modem down"}
stat="Down"
;;
"UP")
p_msg=${p_msg:-"Modem up"}
stat="Up"
nattach="true"
;;
"REMOVED")
p_msg=${p_msg:-"Modem removed"}
stat="LowerLayerDown"
cmclient SETE USB.Interface.1.Status "NotPresent"
;;
*)
p_msg="unknown status $p_mode, msg is \"$p_msg\""
stat="Down"
wwanmodem_reset
;;
esac
echo "MobileModem $p_mode: $p_msg" > /dev/console
cmclient -u Modem SET $mmodem.Status "$stat"
cmclient SETEM "$mmodem.Modem.GSMNetworkRegistered=$nattach	\
$mmodem.Modem.GPRSNetworkAttached=$nattach	\
$mmodem.Modem.PDPContextActivated=$nattach"
help_serialize_unlock "$MODEM_LOCK"
}
wwan_start()
{
local mmodem mmenable oobj sobj sstat proto restart="$1"
help_serialize_run_once "$MODEM_LOCK" notrap
help_wwan_get_usbmodem "mmodem"
if ! help_wwan_checkproto "proto"; then
[ -x /etc/ah/wwan_$proto.sh ] && /etc/ah/wwan_$proto.sh start_$proto $restart \
|| wwan_updatestatus "ERROR" "Protocol $proto not managed"
return
fi
if [ -n "$restart" ]; then
cmclient -v oobj GETV $mobj.ActiveOperator
else
help_wwan_enable_swacc "wwan0"
wwan_initialize || return
wwan_get_simobj "sobj"
cmclient SETE $mmodem.ActiveSIMCard "$sobj"
wwan_simstat_align "sstat" "$sobj" || return
if [ "${sstat#*_}" = "WAIT" ]; then
wwan_validate_pinpuk "$sobj" "$sstat" || return
wwan_simstat_align "sstat" "$sobj" || return
if [ "${sstat#*_}" != "DONE" ]; then
wwan_updatestatus "ERROR" "Unable to unlock the SIM"
cmclient SETE $sobj.AuthenticationStatus Error
return
fi
fi
wwan_trdata_align "oobj" "$mmodem" "$sobj" || return
fi
wwan_network_connect "$oobj" || return
wwan_updatestatus "UP" "Modem configured"
}
wwan_remove()
{
local proto=$1
[ -z "$proto" ] && help_wwan_get_protocol "proto"
case "$proto" in
qmi)	break ;;
mbim)	break ;;
ecm)	break ;;
*)	return ;;
esac
wwan_updatestatus "REMOVED"
wwan_trdata_clear
}
wwan_stop()
{
local proto
help_wwan_checkproto "proto" || return 0
if ! wwanmodem_disconnect; then
wwan_updatestatus "ERROR" "Modem won't stop."
wwan_trdata_clear
return 1
fi
wwan_updatestatus "DOWN"
return 0
}
wwan_enablepin()
{
local mmodem="$1" sobj="$2" pinen="$3" pin="$4" proto void
help_wwan_checkproto "proto" || return 0
[ -z "$pin" ] && return 1
wwanmodem_enablepin "$pinen" "$pin" || return 1
wwan_simstat_align "void" "$sobj"
return 0
}
wwan_changepin()
{
local modem="$1" sobj="$2" pin="$3" pinnew="$4" proto void
help_wwan_checkproto "proto" || return 0
[ -z "$pin" -o -z "$pinnew" ] && return 1
wwanmodem_changepin "$pin" "$pinnew" || return 1
wwan_simstat_align "void" "$sobj"
cmclient SETEM "${sobj}.PINChange=false	\
${sobj}.PIN=$pinnew	\
${sobj}.NewPIN="
return 0
}
[ $# -gt 0 ] && "$1"
return 0
