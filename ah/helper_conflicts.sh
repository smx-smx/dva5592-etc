#!/bin/sh
help_check_conflicts() {
local remote=$1 intf=$2 port= leaf= intfleaf= tmp= leaves= o
shift 2
for port; do
[ "${port:-0}" = "0" ] && continue
if [ "$remote" = "1" ]; then
leaves="${leaves:+$leaves
}X_ADB_SSHServer.RemoteAccess.[Enable=true].[Port=$port]	Interfaces
X_ADB_TelnetServer.RemoteAccess.[Enable=true].[Port=$port]	Interfaces
UserInterface.RemoteAccess.[Enable=true].[X_ADB_ProtocolsEnabled,HTTP].[Port=$port]	X_ADB_Interface
UserInterface.RemoteAccess.[Enable=true].[X_ADB_ProtocolsEnabled,HTTP].[X_ADB_SecondaryPort=$port]	X_ADB_Interface
UserInterface.RemoteAccess.[Enable=true].[X_ADB_ProtocolsEnabled,HTTPS].[HTTPSPort=$port]	X_ADB_Interface
UserInterface.RemoteAccess.[Enable=true].[X_ADB_ProtocolsEnabled,HTTPS].[X_ADB_SecondaryHTTPSPort=$port]	X_ADB_Interface
Services.StorageService.[Enable=true].X_ADB_FTPServerRemote.[Enable=true].[PortNumber=$port]	X_ADB_Interfaces
ManagementServer.[EnableCWMP=true].[X_ADB_ConnectionRequestPort=$port].[X_ADB_ConnectionRequestInterface!]	X_ADB_ConnectionRequestInterface"
else
leaves="${leaves:+$leaves
}X_ADB_SSHServer.LocalAccess.[Enable=true].[Port=$port]	Interfaces
X_ADB_TelnetServer.LocalAccess.[Enable=true].[Port=$port]	Interfaces
UserInterface.X_ADB_LocalAccess.[Enable=true].[ProtocolsEnabled,HTTP].[Port=$port]	Interface
UserInterface.X_ADB_LocalAccess.[Enable=true].[ProtocolsEnabled,HTTP].[SecondaryPort=$port]	Interface
UserInterface.X_ADB_LocalAccess.[Enable=true].[ProtocolsEnabled,HTTPS].[HTTPSPort=$port]	Interface
UserInterface.X_ADB_LocalAccess.[Enable=true].[ProtocolsEnabled,HTTPS].[SecondaryHTTPSPort=$port]	Interface
Services.StorageService.[Enable=true].FTPServer.[Enable=true].[PortNumber=$port]	X_ADB_Interfaces
Services.X_ADB_PrinterService.[Enable=true].Servers.IPP.[Enable=true].[Port=$port]	Interfaces
Services.X_ADB_PrinterService.[Enable=true].Servers.RAW.[Enable=true].[PortBase=$port]	Interfaces"
fi
done
[ -z "$leaves" ] && return 0
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=","
set -- $intf
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
while IFS="	" read -r leaf intfleaf; do
cmclient -v o GETO "Device.$leaf"
case "$o" in
"$obj"|"$obj".*)
;;
*)
if [ -z "$intf" -o -z "$intfleaf" ]; then
cmclient -v tmp GETO "Device.$leaf"
[ -n "$tmp" ] && return 1
else
cmclient -v tmp GETO "Device.$leaf.[$intfleaf=]"
[ -n "$tmp" ] && return 1
for tmp; do
cmclient -v tmp GETO "Device.$leaf.[$intfleaf,$tmp]"
[ -n "$tmp" ] && return 1
done
fi
;;
esac
done <<-EOF
$leaves
EOF
:
}
help_reconfigure_nat_conflicts() {
local intf p ai i
cmclient -v p GETO "Device.NAT.PortMapping.[Enable=true].[X_ADB_Creator!UPnP]"
for p in $p; do
[ "$p" = "$obj" ] && continue
cmclient -v ai GETV $p.AllInterfaces
cmclient -v i GETV $p.Interface
if [ "$ai" = "true" -o ${#1} -eq 0 ]; then
cmclient -u "$AH_NAME" SET "$p.Enable" true
continue
fi
for intf; do
if [ "$i" = "$intf" ]; then
cmclient -u "$AH_NAME" SET "$p.Enable" true
break
fi
done
done
}
