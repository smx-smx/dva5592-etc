#!/bin/sh
FTP_BASEDIR="/tmp/pure-ftpd"
FTPRemote_PASSWDFILE="$FTP_BASEDIR/pureftpd-remote.passwd"
FTPRemote_DBFILE="$FTP_BASEDIR/pureftpd-remote.pdb"
FTPLocal_PASSWDFILE="$FTP_BASEDIR/pureftpd-local.passwd"
FTPLocal_DBFILE="$FTP_BASEDIR/pureftpd-local.pdb"
FTPRemote_USER="ftpremote"
FTPLocal_USER="ftplocal"
FTPRemote_PIDFILE="/var/run/pure-ftpd-Remote.pid"
FTPLocal_PIDFILE="/var/run/pure-ftpd-Local.pid"
FTPLocal_INETD_FILE="/tmp/inetd/pureftpd-local.inetd"
FTPRemote_INETD_FILE="/tmp/inetd/pureftpd-remote.inetd"
FTP_MAX_TIMEOUT="2147483647"
case "${obj}" in
Device.Services.StorageService.*.FTPServer | Device.Services.StorageService.*.FTPServer.*)
	FTPPREFIX=Local
	FTPUSER="$FTPLocal_USER"
	PIDFILE="$FTPLocal_PIDFILE"
	FTP_INETD_FILE="$FTPLocal_INETD_FILE"
	;;
Device.Services.StorageService.*.X_ADB_FTPServerRemote | Device.Services.StorageService.*.X_ADB_FTPServerRemote.*)
	FTPPREFIX=Remote
	FTPUSER="$FTPRemote_USER"
	PIDFILE="$FTPRemote_PIDFILE"
	FTP_INETD_FILE="$FTPRemote_INETD_FILE"
	;;
esac
mkdir -p "$FTP_BASEDIR"
ftpdeluser() {
	local username="$1"
	local db="$2"
	local pwd=""
	case "$db" in
	Local)
		db="$FTPLocal_DBFILE"
		pwd="$FTPLocal_PASSWDFILE"
		;;
	Remote)
		db="$FTPRemote_DBFILE"
		pwd="$FTPRemote_PASSWDFILE"
		;;
	esac
	touch "$pwd"
	pure-pw userdel "$username" -f "$pwd" -F "$db" -m >/dev/null 2>&1
}
ftpadduser() {
	local username="$1"
	local password="$2"
	local folder="$3"
	local db="$4"
	local pwd=""
	case "$folder" in
	*/../*) return 1 ;;
	/mnt/sd*) ;;
	*) return 1 ;;
	esac
	case "$db" in
	Local)
		db="$FTPLocal_DBFILE"
		pwd="$FTPLocal_PASSWDFILE"
		;;
	Remote)
		db="$FTPRemote_DBFILE"
		pwd="$FTPRemote_PASSWDFILE"
		;;
	esac
	touch "$pwd"
	printf '%s\n%s\n' "$password" "$password" | pure-pw useradd "$username" -f "$pwd" -F "$db" -d "$folder" -u 0 -g 0 -m >/dev/null 2>&1
}
