#!/bin/sh
AH_NAME="TR098_Interface"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
service_get()
{
local obj98="$1"
local param98="$2"
local value98=""
local index=""
local manufacturer=""
case "$obj98" in
InternetGatewayDevice.Services.X_DLINK_DynamicDNS.Client*)
index="${obj98##*.}"
obj181="Device.Services.X_ADB_DynamicDNS.Client.$index"
manufacturer="X_DLINK_DynamicDNS"
;;
InternetGatewayDevice.Services.X_ADB_DynamicDNS.Client*)
obj181="Device.${obj98#*.}"
manufacturer="X_ADB_DynamicDNS"
;;
*)
obj181="Device.${obj98#*.}"
;;
esac
cmclient -v value181 GETV "$obj181.$param98"
if [ -n "$value181" ]; then
case "$param98" in
"DownstreamInterfaces" | "UpstreamInterfaces")
set -f
IFS=","
set -- $value181
unset IFS
set +f
for arg; do
case "$arg" in
*"Radio"*)
for if098 in `cmclient GETO "InternetGatewayDevice.LANDevice.WLANConfiguration.[X_ADB_TR181Name=$arg]"`
do
[ -n "$if098" ] && break;
done
;;
*)
if098=`cmclient GETV "$arg.X_ADB_TR098Reference"`
;;
esac
if [ -n "$if098" ]; then
if [ -z "$value98" ]; then
value98="$if098" 
else
value98="$value98,$if098"
fi
fi
done
;;
"Provider")
index="${value181##*.}"
value98="InternetGatewayDevice.Services.$manufacturer.$param98.$index"
;;
esac
fi
echo "$value98"
}
service_set_param()
{
local obj98="$1"
local param98="$2"
local _val="$3"
case "$obj98" in
InternetGatewayDevice.UploadDiagnostics | InternetGatewayDevice.DownloadDiagnostics)
obj181="Device.IP.Diagnostics.${obj98#*.}"
;;
InternetGatewayDevice.IPPingDiagnostics)
obj181="Device.IP.Diagnostics.IPPing"
;;
InternetGatewayDevice.Services.X_DLINK_DynamicDNS.Client*)
index="${obj98##*.}"
obj181="Device.Services.X_ADB_DynamicDNS.Client.$index"
index="${_val##*.}"
value181="Device.Services.X_ADB_DynamicDNS.$param98.$index"
;;
InternetGatewayDevice.Services.X_ADB_DynamicDNS.Client*)
obj181="Device.${obj98#*.}"
value181="Device.${_val#*.}"
;;
*)
obj181="Device.${obj98#*.}"
;;
esac
case $param98 in
"DownstreamInterfaces" | "UpstreamInterfaces")
ifaces_list=""
set -f
IFS=","
set -- $_val
unset IFS
set +f
for arg; do
case "$arg" in
*"WLANConfiguration"*)
ssid_obj=`cmclient GETV "$arg.X_ADB_TR181_SSID"`
if [ -n "$ssid_obj" ]; then
if [ -z "$ifaces_list" ]; then
ifaces_list="$ssid_obj"
else
ifaces_list="$ifaces_list,$ssid_obj"
fi	
fi
;;
*)
if181=`cmclient GETV "$arg.X_ADB_TR181Name"`
if [ -n "$if181" ]; then
if [ -z "$ifaces_list" ]; then
ifaces_list="$if181"
else
ifaces_list="$ifaces_list,$if181"
fi	
fi
;;
esac
done
if [ -z "$setm_params" ]; then
setm_params="$obj181.$param98=$ifaces_list"
else
setm_params="$setm_params	$obj181.$param98=$ifaces_list"
fi
;;
*"Interface"* )
[ "$param98" = X_DLINK_OutboundInterface ] && param98=X_ADB_OutboundInterface
if [ -z "$_val" ]; then
setm_params="${setm_params:+$setm_params	}$obj181.$param98="
else
cmclient -v if181 GETO "Device.IP.Interface.[X_ADB_TR098Reference=$_val]"
if [ -n "$if181" ]; then
setm_params="${setm_params:+$setm_params	}$obj181.$param98=$if181"
fi
fi
;;
"Provider")
setm_params="${setm_params:+$setm_params	}$obj181.Provider=$value181"
;;
esac
}
service_config()
{
setm_params=""
for i in Interface Interfaces X_ADB_InboundInterface InboundInterface OutboundInterface UpstreamInterfaces DownstreamInterfaces \
X_ADB_OutboundInterface X_DLINK_OutboundInterface Provider
do
if eval [ \${set${i}:=0} -eq 1 ]; then
eval service_set_param "$obj" "$i" \"\$new${i}\"
fi
done
if [ -n "$setm_params" ]; then
cmclient -u "tr098" SETM "$setm_params" > /dev/null
fi
}
case "$op" in
"s")
service_config
;;
"g")
for arg # Arg list as separate words
do 
service_get "$obj" "$arg"
done
;;
esac
exit 0
