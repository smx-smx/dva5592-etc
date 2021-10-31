#!/bin/sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_serialize.sh
AH_NAME="LanSurvey"
readDhcpOpt() {
	local _mac=$1
	local _opt=$2
	local _ret=$3
	local _tmp=""
	cmclient -v _tmp GETV "DHCPv4.Server.+.Client.[Chaddr=$_mac].Option.[Tag=$_opt].Value"
	eval $_ret="$_tmp"
}
initScan() {
	cmclient DEL Device.X_ADB_LocalAreaNetworkSurvey.Device >/dev/null
	cmclient SET Device.Hosts.X_ADB_ScanHosts true >/dev/null
}
scanHost() {
	local hostList=""
	local hostObj=""
	cmclient -v hostList GETO Hosts.Host.[AddressSource!X_ADB_CPEName].[Active=true].[PhysAddress!""]
	if [ -n "$hostList" ]; then
		for hostObj in $hostList; do
			local _Hostname=""
			local _IPAddress=""
			local _MACAddress=""
			local _AddressSource=""
			local _InterfaceType=""
			local _Port=""
			local _ConnectionSpeed=""
			local _VSpecInformation=""
			local _ClassIdentifier=""
			local _ClientIdentifier=""
			local _VIdVendorClass=""
			local _VIdVendorSpecific=""
			local _WifiAnnex=""
			local _WifiPairingStatus=""
			cmclient -v _IPAddress GETV "$hostObj.IPAddress"
			cmclient -v _AddressSource GETV "$hostObj.AddressSource"
			cmclient -v _MACAddress GETV "$hostObj.PhysAddress"
			case "$_AddressSource" in
			"DHCP")
				local _opt
				_opt=12
				readDhcpOpt "$_MACAddress" "$_opt" _Hostname
				_opt=43
				readDhcpOpt "$_MACAddress" "$_opt" _VSpecInformation
				_opt=60
				readDhcpOpt "$_MACAddress" "$_opt" _ClassIdentifier
				_opt=61
				readDhcpOpt "$_MACAddress" "$_opt" _ClientIdentifier
				_opt=124
				readDhcpOpt "$_MACAddress" "$_opt" _VIdVendorClass
				_opt=125
				readDhcpOpt "$_MACAddress" "$_opt" _VIdVendorSpecific
				local _static
				cmclient -v _static GETO "Device.DHCPv4.Server.+.StaticAddress.[Chaddr=$_MACAddress].[Enable=true]"
				[ -n "$_static" ] && _AddressSource="Preassigned"
				;;
			"Static") ;;
			*) _AddressSource="" ;;
			esac
			local _int
			cmclient -v _int GETV "$hostObj.[Layer1Interface!].Layer1Interface"
			case "$_int" in
			"Device.Ethernet.Interface."*)
				cmclient -v _ConnectionSpeed GETV "$_int.X_ADB_MediaType"
				case "$_ConnectionSpeed" in
				"1000"*) _ConnectionSpeed="1000" ;;
				"100"*) _ConnectionSpeed="100" ;;
				"10"*) _ConnectionSpeed="10" ;;
				*) _ConnectionSpeed="" ;;
				esac
				_InterfaceType="Ethernet"
				_Port=${_int##*.}
				;;
			"Device.WiFi.SSID."*)
				_InterfaceType="Wifi"
				_Port=""
				cmclient -v _int GETV "$hostObj.AssociatedDevice"
				if [ -n "$_int" ]; then
					cmclient -v _ConnectionSpeed GETV "$_int.LastDataDownlinkRate"
					[ -n "$_ConnectionSpeed" ] && _ConnectionSpeed=$(($_ConnectionSpeed / 1000))
					cmclient -v _WifiAnnex GETV "$_int.X_ADB_Protocol"
					cmclient -v _WifiPairingStatus GETV "$_int.AuthenticationState"
					case "$_WifiPairingStatus" in
					"true") _WifiPairingStatus="Successful" ;;
					"false") _WifiPairingStatus="AuthenticationFailed" ;;
					*) _WifiPairingStatus="" ;;
					esac
				fi
				;;
			*)
				continue
				;;
			esac
			local _Device=""
			cmclient -v _Device ADD X_ADB_LocalAreaNetworkSurvey.Device
			_Device="X_ADB_LocalAreaNetworkSurvey.Device.$_Device"
			local _tmp="$_Device.NetworkInfo.MACAddress=$_MACAddress"
			[ -n "$_IPAddress" ] && _tmp="$_tmp	$_Device.NetworkInfo.IPAddress=$_IPAddress"
			[ -n "$_AddressSource" ] && _tmp="$_tmp	$_Device.NetworkInfo.AddressSource=$_AddressSource"
			[ -n "$_InterfaceType" ] && _tmp="$_tmp	$_Device.InterfaceInfo.InterfaceType=$_InterfaceType"
			[ -n "$_ConnectionSpeed" ] && _tmp="$_tmp	$_Device.InterfaceInfo.ConnectionSpeed=$_ConnectionSpeed"
			[ -n "$_Port" ] && _tmp="$_tmp	$_Device.InterfaceInfo.EthPort=$_Port"
			[ -n "$_WifiAnnex" ] && _tmp="$_tmp	$_Device.InterfaceInfo.WifiAnnex=$_WifiAnnex"
			[ -n "$_WifiPairingStatus" ] && _tmp="$_tmp	$_Device.InterfaceInfo.WifiPairingStatus=$_WifiPairingStatus"
			[ -n "$_Hostname" ] && _tmp="$_tmp	$_Device.DeviceInfo.Opt12_Hostname=$_Hostname"
			[ -n "$_VSpecInformation" ] && _tmp="$_tmp	$_Device.DeviceInfo.Opt43_VSpecInformation=$_VSpecInformation"
			[ -n "$_ClassIdentifier" ] && _tmp="$_tmp	$_Device.DeviceInfo.Opt60_ClassIdentifier=$_ClassIdentifier"
			[ -n "$_ClientIdentifier" ] && _tmp="$_tmp	$_Device.DeviceInfo.Opt61_ClientIdentifier=$_ClientIdentifier"
			[ -n "$_VIdVendorClass" ] && _tmp="$_tmp	$_Device.DeviceInfo.Opt124_VIdVendorClass=$_VIdVendorClass"
			[ -n "$_VIdVendorSpecific" ] && _tmp="$_tmp	$_Device.DeviceInfo.Opt125_VIdVendorSpecific=$_VIdVendorSpecific"
			cmclient SETM "$_tmp"
			local _SMB_Hostname=""
			local _SMB_OperatingSystem=""
			local _SMB_Domain=""
			local _SMB_ShareName=""
			local _smbTmp=$(smbtiny $_IPAddress)
			if [ -n "$_smbTmp" ]; then
				local _oldIFS="$IFS"
				local _row=""
				local _shareId=""
				IFS=";"
				for _row in $_smbTmp; do
					case "$_row" in
					"Server"*) _SMB_Hostname=${_row#*: } ;;
					"OperatingSystem"*) _SMB_OperatingSystem=${_row#*: } ;;
					"Domain"*) _SMB_Domain=${_row#*: } ;;
					"Disk"*)
						_SMB_ShareName=${_row#*: }
						cmclient -v _shareId ADD "$_Device.ExportedServices.Shares"
						_shareId="$_Device.ExportedServices.Shares.$_shareId"
						cmclient SETM "$_shareId.ShareType=SMB	$_shareId.ShareName=$_SMB_ShareName"
						;;
					esac
				done
				IFS="$_oldIFS"
				_tmp="$_Device.DeviceInfo.SMB_Hostname=$_SMB_Hostname"
				_tmp="$_tmp	$_Device.DeviceInfo.SMB_OperatingSystem=$_SMB_OperatingSystem"
				_tmp="$_tmp	$_Device.DeviceInfo.SMB_Domain=$_SMB_Domain"
				cmclient SETM "$_tmp" >/dev/null
			fi
			local _nfsTmp=$(showmount --no-headers -g -e $_IPAddress)
			if [ -n "$_nfsTmp" ]; then
				local _row=""
				local _shareId=""
				for _row in $_nfsTmp; do
					cmclient -v _shareId ADD "$_Device.ExportedServices.Shares"
					_shareId="$_Device.ExportedServices.Shares.$_shareId"
					cmclient SETM "$_shareId.ShareType=NFS	$_shareId.ShareName=$_row"
				done
			fi
		done
	fi
}
scanLocalInfo() {
	local _DefaultGateway=""
	local _DHCPRange=""
	local _NAPTRange=""
	local _tmp=""
	cmclient -v _DefaultGateway GETV "Device.DHCPv4.Server.Pool.1.IPRouters"
	cmclient -v _tmp GETV "Device.DHCPv4.Server.Pool.1.MinAddress"
	_DHCPRange="$_tmp"
	cmclient -v _tmp GETV "Device.DHCPv4.Server.Pool.1.MaxAddress"
	_DHCPRange="$_DHCPRange - $_tmp"
	cmclient -v _tmp GETV "NAT.InterfaceSetting.*.[Alias=Data NAT].X_TELECOMITALIA_IT_NATStartIPAddress"
	_NAPTRange="$_tmp"
	cmclient -v _tmp GETV "NAT.InterfaceSetting.*.[Alias=Data NAT].X_TELECOMITALIA_IT_NATEndIPAddress"
	_NAPTRange="$_NAPTRange - $_tmp"
	_tmp="X_ADB_LocalAreaNetworkSurvey.LocalAreaNetwork.DefaultGateway=$_DefaultGateway"
	_tmp="$_tmp	X_ADB_LocalAreaNetworkSurvey.LocalAreaNetwork.DHCPRange=$_DHCPRange"
	_tmp="$_tmp	X_ADB_LocalAreaNetworkSurvey.LocalAreaNetwork.NAPTRange=$_NAPTRange"
	cmclient SETM "$_tmp" >/dev/null
}
scanUPnP() {
	local _oldIFS="$IFS"
	local _upnp=$(upnpc -Z)
	if [ -n "$_upnp" ]; then
		local _row=""
		local _obj=""
		local _ip=""
		local _tmp=""
		local _DeviceType=""
		local _FriendlyName=""
		local _Manufacturer=""
		local _ModelDescription=""
		local _ModelName=""
		local _ModelNumber=""
		local _UPnPServer=""
		local _UPnPServiceType=""
		IFS=";"
		for _row in $_upnp; do
			case "$_row" in
			"begin"*)
				_ip=${_row#*: }
				cmclient -v _obj GETO "Device.IP.Interface.IPv4Address.[IPAddress=$_ip]"
				[ -n "$_obj" ] && continue
				cmclient -v _obj GETO "Device.X_ADB_LocalAreaNetworkSurvey.Device.+.[IPAddress=$_ip]"
				if [ -n "$_obj" ]; then
					_obj=${_obj%.NetworkInfo}
				else
					cmclient -v _obj ADD "Device.X_ADB_LocalAreaNetworkSurvey.Device"
					_obj="Device.X_ADB_LocalAreaNetworkSurvey.Device.$_obj"
					cmclient SET "$_obj.NetworkInfo.IPAddress $_ip" >/dev/null
				fi
				cmclient -v _tmp ADD "$_obj.ExportedServices.UPnPDevices"
				_obj="$_obj.ExportedServices.UPnPDevices.$_tmp"
				;;
			"end"*)
				_tmp="$_obj.DeviceType=$_DeviceType"
				[ -n $_FriendlyName ] && _tmp="$_tmp	$_obj.FriendlyName=$_FriendlyName"
				[ -n $_Manufacturer ] && _tmp="$_tmp	$_obj.Manufacturer=$_Manufacturer"
				[ -n $_ModelDescription ] && _tmp="$_tmp	$_obj.ModelDescription=$_ModelDescription"
				[ -n $_ModelName ] && _tmp="$_tmp	$_obj.ModelName=$_ModelName"
				[ -n $_ModelNumber ] && _tmp="$_tmp	$_obj.ModelNumber=$_ModelNumber"
				[ -n $_UPnPServer ] && _tmp="$_tmp	$_obj.UPnPServer=$_UPnPServer"
				cmclient SETM "$_tmp" >/dev/null
				;;
			"service"*)
				_UPnPServiceType=${_row#*: }
				cmclient -v _tmp ADD "$_obj.UPnPServices"
				cmclient SET "$_obj.UPnPServices.$_tmp.UPnPServiceType $_UPnPServiceType" >/dev/null
				;;
			"deviceType"*) _DeviceType=${_row#*: } ;;
			"friendlyName"*) _FriendlyName=${_row#*: } ;;
			"manufacturer"*) _Manufacturer=${_row#*: } ;;
			"modelDescription"*) _ModelDescription=${_row#*: } ;;
			"modelName"*) _ModelName=${_row#*: } ;;
			"modelNumber"*) _ModelNumber=${_row#*: } ;;
			"server"*) _UPnPServer=${_row#*: } ;;
			esac
		done
		IFS="$_oldIFS"
	fi
}
startScan() {
	local hosts_ent=""
	help_serialize >/dev/null
	initScan
	scanLocalInfo
	scanHost
	cmclient -v hosts_ent GETO "X_ADB_LocalAreaNetworkSurvey.Device"
	[ ${#hosts_ent} -eq 0 ] && exit 0
	scanUPnP
	[ -e /etc/ah/DNSSDSurvey.sh ] && . /etc/ah/DNSSDSurvey.sh
}
case "$op" in
s)
	startScan
	;;
esac
exit 0
