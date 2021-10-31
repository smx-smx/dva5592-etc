#!/bin/sh
export PURE_PASSWDFILE="/tmp/pureftpd.passwd"
export PURE_DBFILE="/tmp/pureftpd.pdb"
set_user_ftp_access() {
	local userObj=$1 accessType=$2 cmUserAccessObj cmUserFolderObj \
		cmFolderObj accessEnable folderName
	[ ${#userObj} -eq 0 ] && return 1
	[ "$accessType" != "Local" -a "$accessType" != "Remote" ] && return 1
	if [ "$accessType" = "Local" ]; then
		cmUserAccessObj="$userObj.AllowFTPAccess"
		cmUserFolderObj="$userObj.X_ADB_FTPStartingFolder"
	else
		cmUserAccessObj="$userObj.X_ADB_AllowRemoteFTPAccess"
		cmUserFolderObj="$userObj.X_ADB_RemoteFTPStartingFolder"
	fi
	cmclient -v accessEnable GETV $cmUserAccessObj
	[ "$accessEnable" = "false" ] && return 1
	cmclient -v cmFolderObj GETV $cmUserFolderObj
	if [ ${#cmFolderObj} -eq 0 ]; then
		ftpServerObj="Device.Services.StorageService.1.FTPServer"
		cmclient -v cmFolderObj GETV $ftpServerObj.X_ADB_StartingFolder
	fi
	if [ ${#cmFolderObj} -ne 0 ]; then
		cmclient -v folderName GETV $cmFolderObj.Name
		if [ ${#folderName} -ne 0 ]; then
			cmclient SET $cmUserAccessObj true
			return 0
		fi
	fi
	cmclient SET $cmUserAccessObj false
	return 0
}
mkdir -m 777 -p /tmp/spool
mkdir -p /tmp/samba
touch /tmp/samba/smb.conf
cmclient -v autoenable GETV Device.Services.StorageService.1.NetworkServer.X_ADB_AutoshareEnable
if [ "$autoenable" = "true" ]; then
	for lvobj in $(cmclient GETO Device.Services.StorageService.1.LogicalVolume); do
		setm="$lvobj.Status=Offline	$setm"
	done
	if [ -n "$setm" ]; then
		cmclient SETM "$setm" >/dev/null
		setm=""
	fi
fi
for lpobj in $(cmclient GETO Device.Services.X_ADB_PrinterService.PrinterDevice); do
	setm="$lpobj.Status=Offline	$lpobj.DeviceName=\"\"	$setm"
	for jobObj in $(cmclient GETO $lpObj.PrintJob); do
		cmclient -u boot DEL $jobObj >/dev/null
	done
done
if [ -n "$setm" ]; then
	cmclient -u boot SETM "$setm" >/dev/null
	setm=""
fi
rm -rf /dev/usblp*
spoolEna=$(cmclient GETV Device.Services.X_ADB_PrinterService.SpoolEnabled)
if [ "$spoolEna" = "true" ]; then
	spoolPartition=$(cmclient GETV Device.Services.X_ADB_PrinterService.SpoolPartition)
	spoolPartition=$(cmclient GETV $spoolPartition.Name)
	spoolPartition=$(basename $spoolPartition 2>/dev/null)
	spoolPartition=/mnt/$spoolPartition
	spoolPartition=$spoolPartition$SMBSPOOL
	if [ ! -e "$spoolPartition" ]; then
		cmclient SET Device.Services.X_ADB_PrinterService.SpoolEnabled false >/dev/null
	fi
fi
rawenable=$(cmclient GETV Device.Services.X_ADB_PrinterService.Servers.RAW.Enable)
if [ "$rawenable" = "true" ]; then
	cmclient SET Device.Services.X_ADB_PrinterService.Servers.RAW.Enable false >/dev/null
	cmclient SET Device.Services.X_ADB_PrinterService.Servers.RAW.Enable true >/dev/null
fi
accountPath="Device.Services.StorageService.1.UserAccount"
cmclient -v cmUserObj GETO $accountPath
oldIFS=$IFS
IFS='
'
if [ -z "$cmUserObj" ]; then
	for pureUser in $(pure-pw list 2>/dev/null); do
		pureUserName=$(echo $pureUser | cut -f1 -s)
		if [ -n "$pureUserName" ]; then
			pure-pw userdel $pureUserName 2>/dev/null
		fi
	done
else
	for pureUser in $(pure-pw list 2>/dev/null); do
		pureUserName=$(echo $pureUser | cut -f1 -s)
		if [ ${#pureUserName} -ne 0 ]; then
			userSelector="$accountPath.*.[Username=$pureUserName]"
			cmclient -v cmUserObj GETO $userSelector
			if [ ${#cmUserObj} -ne 0 ]; then
				cmclient -v cmUserEnable GETV $cmUserObj.Enable
				if [ "$cmUserEnable" = "true" ]; then
					set_user_ftp_access $cmUserObj "Local"
					set_user_ftp_access $cmUserObj "Remote"
				fi
			else
				pure-pw userdel $pureUserName 2>/dev/null
			fi
		fi
	done
	cmclient -v cmUserObj GETO $accountPath
	for cmUserObj in $cmUserObj; do
		found="false"
		cmUserEnable=$(cmclient GETV $cmUserObj.Enable)
		cmUserName=$(cmclient GETV $cmUserObj.Username)
		if [ "$cmUserEnable" = "true" ]; then
			for pureUser in $(pure-pw list 2>/dev/null); do
				pureUserName=$(echo $pureUser | cut -f1 -s)
				if [ "$pureUserName" = "$cmUserName" ]; then
					found="true"
					break
				fi
			done
			if [ "$found" = "false" ]; then
				set_user_ftp_access $cmUserObj "Local"
				set_user_ftp_access $cmUserObj "Remote"
			fi
		fi
	done
fi
IFS=$oldIFS
cmclient -v cmAnFtpEnable GETV "Device.Services.StorageService.1.FTPServer.AnonymousUser.Enable"
if [ "$cmAnFtpEnable" = "true" ]; then
	cmclient -v cmAnFtpStartFld GETV "Device.Services.StorageService.1.FTPServer.AnonymousUser.StartingFolder"
	if [ ${#cmAnFtpStartFld} -ne 0 ]; then
		cmclient -v cmAnFtpStartFldName GETV "$cmAnFtpStartFld.Name"
		if [ ${#cmAnFtpStartFldName} -eq 0 ]; then
			:
		else
			cmclient SET Device.Services.StorageService.1.FTPServer.AnonymousUser.Enable true >/dev/null
		fi
	else
		cmclient -v cmFtpMainStartFolder GETV "Device.Services.StorageService.1.FTPServer.X_ADB_StartingFolder"
		if [ ${#cmFtpMainStartFolder} -eq 0 ]; then
			cmclient SET Device.Services.StorageService.1.FTPServer.AnonymousUser.Enable false >/dev/null
		else
			cmclient -v cmFtpMainStartFolderName GETV "$cmFtpMainStartFolder.Name"
			if [ ${#cmFtpMainStartFolderName} -eq 0 ]; then
				cmclient SET Device.Services.StorageService.1.FTPServer.AnonymousUser.Enable false >/dev/null
			else
				cmclient SET Device.Services.StorageService.1.FTPServer.AnonymousUser.Enable true >/dev/null
			fi
		fi
	fi
else
	cmclient SET Device.Services.StorageService.1.FTPServer.AnonymousUser.Enable false >/dev/null
fi
>/tmp/samba/smbpasswd
for usrObj in $(cmclient GETO Device.Services.StorageService.1.UserAccount.[Enable=true]); do
	userName=$(cmclient GETV $usrObj.Username)
	userPassword=$(cmclient GETV $usrObj.Password)
	if [ -n "$userName" ] && [ -n "$userPassword" ]; then
		smbpasswd $userName $userPassword 2>&1 >/dev/null
	fi
done
/etc/eh/delay/eh_usbdevices.sh probe
