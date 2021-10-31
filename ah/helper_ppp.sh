#!/bin/sh
command -v help_strextract >/dev/null || . /etc/ah/helper_functions.sh
HELPER_PPP_PROTO_MPPE_RET=7
getEncryptionProtocolCmd() {
	[ "$2" != "arg_encr" ] && local arg_encr
	arg_encr=""
	if ! help_is_in_list "$1" "None"; then
		arg_encr="mppe required"
		help_is_in_list "$1" "MPPE-40bit" || arg_encr="${arg_encr},no40"
		help_is_in_list "$1" "MPPE-56bit" || arg_encr="${arg_encr},no56"
		help_is_in_list "$1" "MPPE-128bit" || arg_encr="${arg_encr},no128"
		help_is_in_list "$1" "MPPE-Stateless" && arg_encr="${arg_encr},stateless"
	fi
	eval $2='$arg_encr'
}
getAuthenticationProtocolClientCmd() {
	[ "$2" != "_ret" ] && local _ret
	[ "$2" != "_retval" ] && local _retval
	[ "$2" != "_retauth" ] && local _retauth
	[ "$2" != "_auth_pap" ] && local _auth_pap
	[ "$2" != "_auth_chap" ] && local _auth_chap
	[ "$2" != "_auth_mschap" ] && local _auth_mschap
	[ "$2" != "_auth_mschap2" ] && local _auth_mschap2
	[ "$2" != "proto" ] && local proto
	_auth_pap=""
	_auth_chap=""
	_auth_mschap=""
	_auth_mschap2=""
	_ret="$2"
	_retval="0"
	_retauth="refuse-eap"
	set -f
	IFS=","
	set -- $1
	unset IFS
	set +f
	for proto; do
		case "$proto" in
		PAP)
			_auth_pap=1
			;;
		CHAP)
			_auth_chap=1
			;;
		MS-CHAP)
			_auth_mschap=1
			_retval="$HELPER_PPP_PROTO_MPPE_RET"
			;;
		MS-CHAPv2)
			_auth_mschap2=1
			_retval="$HELPER_PPP_PROTO_MPPE_RET"
			;;
		Auto)
			_auth_pap=1
			_auth_chap=1
			_auth_mschap=1
			_auth_mschap2=1
			_retval="$HELPER_PPP_PROTO_MPPE_RET"
			break
			;;
		esac
	done
	[ ${#_auth_pap} -eq 0 ] && _retauth="$_retauth refuse-pap"
	[ ${#_auth_chap} -eq 0 ] && _retauth="$_retauth refuse-chap"
	[ ${#_auth_mschap} -eq 0 ] && _retauth="$_retauth refuse-mschap"
	[ ${#_auth_mschap2} -eq 0 ] && _retauth="$_retauth refuse-mschap-v2"
	eval $_ret='$_retauth'
	return "$_retval"
}
