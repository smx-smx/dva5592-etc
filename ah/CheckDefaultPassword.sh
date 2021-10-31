#!/bin/sh
. /etc/ah/helper_functions.sh
AH_NAME="CheckDefaultPassword"
MANGLED_PASSWORDS_PATH="/tmp/magled_pass"
NO_MANGLED_PASSWORDS_PATH="/tmp/no_magled_pass"
DEFAULT_PASSWORDS_PATH="/etc/cm/conf/"
save_mangled_password() {
	cmclient PATHSAVE "$MANGLED_PASSWORDS_PATH" "$1" mangle >/dev/null
}
save_nomangled_password() {
	cmclient PATHSAVE "$NO_MANGLED_PASSWORDS_PATH" "$1" nomangle >/dev/null
}
get_password_from_file() {
	local filePath="$1" object="$2" ret="$3" result=""
	result=$(awk '
/<object name="'$object'"/ { rdf=1; }
/<parameter name="'Password'"/ { if(rdf) {pf=1; next } }
/<value>/,/<\/value>/ { if(rdf && pf) { gsub(".*<value>",""); gsub("</value>",""); print; exit } }
/<\/parameter>/ { if(rdf) {pf=0; next } }
/<\/object>/ { if(rdf){ rdf=0; next } }
' $filePath)
	eval $ret="'$result'"
}
get_passwords_from_files() {
	local files="$1" object="$2" ret="$3" tmpPassword foundPasswords file
	for file in $files; do
		get_password_from_file "$file" "$object" tmpPassword
		foundPasswords="$foundPasswords $tmpPassword"
	done
	eval $ret="'$foundPasswords'"
}
is_default_password() {
	local currentPasswords="$1" factoryPasswords="$2" factoryPassword
	for factoryPassword in $factoryPasswords; do
		if help_list_contains "$currentPasswords" "$factoryPassword" " "; then
			return 0
		fi
	done
	return 1
}
service_config() {
	local userObjects userObject mangledPasswords noMangledPasswords defaultPasswordsFiles defaultPassword mechanismEnabled
	cmclient -v mechanismEnabled GETV "Device.Users.X_ADB_DefaultPasswordCheck"
	[ "$mechanismEnabled" = "false" ] && exit 0
	set -f
	cmclient -v userObjects GETO "Device.Users.User.[X_ADB_Role=AdminUser]"
	for userObject in $userObjects; do
		save_mangled_password "$userObject.Password"
		save_nomangled_password "$userObject.Password"
		get_password_from_file "$MANGLED_PASSWORDS_PATH" "$userObject" mangledPasswords
		get_password_from_file "$NO_MANGLED_PASSWORDS_PATH" "$userObject" noMangledPasswords
		defaultPasswordsFiles=$(grep -r -l -E "$userObject" $DEFAULT_PASSWORDS_PATH)
		get_passwords_from_files "$defaultPasswordsFiles" "$userObject" defaultPassword
		if is_default_password "$mangledPasswords $noMangledPasswords" "$defaultPassword"; then
			cmclient SETE "$userObject.X_ADB_HasDefaultPassword" "true"
			cmclient SET "Device.X_ADB_SSHServer.RemoteAccess.Enable" "false"
			cmclient SET "Device.X_ADB_TelnetServer.RemoteAccess.Enable" "false"
			cmclient SET "Device.UserInterface.RemoteAccess.X_ADB_ProtocolsEnabled" ""
			cmclient SET "Device.UserInterface.RemoteAccess.Enable" "false"
		else
			cmclient SETE "$userObject.X_ADB_HasDefaultPassword" "false"
		fi
		rm "$MANGLED_PASSWORDS_PATH"
		rm "$NO_MANGLED_PASSWORDS_PATH"
	done
	set +f
}
service_config
exit 0
