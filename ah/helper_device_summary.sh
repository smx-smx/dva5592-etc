#!/bin/sh
help_check_profile() {
	[ "$1" != "param" ] && local param
	cmclient -u CWMP -v param GET "$3"
	[ ${#param} -gt 0 ] && eval "${1}=\"\${${1}:+\$${1}, }${2}\""
}
help_tr104_summary() {
	[ "$2" != "srv1obj" ] && local srv1obj
	[ "$2" != "voice1" ] && local voice1
	[ "$2" != "voice2" ] && local voice2
	[ "$2" != "param" ] && local param
	srv1obj="${1}.Services.VoiceService.1"
	help_check_profile voice1 "Endpoint:1, SIPEndpoint:1, TAEndpoint:1" "${srv1obj}.VoiceProfileNumberOfEntries"
	[ ${#voice1} -gt 0 ] && eval "${2}=\"\${${2}:+\$${2}, }VoiceService:1.1[1](${voice1})\""
	[ ${#voice2} -gt 0 ] && eval "${2}=\"\${${2}:+\$${2}, }VoiceService:2.0[1](${voice2})\""
}
help_tr140_summary() {
	[ "$2" != "srv1obj" ] && local srv1obj
	[ "$2" != "storage" ] && local storage
	[ "$2" != "param" ] && local param
	srv1obj="${1}.Services.StorageService.1"
	help_check_profile storage "Baseline:2" "${srv1obj}.PhysicalMediumNumberOfEntries"
	help_check_profile storage "NetServer:1" "${srv1obj}.NetworkServer.SMBEnable"
	help_check_profile storage "FTPServer:1" "${srv1obj}.FTPServer.Enable"
	help_check_profile storage "GroupAccess:2" "${srv1obj}.UserGroupNumberOfEntries"
	help_check_profile storage "HTTPServer:1" "${srv1obj}.HTTPServer.Enable"
	help_check_profile storage "HTTPSServer:1" "${srv1obj}.HTTPSServer.Enable"
	help_check_profile storage "UserAccess:2" "${srv1obj}.UserAccountNumberOfEntries"
	help_check_profile storage "VolumeConfig:1" "${srv1obj}.LogicalVolumeNumberOfEntries"
	[ ${#storage} -gt 0 ] && eval "${2}=\"\${${2}:+\$${2}, }StorageService:1.2[1](${storage})\""
}
