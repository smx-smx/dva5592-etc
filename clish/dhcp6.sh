#!/bin/sh
. /etc/clish/clish-commons.sh
OBJ=""
OBJ_ALIAS=""
show_interface() {
local iface
cmclient -v iface GETV "%($OBJ.Interface).Alias"
print_2_col_row "Interface" "$iface"
}
show_dhcp6_pool_client(){
local val i
local this="$1"
cmclient -v val GETV "$this.Alias"
echo
echo "$val:"
print_horizontal_line
for i in Active SourceAddress X_ADB_ClientDUID; do
show_from_cm "$this" "$i"
done
cmclient -v val GETO "$this.IPv6Address"
for i in $val; do
local a p v
cmclient -v a GETV "$i.IPAddress"
cmclient -v p GETV "$i.PreferredLifetime"
cmclient -v v GETV "$i.ValidLifetime"
print_2_col_row "IP address" "$a (Preferred: $p / Valid: $v)"
done
cmclient -v val GETO "$this.IPv6Prefix"
for i in $val; do
local a p v
cmclient -v a GETV "$i.Prefix"
cmclient -v p GETV "$i.PreferredLifetime"
cmclient -v v GETV "$i.ValidLifetime"
print_2_col_row "IP prefix" "$a (Preferred: $p / Valid: $v)"
done
cmclient -v val GETO "$this.Option"
for i in $val; do
local t v
cmclient -v t GETV "$i.Tag"
cmclient -v v GETV "$i.Value"
print_2_col_row "Option $t" "$v"
done
print_horizontal_line
}
show_dhcp6_pool_clients(){
local list
echo
cmclient -v list GETO "$OBJ.Client"
if [ -z "$list" ]; then
echo "Clients not found"
else
local i
echo "Clients:"
for i in $list; do
show_dhcp6_pool_client "$i"
done
fi
}
show_dhcp6_pool(){
local i p
local OBJ="$1"
local OBJ_ALIAS
cmclient -v OBJ_ALIAS GETV "$OBJ.Alias"
echo
echo "$OBJ_ALIAS:"
print_horizontal_line
for i in \
Enable Status Alias \
DUID DUIDExclude \
VendorClassID VendorClassIDExclude \
UserClassID UserClassIDExclude \
SourceAddress SourceAddressMask SourceAddressExclude \
X_ADB_EnableDNSPassthrough \
IAPDAddLength IANAEnable IAPDEnable; do
show_from_cm "$OBJ" "$i"
done
for p in \
IANAManualPrefixes IAPDManualPrefixes \
IANAPrefixes IAPDPrefixes; do
local vector=""
local list
cmclient -v list GETV "$OBJ.$p"
for i in $(list_print "$list"); do
cmclient -v i GETV "$i.Prefix"
[ -z "$vector" ] && vector="$i" || vector="$vector, $i"
done
show_split_text "$p" "$vector"
done
show_interface
print_horizontal_line
show_dhcp6_pool_clients
}
show_dhcp6_client_server(){
local this="$1"
local i
echo
echo "Server ${this##*.}:"
print_horizontal_line
for i in SourceAddress DUID InformationRefreshTime; do
show_from_cm "$this" "$i"
done
print_horizontal_line
}
show_dhcp6_client_servers(){
local list
echo
cmclient -v list GETO "$OBJ.Server"
if [ -z "$list" ]; then
echo "DHCPv6 servers not found"
else
local i
echo "DHCPv6 Servers:"
for i in $list; do
show_dhcp6_client_server "$i"
done
fi
}
show_dhcp6_client_received_options(){
local list
cmclient -v list GETO "$OBJ.ReceivedOption"
[ -z "$list" ] && return
local i
echo
echo "Received options:"
print_horizontal_line
for i in $list; do
local t v s
cmclient -v t GETV "$i.Tag"
cmclient -v v GETV "$i.Value"
cmclient -v s GETV "$i.Server"
print_2_col_row "Option $t" "$v (Server ${s##*.})"
done
print_horizontal_line
}
show_dhcp6_client(){
local i
echo
echo "$OBJ_ALIAS:"
print_horizontal_line
for i in \
Enable Status DUID \
RequestAddresses \
RequestPrefixes RapidCommit \
SuggestedT1 SuggestedT2 \
SupportedOptions RequestedOptions \
X_ADB_AutoMode; do
show_from_cm "$OBJ" "$i"
done
show_interface
print_horizontal_line
show_dhcp6_client_servers
show_dhcp6_client_received_options
}
show_dhcp6_option(){
local i tag
cmclient -v tag GETV "$OBJ.Tag"
echo
echo "Option $tag"
print_horizontal_line
for i in Enable X_ADB_Type Value; do
show_from_cm "$OBJ" "$i"
done
if [ "$1" != "sent" ]; then
cmclient -v tag GETV "$OBJ.PassthroughClient"
if [ -z "$tag" ]; then
print_2_col_row "Passthrough Client" "Disable"
else
local name
cmclient -v name GETV "$tag.Alias"
print_2_col_row "Passthrough Client" "$name"
fi
fi
print_horizontal_line
}
show_dhcp6_server_info() {
local i pools iface objAccess
echo
cmclient -v pools GETO "Device.DHCPv6.Server.Pool.[Interface=$1]"
for i in $pools; do
objAccess=1
cmclient -v iface GETV "${i}".Interface
[ -n "$iface" ] && get_obj_access objAccess "$iface"
if [ $objAccess -gt 0 ]; then
show_dhcp6_pool "${i}"
echo
fi
done
}
case "$1" in
show_ip_dhcp6_servers)
show_dhcp6_server_info "$2"
exit 0;
;;
Device.*)
OBJ="$1"
cmclient -v OBJ_ALIAS GETV "$OBJ.Alias"
;;
*)
OBJ="$(cli_to_tr $1)"
cmclient -v OBJ_ALIAS GETV "$OBJ.Alias"
;;
esac
case "$2" in
show_pool)
show_dhcp6_pool "$OBJ"
;;
show_client)
show_dhcp6_client 
;;
show_option)
show_dhcp6_option
;;
show_option_sent)
show_dhcp6_option sent
;;
*)
[ -n "$2" ] && setm="$OBJ.$2=$3"
;;
esac
[ -n "$setm" ] && exec /etc/clish/quick_cm.sh setm "${setm}"
