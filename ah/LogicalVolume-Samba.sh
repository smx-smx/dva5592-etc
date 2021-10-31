#!/bin/sh
AH_NAME="LogicalVolume-Samba"
[ "$user" = "$AH_NAME$obj" ] && exit 0
[ "$user" = "yacs" ] && exit 0
[ "$user" = "boot" ] && exit 0
[ "$user" = "dummy" ] && exit 0
[ -f /tmp/upgrading.lock -o -f /tmp/loading_modules -o -d /tmp/init_iptables ] && [ "$op" != "g" ] && exit 0
. /etc/ah/helper_serialize.sh && help_serialize_nowait "$AH_NAME"
. /etc/ah/helper_storage.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_ipcalc.sh
SAMBA_INETD_CONF="/tmp/inetd/samba.inetd"
SAMBA_CONF_DIR="/tmp/samba"
SAMBA_CONF_FILE="$SAMBA_CONF_DIR/smb.conf"
SAMBA_PASS_FILE="$SAMBA_CONF_DIR/smbpasswd"
SAMBA_CONF_FILE_LOCK="smb.conf"
SAMBA_CONF_FILE_SKIP="smb.conf.skip"
SAMBA_CONF_MAIN_FILE="$SAMBA_CONF_DIR/smb.main.conf"
SAMBA_CONF_FOLDER_DIR="$SAMBA_CONF_DIR/smb.folders.d"
NMBD_CONF_FILE="$SAMBA_CONF_DIR/nmbd.conf"
SAMBA_SPOOL_DEFAULT="/tmp/spool"
SAMBA_SPOOL_SUBDIR="smb-spool"
conf_validate() {
	return 0
}
conf_inetd() {
	local ip ifobj mask ip_bcast ra="" if="" rbs=""
	cmclient -v ip GETV "Device.IP.Interface.*.[Enable=true].[X_ADB_Upstream=false].IPv4Address.*.IPAddress"
	for ip in $ip; do
		echo "$ip-none,netbios-ns,137 dgram udp wait root $(which nmbd) nmbd -s $SAMBA_CONF_FILE"
		echo "$ip-none,netbios-ssn,139 stream tcp nowait root $(which smbd) smbd -s $SAMBA_CONF_FILE"
		echo "$ip-none,microsoft-ds,445 stream tcp nowait root $(which smbd) smbd -s $SAMBA_CONF_FILE"
	done >$SAMBA_INETD_CONF
	killall nmbd
	cmclient -v ifobj GETO "Device.IP.Interface.*.[Enable=true].[X_ADB_Upstream=false].IPv4Address"
	for ifobj in $ifobj; do
		cmclient -v ip GETV "$ifobj.IPAddress"
		cmclient -v mask GETV "$ifobj.SubnetMask"
		help_calc_broadcast ip_bcast ${ip} ${mask}
		ra="${ra:+$ra }$ip_bcast"
		if="${if:+$if }$ip/$mask"
		rbs="${rbs:+$rbs }$ip_bcast"
	done
	cat >>$NMBD_CONF_FILE <<-EOF
		remote announce = $ra
		interfaces = $if
		bind interfaces only = yes
		lm announce = yes
		lm interval = 20
		remote browser sync = $rbs
	EOF
	nmbd -D -s "$NMBD_CONF_FILE"
}
conf_generate() {
	[ ! -f $SAMBA_CONF_MAIN_FILE ] && return
	mkdir -p $SAMBA_CONF_FOLDER_DIR
	cat $SAMBA_CONF_MAIN_FILE >$SAMBA_CONF_FILE
	: >$SAMBA_CONF_FOLDER_DIR/keep
	cat $SAMBA_CONF_FOLDER_DIR/* >>$SAMBA_CONF_FILE
}
service_share_printers() {
	local conf="$1"
	local printer=""
	local prnDeviceName=""
	local prnSpoolEnabled=""
	local prnSpoolDirectory=""
	local volumeobj=""
	local prnSpoolPartition=""
	local ipRange=""
	local intobjs
	local ipaddrobjs
	local printobjs
	cmclient -v prnSpoolEnabled GETV Device.Services.X_ADB_PrinterService.SpoolEnabled
	if [ "$prnSpoolEnabled" = "true" ]; then
		cat >>$conf <<-EOF
			load printers = yes
			printing = cups
			printcap name = cups
		EOF
	fi
	local tmp
	cmclient -v tmp GETV Device.Services.X_ADB_PrinterService.Servers.SMB.Enable
	if [ "$tmp" = "true" ]; then
		if [ "$prnSpoolEnabled" = "true" ]; then
			cmclient -v prnSpoolDirectory GETV Device.Services.X_ADB_PrinterService.SpoolPartition
			if [ -n "$prnSpoolDirectory" ]; then
				volumeobj="${prnSpoolDirectory%%.Folder.*}"
				cmclient -v prnSpoolPartition GETV $volumeobj.X_ADB_MountPoint
				cmclient -v prnSpoolDirectory GETV $prnSpoolDirectory.Name
				if [ -n "$prnSpoolDirectory" -a -n "$prnSpoolPartition" ]; then
					prnSpoolDirectory="$prnSpoolPartition/$prnSpoolDirectory/$SAMBA_SPOOL_SUBDIR"
				else
					prnSpoolDirectory="$SAMBA_SPOOL_DEFAULT"
				fi
			else
				prnSpoolDirectory="$SAMBA_SPOOL_DEFAULT"
			fi
		else
			prnSpoolDirectory="$SAMBA_SPOOL_DEFAULT"
		fi
		ipRange=
		IFS=,
		cmclient -v intobjs GETV Device.Services.X_ADB_PrinterService.Interfaces
		for ipObj in $intobjs; do
			unset IFS
			cmclient -v ipaddrobjs GETO "$ipObj.IPv4Address"
			for ipAddrObj in $ipaddrobjs; do
				local ipAddress
				local ipSubnetMask
				cmclient -v ipAddress GETV $ipAddrObj.IPAddress
				cmclient -v ipSubnetMask GETV $ipAddrObj.SubnetMask
				ipRange="$ipRange $ipAddress/$ipSubnetMask"
			done
			IFS=,
		done
		unset IFS
		cmclient -v printobjs GETO "Device.Services.X_ADB_PrinterService.PrinterDevice.[Status=Online]"
		for printer in $printobjs; do
			local prnEnable
			cmclient -v prnEnable GETV $printer.Enable
			if [ "$prnEnable" = "true" ]; then
				local prnShareName
				cmclient -v prnShareName GETV $printer.Name
				if [ -n "$prnShareName" ]; then
					local prnDescription
					local prnLocation
					local prnDeviceName
					cmclient -v prnDescription GETV $printer.Description
					cmclient -v prnLocation GETV $printer.Location
					cmclient -v prnDeviceName GETV $printer.DeviceName
					cat >>$conf <<-EOF
						[$prnShareName]
						comment = $prnDescription $prnLocation
						path = $prnSpoolDirectory
					EOF
					if [ "$prnSpoolEnabled" = "false" -a -n "$prnDeviceName" ]; then
						cat >>$conf <<-EOF
							device = $prnDeviceName
							print command = echo
							lpq command = echo
						EOF
					fi
					cat >>$conf <<-EOF
						print ok = yes
						guest ok = yes
						hosts allow = $ipRange
					EOF
				fi
			fi
		done
	fi
}
flush_iptables_samba_rules() {
	local r
	local t
	local o
	for r in SambaIn SambaOut; do
		if [ $r = SambaIn ]; then
			o="--dport"
		else
			o="--sport"
		fi
		for t in mangle filter; do
			help_iptables -t $t -F $r
		done
	done
}
conf_header() {
	local conf="$1" ipobj ipaddrobj hostsallow ipobjs ipaddrobjs ipaddr ipnm vncobj vncobjs ipminaddr ipmaxaddr poolsize t
	flush_iptables_samba_rules
	local domainName
	local hostName
	cmclient -v domainName GETV Device.Services.StorageService.1.NetInfo.DomainName
	cmclient -v hostName GETV Device.Services.StorageService.1.NetInfo.HostName
	domainName=${domainName%%\\*}
	hostName=${hostName%%\\*}
	mkdir -p $SAMBA_CONF_DIR
	: >$conf
	cat >$conf <<-EOF
		[global]
		netbios name = $hostName
		workgroup = $domainName
		wide links = no
		smb ports = 445 139
	EOF
	if [ "$newNetworkProtocolAuthReq" = "true" ]; then
		cat >>$conf <<-EOF
			security = user
			passdb backend = smbpasswd
			smb passwd file = $SAMBA_PASS_FILE
			server signing = mandatory
		EOF
	else
		cat >>$conf <<-EOF
			security = share
			guest account = root
		EOF
	fi
	cat >>$conf <<-EOF
		announce version = 5.0
		socket options = TCP_NODELAY SO_RCVBUF=65536 SO_SNDBUF=65536
		null passwords = yes
		name resolve order = hosts wins bcast
		wins support = yes
		syslog only = yes
		read only = no
	EOF
	if [ -z "$newX_ADB_SMBInterfaces" ]; then
		cmclient -v ipobjs GETO Device.IP.Interface.[Enable=true].[X_ADB_Upstream=false]
		for ipobj in $ipobjs; do
			if [ -z "$newX_ADB_SMBInterfaces" ]; then
				newX_ADB_SMBInterfaces="$ipobj"
			else
				newX_ADB_SMBInterfaces="$newX_ADB_SMBInterfaces,$ipobj"
			fi
		done
	fi
	hostsallow=""
	set -f
	IFS="$IFS,"
	for ipobj in $newX_ADB_SMBInterfaces; do
		cmclient -v ipaddrobjs GETO $ipobj.IPv4Address.[Enable=true].[IPAddress!]
		for ipaddrobj in $ipaddrobjs; do
			cmclient -v ipaddr GETV $ipaddrobj.IPAddress
			cmclient -v ipnm GETV $ipaddrobj.SubnetMask
			hostsallow="$hostsallow $ipaddr/$ipnm"
			for t in mangle filter; do
				help_iptables -t $t -A SambaIn -p tcp --dport 139 -d $ipaddr/32 -j CONNMARK --set-mark 8/8
				help_iptables -t $t -A SambaIn -p tcp --dport 139 -d $ipaddr/32 -j ACCEPT
				help_iptables -t $t -A SambaIn -p tcp --dport 445 -d $ipaddr/32 -j CONNMARK --set-mark 8/8
				help_iptables -t $t -A SambaIn -p tcp --dport 445 -d $ipaddr/32 -j ACCEPT
			done
		done
	done
	set +f
	unset IFS
	cmclient -v vncobjs GETO "Device.IPsec.Filter.[Enable=true].[ProcessingChoice=Protect].[X_ADB_RoadWarrior.Enable=false]"
	for vncobj in $vncobjs; do
		cmclient -v ipaddr GETV "$vncobj.DestIP"
		cmclient -v ipnm GETV "$vncobj.DestMask"
		[ -z "$ipaddr" ] && continue
		hostsallow="$hostsallow $ipaddr/$ipnm"
	done
	cmclient -v vncobjs GETO "Device.IPsec.Filter.[Enable=true].[X_ADB_RoadWarrior.Enable=true]"
	for vncobj in $vncobjs; do
		cmclient -v ipminaddr GETV "$vncobj.X_ADB_RoadWarrior.Address"
		cmclient -v poolsize GETV "$vncobj.X_ADB_RoadWarrior.PoolSize"
		cmclient -v ipnm GETV "$vncobj.X_ADB_RoadWarrior.SubnetMask"
		cmclient -v t GETV "$vncobj.X_ADB_RoadWarrior.Type"
		[ -z "$ipminaddr" ] && continue
		if [ "$t" = "L2TP" ]; then
			have_l2tp_ipsec="true"
			continue
		fi
		help_ip2int ipnm "$ipnm"
		help_ip2int ipminaddr "$ipminaddr"
		ipmaxaddr=$((ipminaddr + poolsize)) # allowed addresses are Address and "PoolSize" consecutive addresses
		[ $((ipmaxaddr & ipnm)) -gt $((ipminaddr | 0xffffffff & ~ipnm)) ] &&
			ipmaxaddr=$((ipminaddr | 0xffffffff & ~ipnm))
		help_int2ip ipminaddr "$ipminaddr"
		help_int2ip ipmaxaddr "$ipmaxaddr"
		help_ips2masks ipaddr "$ipminaddr" "$ipmaxaddr"
		hostsallow="$hostsallow $ipaddr"
	done
	cmclient -v vncobjs GETO "Device.X_ADB_VPN.Server.PPTP.[Enable=true]"
	for vncobj in $vncobjs; do
		cmclient -v ipminaddr GETV "$vncobj.MinAddress"
		cmclient -v ipmaxaddr GETV "$vncobj.MaxAddress"
		help_ips2masks ipaddr "$ipminaddr" "$ipmaxaddr"
		hostsallow="$hostsallow $ipaddr"
	done
	if [ "$have_l2tp_ipsec" = "true" ]; then
		cmclient -v vncobjs GETO "Device.X_ADB_VPN.Server.L2TP.[Enable=true]"
		for vncobj in $vncobjs; do
			cmclient -v ipminaddr GETV "$vncobj.MinAddress"
			cmclient -v ipmaxaddr GETV "$vncobj.MaxAddress"
			help_ips2masks ipaddr "$ipminaddr" "$ipmaxaddr"
			hostsallow="$hostsallow $ipaddr"
		done
	fi
	for t in mangle filter; do
		help_iptables -t $t -A SambaOut -p tcp --sport 139 -d 0.0.0.0/0 -j CONNMARK --set-mark 8/8
		help_iptables -t $t -A SambaOut -p tcp --sport 139 -d 0.0.0.0/0 -j ACCEPT
		help_iptables -t $t -A SambaOut -p tcp --sport 445 -d 0.0.0.0/0 -j CONNMARK --set-mark 8/8
		help_iptables -t $t -A SambaOut -p tcp --sport 445 -d 0.0.0.0/0 -j ACCEPT
	done
	if [ -n "$hostsallow" ]; then
		cat >>$conf <<-EOF
			hosts allow = $hostsallow
		EOF
	fi
	cp $conf $NMBD_CONF_FILE
	local tmp
	cmclient -v tmp GETV Device.Services.X_ADB_PrinterService.Enable
	if [ "$tmp" = "true" ]; then
		service_share_printers "$conf"
	fi
}
conf_share_folder() {
	local conf="$1"
	local volumeobj="$2"
	local volumestatus="$3"
	local volumeenable="$4"
	local mountpoint="$5"
	local folderobj="$6"
	local name="$7"
	local enable="$8"
	local sharename="$9"
	local permission="$10"
	local guestaccess="$11"
	local authreq="$12"
	local readonly
	local storageobj="${volumeobj%%.LogicalVolume.*}"
	local userobj
	rm -f $conf
	[ "$enable" = "true" ] || return 1
	[ "$volumeenable" = "true" ] || return 1
	[ -n "$mountpoint" -a -d "$mountpoint" ] || return 1
	[ -n "$sharename" ] || return 1
	check_path_traversal "$name" || return 1
	if [ "$permission" = "ro" ]; then
		readonly="yes"
	else
		readonly="false"
	fi
	cat >>$conf <<-EOF
		[$sharename]
		path = $mountpoint/$name
		read only = $readonly
		force user = root
		force group = root
	EOF
	if [ "$authreq" = "true" -a "$guestaccess" = "false" ]; then
		local folderwritelist=""
		local folderreadlist=""
		local validusers=""
		local invalidusers=""
		local fuobjs
		cmclient -v fuobjs GETO "$folderobj.UserAccess.[Enable=true].[UserReference!].[Permissions!]"
		for folderuserobj in $fuobjs; do
			local userobj
			local userpermissions
			local username
			cmclient -v userobj GETV $folderuserobj.UserReference
			cmclient -v userpermissions GETV $folderuserobj.Permissions
			cmclient -v username GETV $userobj.Username
			[ -z "$username" ] && continue
			local userenable
			cmclient -v userenable GETV $userobj.Enable
			[ "$userenable" != "true" ] && continue
			case $userpermissions in
			2 | 3 | 6 | 7)
				if [ -z "$folderwritelist" ]; then
					folderwritelist="$username"
				else
					folderwritelist="$folderwritelist","$username"
				fi
				;;
			4 | 5)
				if [ -z "$fldReadList" ]; then
					folderreadlist="$username"
				else
					folderreadlist="$fldReadList,$username"
				fi
				;;
			esac
		done
		local fgobjs
		cmclient -v fgobjs GETO "$folderobj.GroupAccess.*.[Enable=true].[GroupReference!].[Permissions!]"
		for folderuserobj in $fgobjs; do
			cmclient -v groupobj GETV $folderuserobj.GroupReference
			cmclient -v grouppermissions GETV $folderuserobj.Permissions
			cmclient -v groupname GETV $groupobj.GroupName
			[ -z "$groupname" ] && continue
			cmclient -v groupenable GETV $groupobj.Enable
			[ "$groupenable" != "true" ] && continue
			case $grouppermissions in
			2 | 3 | 6 | 7)
				if [ -z "$folderwritelist" ]; then
					folderwritelist="@$groupname"
				else
					folderwritelist="$folderwritelist,@$groupname"
				fi
				;;
			4 | 5)
				if [-z "$folderreadlist" ]; then
					folderreadlist="@$groupname"
				else
					folderreadlist="$folderreadlist,@$groupname"
				fi
				;;
			esac
		done
		if [ -n "$folderwritelist" ]; then
			cat >>$conf <<-EOF
				write list = $folderwritelist
			EOF
			validusers="$folderwritelist"
		fi
		if [ -n "$folderreadlist" ]; then
			cat >>$conf <<-EOF
				read list = $folderreadlist
			EOF
			if [ -n "$validusers" ]; then
				validusers="$validusers,$folderreadlist"
			else
				validusers="$folderreadlist"
			fi
		fi
		if [ -n "$validusers" ]; then
			cat >>$conf <<-EOF
				valid users = $validusers
			EOF
		fi
		invalidusers=""
		local stobjs
		cmclient -v stobjs GETO "$storageobj.UserAccount.[Enable=true]"
		for userobj in $stobjs; do
			local invalid="false"
			local folderuserobj
			cmclient -v folderuserobj GETO $folderobj.UserAccess.[UserReference=$usrObj]
			if [ -z "$folderuserobj" ]; then
				invalid="true"
			else
				cmclient -v folderuserenable GETV $folderuserobj.Enable
				if [ "$folderuserenable" = "false" ]; then
					invalid="true"
				fi
			fi
			if [ "$invalid" = "true" ]; then
				cmclient -v usrGrpPartList GETV $userobj.UserGroupParticipation
				if [ -n "$usrGrpPartList" ]; then
					set -f
					IFS=,
					for usrGrpPartObj in $usrGrpPartList; do
						cmclient -v fldGrpObjs GETO $folderobj.GroupAccess.[GroupReference=$usrGrpPartObj]
						unset IFS
						for fldGrpObj in $fldGrpObjs; do
							if [ -n "$fldGrpObj" ]; then
								cmclient -v fldGrpObjEnable GETV $fldGrpObj.Enable
								if [ "$fldGrpObjEnable" = "true" ]; then
									invalid="false"
									break
								fi
							fi
						done
						IFS=,
						[ "$invalid" = "false" ] && break
					done
					unset IFS
					set +f
				fi
			fi
			if [ "$invalid" = "true" ]; then
				local username
				cmclient -v username GETV $usrObj.Username
				if [ -n "$invalidusers" ]; then
					invalidusers="$invalidusers,$username"
				else
					invalidusers="$username"
				fi
			fi
		done
		if [ -n "$invalidusers" ]; then
			cat >>$conf <<-EOF
				invalid users = $invaUsers
			EOF
		fi
	else
		cat >>$conf <<-EOF
			guest ok = yes
		EOF
	fi
	return 0
}
NetInfo_need_refresh() {
	[ "$changedDomainName" = "1" ] && return 0
	[ "$changedHostName" = "1" ] && return 0
	return 1
}
NetInfo() {
	case "$op" in
	s)
		NetInfo_need_refresh || return
		local storageobj="${obj%%.NetInfo}"
		[ $(help_sem_get $SAMBA_CONF_FILE_SKIP) -eq 0 ] && (cmclient SET "$storageobj.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
		;;
	esac
}
NetworkServer_need_refresh() {
	[ "$setX_ADB_SambaRefresh" = "1" -a "$newX_ADB_SambaRefresh" = "true" ] && return 0
	[ "$changedSMBEnable" = "1" ] && return 0
	[ "$changedX_ADB_SMBInterfaces" = "1" ] && return 0
	[ "$changedNetworkProtocolAuthReq" = "1" ] && return 0
	return 1
}
NetworkServer() {
	case "$op" in
	s)
		NetworkServer_need_refresh || return
		local volumeobjs="${obj%%.NetworkServer}.LogicalVolume"
		local count=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
		if [ "$changedNetworkProtocolAuthReq" = "1" ]; then
			(cmclient SET "$volumeobjs.Folder.[Enable=true].[X_ADB_ShareName!].[Name!].X_ADB_SambaRefresh" true) &
		fi
		count=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
		if [ $count -eq 0 ]; then
			local lockdir=$(help_serialize_nowait "$SAMBA_CONF_FILE_LOCK" notrap)
			rm -f "$SAMBA_CONF_FILE"
			rm -f "$SAMBA_CONF_MAIN_FILE"
			rm -f "$SAMBA_INETD_CONF"
			local PrintSMBEnable
			cmclient -v PrintSMBEnable GETV Device.Services.X_ADB_PrinterService.Servers.SMB.Enable
			if [ "$newSMBEnable" = "true" -o "$PrintSMBEnable" = "true" ] && conf_validate; then
				conf_header "$SAMBA_CONF_MAIN_FILE"
				conf_generate
				conf_inetd
			fi
			help_serialize_unlock "$SAMBA_CONF_FILE_LOCK"
		fi
		;;
	esac
}
GroupAccess_need_refresh() {
	[ "$setEnable" = "1" ] && return 0
	[ "$changedGroupReference" = "1" ] && return 0
	[ "$changedPermissions" = "1" ] && return 0
	return 1
}
GroupAccess() {
	case "$op" in
	s)
		GroupAccess_need_refresh || return
		local folderobj="${obj%%.GroupAccess.*}"
		local volumeobj="${folderobj%%.Folder.*}"
		local storageobj="${volumeobj%%.LogicalVolume.*}"
		local count=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
		(cmclient SET "$folderobj.[Enable=true].[X_ADB_ShareName!].[Name!].X_ADB_SambaRefresh" true) &
		count=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && (cmclient SET "$storageobj.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
		;;
	d)
		local folderobj="${obj%%.GroupAccess.*}"
		local volumeobj="${folderobj%%.Folder.*}"
		local storageobj="${volumeobj%%.LogicalVolume.*}"
		local count=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
		(cmclient SET "$folderobj.[Enable=true].[X_ADB_ShareName!].[Name!].X_ADB_SambaRefresh" true) &
		count=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && (cmclient SET "$storageobj.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
		;;
	esac
}
UserAccess_need_refresh() {
	[ "$setEnable" = "1" ] && return 0
	[ "$changedPermissions" = "1" ] && return 0
	[ "$changedUserReference" = "1" ] && return 0
	return 1
}
UserAccess() {
	case "$op" in
	s)
		UserAccess_need_refresh || return
		local folderobj="${obj%%.UserAccess.*}"
		local volumeobj="${folderobj%%.Folder.*}"
		local storageobj="${volumeobj%%.LogicalVolume.*}"
		local count=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
		(cmclient SET "$folderobj.[Enable=true].[X_ADB_ShareName!].[Name!].X_ADB_SambaRefresh" true) &
		count=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && (cmclient SET "$storageobj.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
		;;
	d)
		local folderobj="${obj%%.UserAccess.*}"
		local volumeobj="${folderobj%%.Folder.*}"
		local storageobj="${volumeobj%%.LogicalVolume.*}"
		local count=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
		(cmclient SET "$folderobj.[Enable=true].[X_ADB_ShareName!].[Name!].X_ADB_SambaRefresh" true) &
		count=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && (cmclient SET "$storageobj.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
		;;
	esac
}
Folder_need_refresh() {
	[ "$setX_ADB_SambaRefresh" = "1" -a "$newX_ADB_SambaRefresh" = "true" ] && return 0
	[ "$changedEnable" = "1" ] && return 0
	[ "$changedName" = "1" ] && return 0
	[ "$changedX_ADB_ShareName" = "1" ] && return 0
	[ "$changedX_ADB_Permission" = "1" ] && return 0
	[ "$changedX_ADB_AllowGuestAccess" = "1" ] && return 0
	return 1
}
Folder() {
	case "$op" in
	s)
		Folder_need_refresh || return
		if [ -n "$newName" -a -n "$newX_ADB_ShareName" -a -n "$newX_ADB_Permission" -a "$newEnable" ] ||
			[ -n "$oldName" -a -n "$oldX_ADB_ShareName" -a -n "$oldX_ADB_Permission" -a "$oldEnable" ]; then
			local conf="$SAMBA_CONF_FOLDER_DIR/$obj.conf"
			local folderobj="$obj"
			local volumeobj="${obj%%.Folder.*}"
			local storageobj="${volumeobj%%.LogicalVolume.*}"
			local networkserver="$storageobj.NetworkServer"
			local volumestatus
			local volumeenable
			local mountpoint
			local count=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
			local authreq
			cmclient -v volumestatus GETV $volumeobj.Status
			cmclient -v volumeenable GETV $volumeobj.Enable
			cmclient -v mountpoint GETV $volumeobj.X_ADB_MountPoint
			cmclient -v authreq GETV $networkserver.NetworkProtocolAuthReq
			mkdir -p $SAMBA_CONF_FOLDER_DIR
			conf_share_folder "$conf" "$volumeobj" "$volumestatus" "$volumeenable" "$mountpoint" "$folderobj" "$newName" "$newEnable" "$newX_ADB_ShareName" "$newX_ADB_Permission" "$newX_ADB_AllowGuestAccess" "$authreq"
			count=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
			[ $count -eq 0 ] && (cmclient SET "$storageobj.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
		fi
		;;
	d)
		if [ -n "$oldName" -a -n "$oldX_ADB_ShareName" -a -n "$oldX_ADB_Permission" -a "$oldEnable" ]; then
			local volumeobj="${obj%%.Folder.*}"
			local storageobj="${volumeobj%%.LogicalVolume.*}"
			local count=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
			rm -f "$SAMBA_CONF_FOLDER_DIR/$obj.conf"
			count=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
			[ $count -eq 0 ] && (cmclient SET "$storageobj.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
		fi
		;;
	esac
}
LogicalVolume_need_refresh() {
	[ "$changedX_ADB_MountPoint" = "1" ] && return 0
	[ "$changedStatus" = "1" ] && return 0
	[ "$setEnable" = "1" ] && return 0
	return 1
}
LogicalVolume() {
	case "$op" in
	s)
		LogicalVolume_need_refresh || return
		local storageobj="${obj%%.LogicalVolume.*}"
		local count=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
		(cmclient SET "$obj.Folder.[Enable=true].[X_ADB_ShareName!].[Name!].X_ADB_SambaRefresh" true) &
		count=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && (cmclient SET "$storageobj.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
		;;
	esac
}
UserAccount_need_refresh() {
	[ "$changedUsername" = "1" ] && return 0
	[ "$changedEnable" = "1" -o "$setEnable" = "1" ] && return 0
	return 1
}
UserAccount() {
	case "$op" in
	s)
		UserAccount_need_refresh || return
		local storageobj="${obj%%.UserAccount.*}"
		local volumeobj
		local folderobj
		local count=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
		local stobjs
		local vlobjs
		cmclient -v stobjs GETO "$storageobj.LogicalVolume"
		for volumeobj in $stobjs; do
			cmclient -v vlobjs GETO "$volumeobj.Folder"
			for folderobj in $vlobjs; do
				(cmclient SET "$folderobj.UserAccess.[UserReference=$obj].[Enable=true].X_ADB_SambaRefresh" true) &
			done
		done
		count=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && (cmclient SET "$storageobj.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
		;;
	d)
		local storageobj="${obj%%.UserAccount.*}"
		local volumeobj
		local folderobj
		local count=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
		local sobjs
		local vobjs
		cmclient -v sobjs GETO "$storageobj.LogicalVolume"
		for volumeobj in $sobjs; do
			cmclient -v vobjs GETO "$volumeobj.Folder"
			for folderobj in $vobjs; do
				cmclient DEL "$folderobj.UserAccess.[UserReference=$obj]"
			done
		done
		count=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && (cmclient SET "$storageobj.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
		;;
	esac
}
UserGroup_need_refresh() {
	[ "$changedGroupName" = "1" ] && return 0
	[ "$setEnable" = "1" -o "$changedEnable" = "1" ] && return 0
	return 1
}
UserGroup() {
	case "$op" in
	s)
		UserGroup_need_refresh || return
		local storageobj="${obj%%.UserGroup.*}"
		local volumeobj
		local folderobj
		local count=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
		local stobjs
		local vlobjs
		cmclient -v stobjs GETO "$storageobj.LogicalVolume"
		for volumeobj in $stobjs; do
			cmclient -v vlobjs GETO "$volumeobj.Folder"
			for folderobj in $vlobjs; do
				(cmclient SET "$folderobj.GroupAccess.[GroupReference=$obj].[Enable=true].Enable" true) &
			done
		done
		(cmclient SET "$storageobj.UserAccess.[Enable=true].[UserGroupParticipation>$obj]" true) &
		count=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && (cmclient SET "$storageobj.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
		;;
	d)
		local storageobj="${obj%%.UserGroup.*}"
		local volumeobj
		local folderobj
		local count=$(help_sem_signal "$SAMBA_CONF_FILE_SKIP")
		local sobjs
		local vobjs
		cmclient -v sobjs GETO "$storageobj.LogicalVolume"
		for volumeobj in $sobjs; do
			cmclient -v vobjs GETO "$volumeobj.Folder"
			for folderobj in $vobjs; do
				cmclient DEL "$folderobj.GroupAccess.[GroupReference=$obj]"
			done
		done
		count=$(help_sem_wait "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && (cmclient SET "$storageobj.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
		;;
	esac
}
IPv4Address_need_refresh() {
	[ "$changedEnable" = "1" ] && return 0
	[ "$changedIPAddress" = "1" ] && return 0
	return 1
}
IPv4Address() {
	case "$op" in
	s)
		if IPv4Address_need_refresh; then
			local found="false"
			local ipobj
			local setipobj="${obj%%.IPv4Address.*}"
			cmclient -v newX_ADB_SMBInterfaces GETV Device.Services.StorageService.1.NetworkServer.X_ADB_SMBInterfaces
			if [ -z "$newX_ADB_SMBInterfaces" ]; then
				cmclient -v newX_ADB_SMBInterfaces GETO Device.IP.Interface.[Enable=true].[X_ADB_Upstream=false]
			fi
			IFS="$IFS,"
			for ipobj in $newX_ADB_SMBInterfaces; do
				if [ "$setipobj" = "$ipobj" ]; then
					found="true"
				fi
			done
			unset IFS
			if [ "$found" = "true" ]; then
				local count=$(help_sem_get "$SAMBA_CONF_FILE_SKIP")
				[ $count -eq 0 ] && (cmclient SET "Device.Services.StorageService.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true) &
			fi
		fi
		;;
	d)
		local ipobj="${obj%%.IPv4Address.*}"
		local count=$(help_sem_get "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && (cmclient SET "Device.Services.StorageService.NetworkServer.[SMBEnable=true].[X_ADB_SMBInterfaces>$ipobj].X_ADB_SambaRefresh" true) &
		;;
	esac
}
IPInterface_need_refresh() {
	[ "$changedStatus" = "1" ] && return 0
	return 1
}
IPInterface() {
	case "$op" in
	s)
		if IPInterface_need_refresh; then
			local count=$(help_sem_get "$SAMBA_CONF_FILE_SKIP")
			[ $count -eq 0 ] && (cmclient SET "Device.Services.StorageService.1.NetworkServer.[SMBEnable=true].[X_ADB_SMBInterfaces>$obj].X_ADB_SambaRefresh" true) &
		fi
		;;
	d)
		local smbserver
		local objs
		cmclient -v objs GETO "Device.Services.StorageService.NetworkServer.[X_ADB_SMBInterfaces>$obj]"
		for smbserver in $objs; do
			local intobjs
			cmclient -v intobjs GETV $smbserver.X_ADB_SMBInterfaces
			local ifs=",$intobjs,"
			local ifs_pre="${ifs%%,$obj,*}"
			local ifs_post="${ifs##*,$obj,}"
			ifs="$ifs_pre,$ifs_post"
			ifs="${ifs#,}"
			ifs="${ifs%,}"
			cmclient SET $smbserver.X_ADB_SMBInterfaces "$ifs"
		done
		;;
	esac
}
IPsecRoadWarrior_need_refresh() {
	local road_warrior filter_obj filter_enabled
	filter_obj=${obj%.X_ADB_RoadWarrior}
	case "$op" in
	s)
		cmclient -v filter_enabled GETV "$filter_obj.Enable"
		[ "$filter_enabled" = "false" ] && return 1
		[ "$changedEnable" = "1" ] && return 0
		cmclient -v road_warrior GETV "$obj.Enable"
		[ "$road_warrior" = "false" ] && return 1
		[ "$changedAddress" = "1" ] && return 0
		[ "$changedSubnetMask" = "1" ] && return 0
		[ "$changedPoolSize" = "1" ] && return 0
		[ "$changedType" = "1" ] && return 0
		return 1
		;;
	esac
	return 0
}
IPsecFilterRoadWarrior() {
	if IPsecRoadWarrior_need_refresh; then
		local count=$(help_sem_get "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && cmclient SET "Device.Services.StorageService.1.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true &
	fi
}
IPsec_need_refresh() {
	local enabled
	case "$op" in
	s)
		[ "$changedEnable" = "1" ] && return 0
		cmclient -v enabled GETV "$obj.Enable"
		[ "$enabled" = "false" ] && return 1
		[ "$changedDestIP" = "1" ] && return 0
		[ "$changedDestMask" = "1" ] && return 0
		[ "$changedProcessingChoice" = "1" ] && return 0
		return 1
		;;
	d)
		cmclient -v enabled GETV "$obj.Enable"
		[ "$enabled" = "true" ] && return 0
		return 1
		;;
	esac
	return 0
}
IPsecFilter() {
	if IPsec_need_refresh; then
		local count=$(help_sem_get "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && cmclient SET "Device.Services.StorageService.1.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true &
	fi
}
VPNServer_need_refresh() {
	local enabled
	case "$op" in
	s)
		[ "$changedEnable" = "1" ] && return 0
		cmclient -v enabled GETV "$obj.Enable"
		[ "$enabled" = "false" ] && return 1
		[ "$changedMinAddress" = "1" ] && return 0
		[ "$changedMaxAddress" = "1" ] && return 0
		return 1
		;;
	d)
		cmclient -v enabled GETV "$obj.Enable"
		[ "$enabled" = "true" ] && return 0
		return 1
		;;
	esac
	return 0
}
VPNServer() {
	if VPNServer_need_refresh; then
		local count=$(help_sem_get "$SAMBA_CONF_FILE_SKIP")
		[ $count -eq 0 ] && cmclient SET "Device.Services.StorageService.1.NetworkServer.[SMBEnable=true].X_ADB_SambaRefresh" true &
	fi
}
PrinterDevice_need_refresh() {
	[ "$changedStatus" = "1" ] && return 0
	[ "$setEnable" = "1" ] && return 0
	return 1
}
PrinterDevice() {
	case "$op" in
	s)
		PrinterDevice_need_refresh || return
		[ $(help_sem_get $SAMBA_CONF_FILE_SKIP) -eq 0 ] && (cmclient SET "Device.Services.StorageService.1.NetworkServer.X_ADB_SambaRefresh" "true") &
		;;
	esac
}
SmbServer() {
	case "$op" in
	s)
		if [ "$changedEnable" = "1" ]; then
			cmclient SET "Device.Services.StorageService.1.NetworkServer.X_ADB_SambaRefresh" "true" &
		fi
		;;
	esac
}
case "$obj" in
Device.Services.StorageService.*.NetInfo)
	NetInfo
	;;
Device.Services.StorageService.*.NetworkServer)
	NetworkServer
	;;
Device.Services.StorageService.*.LogicalVolume.*.Folder.*.GroupAccess.*)
	GroupAccess
	;;
Device.Services.StorageService.*.LogicalVolume.*.Folder.*.UserAccess.*)
	UserAccess
	;;
Device.Services.StorageService.*.LogicalVolume.*.Folder.*)
	Folder
	;;
Device.Services.StorageService.*.LogicalVolume.*)
	LogicalVolume
	;;
Device.Services.StorageService.*.UserAccount.*)
	UserAccount
	;;
Device.Services.StorageService.*.UserGroup.*)
	UserGroup
	;;
Device.Services.StorageService.*) ;;

Device.IP.Interface.*.IPv4Address.*)
	IPv4Address
	;;
Device.IP.Interface.*)
	IPInterface
	;;
Device.IPsec.Filter.*.X_ADB_RoadWarrior)
	IPsecFilterRoadWarrior
	;;
Device.IPsec.Filter.*)
	IPsecFilter
	;;
Device.X_ADB_VPN.Server.PPTP.* | Device.X_ADB_VPN.Server.L2TP.*)
	VPNServer
	;;
Device.Services.X_ADB_PrinterService.PrinterDevice.*)
	PrinterDevice
	;;
Device.Services.X_ADB_PrinterService.Servers.SMB)
	SmbServer
	;;
esac
exit 0
