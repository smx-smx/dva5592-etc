#!/bin/sh
install_application() {
	local exec_env_obj command url="$1" username="$2" password="$3"
	cmclient -v exec_env_obj GETO "Device.SoftwareModules.ExecEnv.[Type=Linux]"
	command="CLI\n INSTALL\n $url\n \n $username\n $password\n $exec_env_obj\n \n ;"
	printf "$command" >/tmp/upgrade/swmodule.txt
}
uninstall_application() {
	local application_name="$1" application_obj application_status application_removable
	cmclient -v application_obj GETO "Device.SoftwareModules.DeploymentUnit.[Name=$application_name]"
	if [ -z "$application_obj" ]; then
		echo "Selected application cannot be found in installed modules"
		exit 1
	else
		cmclient -v application_removable GETV "$application_obj.X_ADB_Removable"
		if [ "$application_removable" = "false" ]; then
			echo "Selected application cannot be uninstalled"
			exit 1
		fi
	fi
	cmclient SET "$application_obj.X_ADB_Operation" "Uninstall" >/dev/null
	echo "Selected application has been uninstalled"
}
check_instalation_status() {
	local installation_status installation_exit_code="/tmp/swmodule.log" installation_log="/tmp/sw-du.log"
	local start_line=3 timeout=10
	sleep $timeout
	if [ ! -e "$installation_exit_code" ]; then
		echo "Cannot get installation status"
		exit 1
	fi
	read installation_status <"$installation_exit_code"
	if [ $installation_status -ne 0 ]; then
		echo "$(tail -n +$start_line $installation_log)"
	else
		echo "Application has been successfully installed"
	fi
}
