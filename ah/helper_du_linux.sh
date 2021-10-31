#!/bin/sh
helper_du_install() {
	local _duname="$1" _duurl="$2" _dudest="$3" _username="$4" _password="$5"
	local _ret=0 _f1 _f2 _f3
	local _opkgopts="--force-downgrade"
	local _force_install=""
	[ "$_dudest" = "USB1" ] && _opkgopt="${_opkgopt} -d usb1" || _opkgopt="${_opkgopt} -d root"
	if [ -n "$_duurl" ]; then
		opkg install $_force_install "$_duurl" $_opkgopts >/tmp/opkg-out 2>&1
		_ret=$?
	elif [ -n "$_duname" ]; then
		[ -f /var/opkg-lists/snapshots ] || opkg update
		opkg install "$_duname" $_opkgopts >/tmp/opkg-out 2>&1
		_ret=$?
	else
		_ret=$FAULT_INVALID_ARGS
		return $_ret
	fi
	cat /tmp/opkg-out >>"$LOG_FILE"
	if [ $_ret = 0 ]; then
		set -f
		IFS=" ()"
		while read -r _f1 _f2 _f3 _; do
			case "$_f1" in
			"Installing" | "Upgrading" | "Downgrading")
				opkgname="$_f2"
				opkgversion="$_f3"
				;;
			esac
		done </tmp/opkg-out
		set +f
	else
		_ret=$FAULT_FILE_CORRUPTED
		set -f
		IFS=" :*	"
		while read -r _f1 _f2 _; do
			case "$_f2" in
			"opkg_download")
				_ret=$FAULT_FILE_TRANS_FAILURE
				;;
			"satisfy_dependencies_for")
				_ret=$FAULT_REQUEST_DENIED
				;;
			esac
		done </tmp/opkg-out
		set +f
	fi
	return $_ret
}
helper_du_uninstall() {
	local _duname="$1" _ret=0
	local _f1 _f2
	opkg remove "$_duname" >/tmp/opkg-out 2>&1
	_ret=$?
	cat /tmp/opkg-out >>"$LOG_FILE"
	if [ $_ret != 0 ]; then
		du_log "Error removing package $_duname: $_ret"
		_ret=$FAULT_INTERNAL_ERROR
		set -f
		IFS=" :*	"
		while read -r _f1 _f2 _; do
			case "$_f2" in
			"print_dependents_warning")
				_ret=$FAULT_REQUEST_DENIED
				;;
			esac
		done </tmp/opkg-out
		set +f
	fi
	return $_ret
}
