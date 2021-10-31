#!/bin/sh
[ "$user" = "dummy" ] && exit 0
AH_NAME="LogicalVolume-Create"
UNIT_1BLOCK_INBYTES=1024
UNIT_1MB_INBYTES=1000000
OK=0
ERR=1
call_fdisk_p() {
	local devName=$1
	local command=$2
	local subcommand=$3
	local partnum=$4
	local lvolSize=$5
	fdisk $devName >/tmp/fdisk.err 2>&1 <<EOF
$command
$subcommand
${partNum}
$nullv
+${lvolSize}M
w
EOF
	return $?
}
call_fdisk_l() {
	local devName=$1
	local command=$2
	local start=$3
	local end=$4
	fdisk $devName >/tmp/fdisk.err 2>&1 <<EOF
$command
$start
$end
w
EOF
	return $?
}
getNextFirstCyl() {
	local lcylList="$1"
	local skipCyl="$2"
	local count="1"
	local prevVal=
	numEntries=$(echo $lcylList | wc -w)
	for cyl in $lcylList; do
		if [ "$count" = "1" ] && [ "$cyl" != "1" ]; then
			continue
		fi
		if [ "$count" = "1" ] && [ "$cyl" = "1" ]; then
			count=$((count + 1))
			continue
		elif [ "$cyl" -le "$skipCyl" ]; then
			count=$((count + 1))
			continue
		elif [ "$count" = "$numEntries" ]; then
			continue
		fi
		if [ -n "$prevVal" ]; then
			prevVal=$((prevVal + 1))
			if [ "$prevVal" != "$cyl" ]; then
				break
			fi
			prevVal=
		else
			prevVal=$cyl
		fi
		count=$((count + 1))
	done
	if [ "$count" = "$numEntries" ]; then
		echo "_ $cyl"
	else
		echo "$prevVal $cyl"
	fi
}
getLogicalVolumeList() {
	local devName="$1"
	local ret_val=""
	local devBaseName=$(basename $devName 2>/dev/null)
	while read logicalvolume; do
		lvolName=$(echo $logicalvolume | grep "$devBaseName" | cut -f4 -d' ')
		if [ -n "$lvolName" ]; then
			ret_val="$ret_val $lvolName"
		fi
	done </proc/partitions
	echo "$ret_val"
}
getNewLogicalVolumeName() {
	local devName="$1"
	local oldList="$2"
	local newList="$3"
	local newLvolName=""
	local newTempLvolName=""
	local chkExtended=""
	local extName=""
	local found="false"
	local newListName=""
	local oldListName=""
	newTempLvolName=$(echo ${newList##$oldList})
	count=$(echo $newTempLvolName | wc -w)
	if [ "$count" -gt "1" ]; then
		chkExtended=$(fdisk -l $devName | grep Extended | tr -s ' ' | cut -d ' ' -f6)
		if [ "$chkExtended" = "Extended" ]; then
			extName=$(fdisk -l $devName | grep Extended | tr -s ' ' | cut -d ' ' -f1)
			extBaseName=$(basename $extName 2>/dev/null)
		fi
		newLvolName=$(echo ${newTempLvolName##$extBaseName})
		count=$(echo $newLvolName | wc -w)
		if [ "$count" -gt "1" ]; then
			for newListName in $newList; do
				found="false"
				for oldListName in $oldList; do
					if [ "$newListName" = "$oldListName" ]; then
						found="true"
						break
					fi
				done
				if [ "$found" = "true" ]; then
					oldList=$(echo ${oldList##$newListName})
				else
					newLvolName=$newListName
					break
				fi
			done
		fi
	elif [ "$count" -eq "1" ]; then
		newLvolName=$newTempLvolName
	fi
	echo $newLvolName
}
checkPrimaryPartitionAvailability() {
	local devName="$1"
	local devBaseName=$(basename $devName 2>/dev/null)
	local chkExtended=""
	local extIndex=""
	local ret_val="ERROR"
	lvolOffset="4"
	countPrimary="0"
	chkExtended=$(fdisk -l $phyName | grep Extended | tr -s ' ' | cut -d ' ' -f6)
	if [ "$chkExtended" = "Extended" ]; then
		extName=$(fdisk -l $phyName | grep Extended | tr -s ' ' | cut -d ' ' -f1)
		extBaseName=$(basename $extName 2>/dev/null)
		extIndex=$(echo -n $extBaseName | sed 's/sd[a-z]*//g')
	fi
	while read logicalvolume; do
		lvolName=$(echo $logicalvolume | grep "$devBaseName" | cut -f4 -d' ')
		if [ -n "$lvolName" ]; then
			lvolIndex=$(echo -n $lvolName | sed 's/sd[a-z]*//g')
			if [ -n "$lvolIndex" ]; then
				if [ "$lvolIndex" -le "$lvolOffset" ] && [ "$lvolIndex" != "$extIndex" ]; then
					priParts="$priParts $lvolIndex"
				fi
			fi
		fi
	done </proc/partitions
	countPrimary=$(echo $priParts | wc -w)
	case $countPrimary in
	"4")
		ret_val="ERROR"
		;;
	"3")
		ret_val="NO"
		;;
	"2")
		ret_val="YES"
		;;
	"1")
		ret_val="YES"
		;;
	"0")
		ret_val="YES"
		;;
	*)
		ret_val="ERROR"
		;;
	esac
	echo $ret_val
}
createPrimaryPartition() {
	local devName="$1"
	local lvolSize="$2"
	local partNum=""
	local devBaseName=$(basename $devName 2>/dev/null)
	local priParts=""
	local chkExtended=""
	local extIndex=""
	local ret_val=$ERR
	lvolOffset="4"
	countPrimary="0"
	chkExtended=$(fdisk -l $phyName | grep Extended | tr -s ' ' | cut -d ' ' -f6)
	if [ "$chkExtended" = "Extended" ]; then
		extName=$(fdisk -l $phyName | grep Extended | tr -s ' ' | cut -d ' ' -f1)
		extBaseName=$(basename $extName 2>/dev/null)
		extIndex=$(echo -n $extBaseName | sed 's/sd[a-z]*//g')
	fi
	while read logicalvolume; do
		lvolName=$(echo $logicalvolume | grep "$devBaseName" | cut -f4 -d' ')
		if [ -n "$lvolName" ]; then
			lvolIndex=$(echo -n $lvolName | sed 's/sd[a-z]*//g')
			if [ -n "$lvolIndex" ]; then
				if [ "$lvolIndex" -le "$lvolOffset" ] && [ "$lvolIndex" != "$extIndex" ]; then
					priParts="$priParts $lvolIndex"
				fi
			fi
		fi
	done </proc/partitions
	countPrimary=$(echo $priParts | wc -w)
	case $countPrimary in
	"0")
		partNum="1"
		;;
	"1")
		case $priParts in
		" 1")
			partNum="2"
			;;
		" 2")
			partNum="1"
			;;
		" 3")
			partNum="1"
			;;
		*)
			return "$ERR"
			;;
		esac
		;;
	"2")
		case $priParts in
		" 1 2")
			partNum="3"
			;;
		" 2 1")
			partNum="3"
			;;
		" 1 3")
			partNum="2"
			;;
		" 3 1")
			partNum="2"
			;;
		" 2 3")
			partNum="1"
			;;
		" 3 2")
			partNum="1"
			;;
		*)
			return "$ERR"
			;;
		esac
		;;
	*)
		return "$ERR"
		;;
	esac
	noPrimaryPartId="false"
	if [ "$countPrimary" -eq "2" ] && [ -n "$extIndex" ]; then
		noPrimaryPartId="true"
	fi
	call_fdisk_p "$devName" "n" "p" "$partNum" "$lvolSize"
	ret_val=$?
	ret=$(grep -r "Value out of range." /tmp/fdisk.err)
	if [ "$ret_val" != "$OK" ] && [ -n "$ret" ]; then
		echo "error with primary partition ${lvolSize}M, retry" >/dev/console
		call_fdisk_p "$devName" "n" "p" "$partNum" ""
		ret_val=$?
	else
		echo "Successfully created the primary partition" >/dev/console
	fi
	ret_val=$?
	rm -f /tmp/fdisk.err
	return $ret_val
}
createLogicalPartition() {
	local devName="$1"
	local lvolSize="$2"
	local chkExtended=""
	local extIndex=""
	local ret_val=$ERR
	lvolOffset="4"
	countPrimary="0"
	chkExtended=$(fdisk -l $devName | grep Extended | tr -s ' ' | cut -d ' ' -f6)
	if [ "$chkExtended" = "Extended" ]; then
		extName=$(fdisk -l $devName | grep Extended | tr -s ' ' | cut -d ' ' -f1)
		extBaseName=$(basename $extName 2>/dev/null)
		extIndex=$(echo -n $extBaseName | sed 's/sd[a-z]*//g')
	fi
	if [ -z "$extIndex" ]; then
		fdisk $devName >/dev/null 2>&1 <<EOF
n
e
$nullv
$nullv
w
EOF
		ret_val=$?
		if [ "$ret_val" != "$OK" ]; then
			return $ERR
		fi
	fi
	call_fdisk_l "$devName" "n" "" "+${lvolSize}M"
	ret_val=$?
	ret=$(grep -r "Value out of range." /tmp/fdisk.err)
	if [ "$ret_val" != "$OK" ] && [ -n "$ret" ]; then
		echo "error with logical partition ${lvolSize}M, retry" >/dev/console
		call_fdisk_l "$devName" "n" "" ""
		ret_val=$?
	else
		echo "Successfully created the logical partition" >/dev/console
	fi
	rm -f /tmp/fdisk.err
	return $ret_val
}
service_umount_partitions() {
	local lvolPhyRef="$1"
	local lvolEnable=""
	local itf=""
	local localStatus=""
	local lvolName=""
	for lvolObj in $(cmclient GETO Device.Services.StorageService.1.LogicalVolume.*.[PhysicalReference=$lvolPhyRef]); do
		cmclient -v lvolEnable GETV "$lvolObj.Enable"
		if [ "$lvolEnable" = "true" ]; then
			cmclient SET $lvolObj.Enable false >/dev/null
			itf="$itf $lvolObj"
		fi
	done
	while [ "$globalStatus" = "true" ]; do
		localStatus=""
		for lvolObj in $itf; do
			lvolName=$(cmclient GETV $lvolObj.Name)
			status=$(mount | grep $lvolName)
			if [ -n "$status" ]; then
				localStatus="true"
				break
			fi
		done
		if [ "$localStatus" = "" ]; then
			break
		fi
	done
	lvEnabledList="$itf"
}
service_create_partition() {
	local lvolPhyRef="$1"
	local phyName=""
	local lvolPhyIdx=""
	local lvolStatus=""
	local lvolEnable=""
	local lvolName=""
	local lvolReqName=""
	local lvolBaseName=""
	local lvolIndex=""
	local lvolMountDir=""
	local lvolFs=""
	local lvolSize=""
	local errStatus=""
	local oldLvolList=""
	local newLvolList=""
	local newLvolName=""
	local itf=""
	lvolPhyIdx=$(echo ${lvolPhyRef##Device.Services.StorageService.1.PhysicalMedium.})
	cmclient -v phyName GETV Device.Services.StorageService.1.PhysicalMedium.$lvolPhyIdx.X_ADB_DeviceName
	lvolSize=$(cmclient GETV $obj.Capacity)
	lvolStatus=$(cmclient GETV $obj.Status)
	errStatus=$ERR
	if [ "$lvolStatus" = "Offline" ]; then
		oldLvolList=$(getLogicalVolumeList $phyName)
		ret=$(checkPrimaryPartitionAvailability $phyName)
		if [ "$ret" = "YES" ]; then
			createPrimaryPartition $phyName $lvolSize
			errStatus=$?
		elif [ "$ret" = "NO" ]; then
			createLogicalPartition $phyName $lvolSize
			errStatus=$?
		else
			errStatus=$ERR
		fi
	fi
	if [ "$errStatus" = "$OK" ]; then
		newLvolList=$(getLogicalVolumeList $phyName)
		newLvolName=$(getNewLogicalVolumeName $phyName "$oldLvolList" "$newLvolList")
		if [ -n "$newLvolName" ]; then
			setm="$obj.Name=/dev/$newLvolName	$obj.Status=Online"
			while read logicalvolume; do
				LogVolSizeInBlocks=$(echo $logicalvolume | grep "$newLvolName" | cut -f3 -d' ')
				if [ -n "$LogVolSizeInBlocks" ]; then
					LogVolSizeInMB=$(expr $LogVolSizeInBlocks \* $UNIT_1BLOCK_INBYTES / $UNIT_1MB_INBYTES)
					cmSize=$(cmclient GETV $obj.Capacity)
					if [ "$cmSize" != "$LogVolSizeInMB" ]; then
						setm="$setm	$obj.Capacity=$LogVolSizeInMB"
					fi
					break
				fi
			done </proc/partitions
			cmclient SETM "$setm" >/dev/null
		else
			cmclient SET $obj.Status Error >/dev/null
		fi
	else
		cmclient SET $obj.Status Error >/dev/null
	fi
	for lvolObj in $itf; do
		cmclient SET $lvolObj.Enable true >/dev/null
	done
	return $errStatus
}
service_config() {
	local lvolPhyRef=""
	lvEnabledList=""
	Status=$OK
	if [ "$setX_ADB_Create" = "1" -a "$newX_ADB_Create" = "true" ]; then
		cmclient -v lvolPhyRef GETV "$obj.PhysicalReference"
		service_umount_partitions "$lvolPhyRef"
		service_create_partition "$lvolPhyRef"
		Status=$?
		cmclient -u dummy SET "$obj.X_ADB_Create" "false" >/dev/null
	fi
	if [ "$Status" = "$OK" -a "$setX_ADB_Format" = "1" ]; then
		if [ -n "$newX_ADB_Format" ]; then
			cmclient -v lvolPhyRef GETV "$obj.PhysicalReference"
			service_umount_partitions "$lvolPhyRef"
			cmclient SET "$obj.Status" "Formatting" >/dev/null
			/etc/ah/LogicalVolume-MakeFs.sh "$lvolPhyRef" "$lvEnabledList" &
		fi
	fi
}
case "$op" in
"s")
	service_config
	;;
esac
exit 0
