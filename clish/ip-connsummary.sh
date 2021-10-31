#/bin/sh
. /etc/clish/clish-commons.sh
get_if_by_ip() {
	local wanip="${1%%:*}"
	local ifobj
	cmclient -v obj GETO "IP.Interface.[X_ADB_Upstream=true].IPv4Address.[IPAddress=$wanip]"
	if [ -n "$obj" ]; then
		ifobj="${obj%.IPv4Address.*}"
		cmclient -v wanif GETV "$ifobj.Alias"
	else
		wanif="-"
	fi
	echo "$wanif"
}
print_connections_table() {
	local filename="$1"
	local proto protonum ttl connstatus bytes packets direction lanport wanport modemport routingmode wanstatus wanifip
	local cnt=1
	local row1=7
	local row2=15
	local row3=21
	local row4=21
	local row5=21
	local row6=11
	local row7=11
	local row8=20
	local row9=16
	local row11=20
	local row12=15
	local row13=10
	local row14=15
	local table_format="|%-${row1}s|%-${row2}s|%-${row3}s|%-${row4}s|%-${row5}s|%-${row6}s|%-${row7}s|%-${row8}s|%-${row9}s|%-${row11}s|%-${row12}s|%-${row13}s|%-${row14}s|\n"
	printf "$table_format" "$(dup_char $row1)" "$(dup_char $row2)" "$(dup_char $row3)" "$(dup_char $row4)" "$(dup_char $row5)" "$(dup_char $row6)" "$(dup_char $row7)" "$(dup_char $row8)" "$(dup_char $row9)" "$(dup_char $row11)" "$(dup_char $row12)" "$(dup_char $row13)" "$(dup_char $row14)"
	printf "$table_format" " Number" " Protocol" " LAN" " Modem" " WAN" " WAN Status" " TTL (sec.)" " Bytes (TX/RX)" " Packets (TX/RX)" " WAN Device" " Routing Mode" " Direction" " Flags"
	printf "$table_format" "$(dup_char $row1)" "$(dup_char $row2)" "$(dup_char $row3)" "$(dup_char $row4)" "$(dup_char $row5)" "$(dup_char $row6)" "$(dup_char $row7)" "$(dup_char $row8)" "$(dup_char $row9)" "$(dup_char $row11)" "$(dup_char $row12)" "$(dup_char $row13)" "$(dup_char $row14)"
	while IFS="," read -r proto protonum ttl connstatus packets bytes direction lanport wanport modemport routingmode wanstatus _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ wanifip _; do
		byte_tx="${bytes%/*}"
		byte_rx="${bytes#*/}"
		if [ -n "$byte_tx" ]; then
			byte_tx="$(size_to_human_format "$byte_tx")"
		else
			byte_tx="0B"
		fi
		if [ -n "$byte_rx" ]; then
			byte_rx="$(size_to_human_format "$byte_rx")"
		else
			byte_rx="0B"
		fi
		bytes="$byte_tx/$byte_rx"
		printf "$table_format" "$cnt" "$proto ($protonum)" "$lanport" "$modemport" "$wanport" "$wanstatus" "$ttl" "$bytes" "$packets" "$(get_if_by_ip "$wanifip")" "$routingmode" "$direction" "$connstatus"
		cnt=$((cnt + 1))
	done <"$filename"
	printf "$table_format" "$(dup_char $row1)" "$(dup_char $row2)" "$(dup_char $row3)" "$(dup_char $row4)" "$(dup_char $row5)" "$(dup_char $row6)" "$(dup_char $row7)" "$(dup_char $row8)" "$(dup_char $row9)" "$(dup_char $row11)" "$(dup_char $row12)" "$(dup_char $row13)" "$(dup_char $row14)"
	echo
}
show() {
	local filename="/tmp/nf_conntrack_clish_$LOGNAME"
	local filename1="/tmp/nf_conntrack_clish_out_$LOGNAME"
	local ipinterface1 ipinterface8 subnetinterface1 subnetinterface8 bridgeportes bridgeportes1 totallines
	local cnt
	cat /proc/net/nf_conntrack >"$filename"
	cmclient -v ipinterface1 GETV "Device.IP.Interface.1.IPv4Address.1.IPAddress"
	cmclient -v subnetinterface1 GETV "Device.IP.Interface.1.IPv4Address.1.SubnetMask"
	cmclient -v bridgeportes GETO "DHCPv4.Server.[Enable=true].Pool.[!IPRouters]"
	for this in $bridgeportes; do
		if [ -n "$cnt" ]; then
			bridgeportes1=$this
			break
		else
			cnt=1
		fi
	done
	cmclient -v ipinterface2 GETV "$bridgeportes1.Interface"
	if [ -z "$ipinterface2" ]; then
		ipinterface8=$ipinterface1
		subnetinterface8=$subnetinterface1
	else
		cmclient -v ipinterface8 GETV "$ipinterface2.IPv4Address.1.IPAddress"
		cmclient -v subnetinterface8 GETV "$ipinterface2.IPv4Address.1.SubnetMask"
	fi
	/etc/ah/consummary.sh "$filename" "$ipinterface1" "$subnetinterface1" "$ipinterface8" "$subnetinterface8" >$filename1
	totallines=$(wc -l "$filename1" | egrep -o '[0-9]*')
	echo
	echo "Total connections $totallines"
	[ "$totallines" -ne "0" -a -n "$totallines" ] && print_connections_table "$filename1"
	rm -f "$filename"
	rm -f "$filename1"
}
show
