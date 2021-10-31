#!/bin/sh
AH_NAME="TR098_Diagnostics"
[ "$user" != "CWMP" ] && exit 0
[ "$setDiagnosticsState" = "1" -a \
"$newDiagnosticsState" != "Requested" -a \
"$newDiagnosticsState" != "None" ] && exit 1
service_set_param()
{
local obj98="$1" param98="$2" _val="$3" val181="" obj181=""
case "$obj98" in
"InternetGatewayDevice.IPPingDiagnostics")
obj181="Device.IP.Diagnostics.IPPing"
;;
"InternetGatewayDevice.DownloadDiagnostics")
obj181="Device.IP.Diagnostics.DownloadDiagnostics"
;;
"InternetGatewayDevice.UploadDiagnostics")
obj181="Device.IP.Diagnostics.UploadDiagnostics"
;;
"InternetGatewayDevice.TraceRouteDiagnostics")
obj181="Device.IP.Diagnostics.TraceRoute"
;;
*)
return
;;
esac
case "$param98" in
"Interface")
[ ${#_val} -ne 0 ] && cmclient -v val181 GETO "Device.IP.Interface.[X_ADB_TR098Reference=$_val]"
;;
*)
val181="$_val"
;;
esac
setm="${setm:+$setm	}$obj181.$param98=$val181"
}
service_config()
{
setm=""
for i in DiagnosticsState Interface \
Host NumberOfRepetitions Timeout DataBlockSize \
DSCP EthernetPriority \
DownloadURL UploadURL TestFileLength \
NumberOfTries MaxHopCount
do
if eval [ \${set${i}:=0} -eq 1 ]; then
eval service_set_param "$obj" "$i" \"\$new${i}\"
fi
done
if [ -n "$setm" ]; then
cmclient -u "tr098" SETM "$setm"
fi
}
case "$op" in
"s")
service_config
;;
esac
exit 0
