#!/bin/sh
. /etc/clish/clish-commons.sh
OBJ=""
show_dhcp_pool_obj(){
local that
local wins=""
local lease=""
local this="$1"
DEFAULT_FIRST_COL_WIDTH=40
echo
cmclient -v alias_name GETV $this.Alias
echo "$alias_name:"
print_horizontal_line
cmclient -v wins  GETV "$this.Option.*.[Tag=44].Value"
cmclient -v lease GETV "$this.LeaseTime"
show_from_cm_interface "$this.Interface"
print_2_col_row "WINS Servers" "$wins"
for that in \
Enable Alias MinAddress MaxAddress SubnetMask \
DNSServers DomainName IPRouters Order VendorClassID \
VendorClassIDExclude VendorClassIDMode ClientID \
ClientIDExclude UserClassID UserClassIDExclude \
Chaddr ChaddrMask ChaddrExclude \
ReservedAddresses X_ADB_AddressProbe X_ADB_AddressProbeDelay; do
show_from_cm "$this" "$that"
done;
if [ "$lease" = "-1" ]; then
print_2_col_row "LeaseTime" "infinite"
else
print_2_col_row "LeaseTime" "$lease"
fi
for that in StaticAddress Option Client; do
show_from_cm "$this" "${that}NumberOfEntries"
done
print_horizontal_line
}
dhcp_relay_show() {
local this="$1"
local i val objAccess=1
cmclient -v val GETV "$this.Interface"
[ -n "$val" ] && get_obj_access objAccess "$val"
[ $objAccess -lt 1 ] && return
echo
cmclient -v val GETV "$this.Alias"
echo "$val:"
print_horizontal_line
for i in \
Enable Status Alias Chaddr \
ChaddrExclude ChaddrMask ClientID \
ClientIDExclude DHCPServerIPAddress \
LocallyServed Order UserClassID \
UserClassIDExclude VendorClassID \
VendorClassIDExclude VendorClassIDMode; do
show_from_cm "$this" "$i"
done
show_from_cm_interface "$this.Interface" "Interface in"
cmclient -v val GETV "$this.X_ADB_UpstreamInterface"
if [ -n "$val" ]; then
cmclient -v alias_name GETV "${val}.Alias"
print_2_col_row "Interface out" "$alias_name"
else
print_2_col_row "Interface out" "all"
fi
print_horizontal_line
}
show_dhcp_server_info() {
local i pools iface objAccess
local filter="${1:+.[Interface=$1]}"
echo
cmclient -v pools GETO "Device.DHCPv4.Server.Pool${filter}"
for i in $pools; do
objAccess=1
cmclient -v iface GETV "${i}".Interface
[ -n "$iface" ] && get_obj_access objAccess "$iface"
if [ $objAccess -gt 0 ]; then
show_dhcp_pool_obj "${i}"
echo
fi
done
}
dhcp_static_show() {
local Enable Alias Chaddr Yiaddr i
for i in Enable Alias Chaddr Yiaddr; do
cmclient -v $i GETV "${OBJ}.$i"
done
echo
echo "Current configuration:"
print_horizontal_line
print_2_col_row "Enable" "$Enable"
print_2_col_row "Alias" "$Alias"
print_2_col_row "MAC address" "$Chaddr"
print_2_col_row "IP address" "$Yiaddr"
print_horizontal_line
}
dhcp_option_show(){
local i
echo
echo "Current configuration:"
print_horizontal_line
for i in Enable Alias Tag Value X_ADB_OnRequest X_ADB_Type; do
show_from_cm "$OBJ" "$i"
done
print_horizontal_line
}
dhcp_option_show_sent() {
local i
echo
echo "Current configuration:"
print_horizontal_line
for i in Enable Alias Tag Value X_ADB_Type; do
show_from_cm "$OBJ" "$i"
done
print_horizontal_line
}
dhcp_option_show_req() {
local val i
echo
echo "Current configuration:"
print_horizontal_line
for i in Enable Order Alias Tag Value X_ADB_PassthroughEnable; do
show_from_cm "$OBJ" "$i"
done
show_from_cm "%($OBJ.X_ADB_PassthroughDHCPServerPool)" Alias
print_horizontal_line
}
dhcp_client_option_show(){
local obj="${1}"
local type="${2}"
local printf_args_sent="%-7s | %-5s | %-25s | %s\n"
local printf_args_req="%-7s | %-5s | %s\n"
local this list
cmclient -v list GETO "${obj}"
[ -z "${list}" ] && return
echo
echo "${2} options:"
print_horizontal_line 79
if [ "${type}" = "Sent" ]; then
printf "${printf_args_sent}" "Enable" "Tag" "Value" "Name"
print_horizontal_line 79
for this in $list; do
local t e a v
cmclient -v t GETV "${this}.Tag"
cmclient -v a GETV "${this}.Alias"
cmclient -v v GETV "${this}.Value"
cmclient -v e GETV "${this}.Enable"
printf "${printf_args_sent}" "${e}" "${t}" "${v}" "${a}"
done
else
printf "${printf_args_req}" "Enable" "Tag" "Name"
print_horizontal_line 79
for this in $list; do
local t e a
cmclient -v t GETV "${this}.Tag"
cmclient -v a GETV "${this}.Alias"
cmclient -v e GETV "${this}.Enable"
printf "${printf_args_req}" "${e}" "${t}" "${a}"
done
fi
print_horizontal_line 79
echo
}
dhcp_client_options_show(){
local client="${1}"
local this
for this in Sent Req; do
dhcp_client_option_show "${client}.${this}Option" "${this}"
done
}
get_expire_time(){
local ltime="${1}" htime="${2}" t="${3}" ret=0 stop=1000 d= t1= t2=
if [ ${#t} -eq 0 -o ${#ltime} -eq 0 -o ${#htime} -eq 0 -o $ltime -gt $htime -o \
$t -gt $htime ]; then
ret=0
elif [ $t -le $ltime ]; then
ret=$((ltime - t))
else
d=$((htime - ltime))
t1=$ltime
while [ $stop -gt 0 ]; do
stop=$((stop-1))
d=$((d/2))
if [ $d -le 60 ]; then
ret=$((t1 + 60 - t))
[ $ret -lt 0 ] && ret=0
break
fi
t2=$((t1 + d))
if [ $t -le $t2 ]; then
ret=$((t2 - t))
break
fi
t1=$t2
done
fi
echo $ret
}
dhcp_client_show() {
local this="$1" val= i= t0= t1= t2= t3= lease_val= renew_val= rebind_val= ip=
echo
print_horizontal_line
for i in \
Alias Enable Status DHCPServer \
DHCPStatus DNSServers IPAddress IPRouters \
LeaseTimeRemaining SubnetMask PassthroughEnable; do
show_from_cm "$this" "$i"
done
show_from_cm_interface "$this.Interface"
cmclient -v i   GETV "$this.Interface"
cmclient -v val GETV "%($i.LowerLayers).MACAddress"
[ -z "$val" ] && cmclient -v val GETV "$(get_low_level $i).MACAddress"
print_2_col_row "Interface MAC" "$val"
cmclient -v val GETV "$this.ReqOption.*.[Tag=15].Value"
[ -n "$val" ] && print_2_col_row "Domain Name" "$val"
cmclient -v lease_val GETV "$this.ReqOption.*.[Tag=51].Value"
cmclient -v ip        GETV "$this.IPAddress"
[ -s "/tmp/$ip" ] && read -r t0 < "/tmp/$ip"
if [ ${#lease_val} -ne 0 ] ; then
print_2_col_row "Lease Period  (sec)" "$lease_val"
if [ ${#t0} -ne 0 ] ; then
cmclient -v renew_val GETV "$this.ReqOption.*.[Tag=58].Value"
[ ${#renew_val} -eq 0 ] && renew_val=$((lease_val/2))
t1=$((t0 + renew_val))
cmclient -v rebind_val GETV "$this.ReqOption.*.[Tag=59].Value"
[ ${#rebind_val} -eq 0 ] && rebind_val=$((lease_val*7/8))
t2=$((t0 + rebind_val))
t3=$((t0 + lease_val))
t=$(date +%s)
t4=$((t3 - t))
[ $t4 -lt 0 ] && t4=0
print_2_col_row "     expires  (sec)"  "$t4"
val="$(get_expire_time $t1 $t2 $t)"
[ $val -gt $t4 ] && val=0
print_2_col_row "Renew Period  (sec)"  "$renew_val"
print_2_col_row "     expires  (sec)"  "$val"
val="$(get_expire_time $t2 $t3 $t)"
[ $val -gt $t4 ] && val=0
print_2_col_row "Rebind Period (sec)"  "$rebind_val"
print_2_col_row "     expires  (sec)"  "$val"
fi
else
print_2_col_row "Lease Period (sec)" "Not provided by DHCP Server"
fi
show_from_cm "%($this.PassthroughDHCPPool)" Alias
print_horizontal_line
echo
dhcp_client_options_show "${this}"
}
case "$1" in
show_ip_dhcp_servers)
show_dhcp_server_info "$2"
exit 0;
;;
null)
;;
*)
OBJ="$(cli_or_tr_alias_to_tr_obj $1)"
;;
esac
case "$2" in
dhcp_server_pool_show)
show_dhcp_pool_obj "$OBJ"
;;
dhcp_server_static_show)
dhcp_static_show
;;
dhcp_server_option_show)
dhcp_option_show
;;
dhcp_client_option_sent_show)
dhcp_option_show_sent
;;
dhcp_server_option_req_show)
dhcp_option_show_req
;;
dhcp_relay_show)
dhcp_relay_show "$OBJ"
;;
dhcp_client_show)
dhcp_client_show "$OBJ"
;;
dhcp_clients_show)
local list
cmclient_GETO_Access list "Device.DHCPv4.Client" 1
for this in $list; do
dhcp_client_show "${this}"
done
;;
router_show)
tmp_value="$(handle_list_actions $OBJ.IPRouters show)"
[ -z "$tmp_value" ] && echo -e "\nRouter address list is empty\n" \
|| echo -e "\nRouter address list:\n$tmp_value\n"
;;
esac
[ -n "$setm" ] && exec /etc/clish/quick_cm.sh setm "$setm"
