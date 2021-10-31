#!/bin/sh
AH_NAME="SW-DeploymentUnit"
. /etc/ah/helper_serialize.sh && help_serialize "$AH_NAME"
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
LOG_FILE=/tmp/sw-du.log
echo "$AH_NAME" >"$LOG_FILE"
FAULT_REQUEST_DENIED=1
FAULT_INTERNAL_ERROR=2
FAULT_INVALID_ARGS=3
FAULT_FILE_TRANS_FAILURE=17
FAULT_FILE_CORRUPTED=18
FAULT_EE_UNKNOWN=23
FAULT_EE_DISABLED=24
FAULT_DU_EE_MISMATCH=25
FAULT_DU_DUPLICATED=26
FAULT_RESOURCES_EXCEEDED=27
FAULT_UNKNOWN_DU=28
FAULT_INVALID_STATE=29
du_log() {
	echo "$*" >>"$LOG_FILE"
}
du_uuid_gen() {
	local _name="$1" _version="$2"
	md5s=$(echo "$_name $_version" | md5sum | cut -d' ' -f 1)
	uuid="${md5s:0:8}-${md5s:8:4}-${md5s:12:4}-${md5s:16:4}-${md5s:20}"
	echo $uuid
}
du_install() {
	local _duobj="$1" _ret=0
	cmclient -v duname GETV "$_duobj.Name"
	cmclient -v duversion GETV "$_duobj.Version"
	cmclient -v duuid GETV "$_duobj.UUID"
	cmclient -v duurl GETV "$_duobj.URL"
	cmclient -v dudest GETV "$_duobj.X_ADB_InstallDest"
	cmclient -v execenvobj GETV "$_duobj.ExecutionEnvRef"
	cmclient -v execenv GETV "$execenvobj.Name"
	if [ "$execenv" = "Linux" ]; then
		. /etc/ah/helper_du_linux.sh
		helper_du_install "$duname" "$duurl" "$dudest"
		_ret=$?
		if [ $_ret = 0 ]; then
			if [ -n "$opkgname" ] && [ "$opkgname" != "$duname" ]; then
				duname=$opkgname
				cmclient SETE "$_duobj.Name" "$duname"
			fi
			if [ -n "$opkgversion" ] && [ "$opkgversion" != "$duversion" ]; then
				duversion=$opkgversion
				cmclient SETE "$_duobj.Version" "$duversion"
			fi
			if [ -z "$duuid" ]; then
				duuid=$(du_uuid_gen "$duname" "$duversion")
				cmclient SETE "$_duobj.UUID" "$duuid"
			fi
			cmclient SETE "$_duobj.Resolved" "true"
			cmclient SETE "$_duobj.Status" "Installed"
		fi
	elif [ "$execenv" = "OSGi" ]; then
		. /etc/ah/helper_du_osgi.sh
		helper_du_install "$duname" "$duurl"
		_ret=$?
	elif [ "$execenv" = "Docker" ]; then
		. /etc/ah/helper_du_docker.sh
		helper_du_install "$duname" "$duurl"
		_ret=$?
		if [ $_ret = 0 ]; then
			local setm=""
			if [ ${#duuid} -eq 0 ]; then
				duuid=$(du_uuid_gen "$duname" "$duversion")
				setm="$_duobj.UUID=$duuid"
			fi
			setm="$setm	$_duobj.Resolved=true"
			setm="$setm	$_duobj.Status=Installed"
			cmclient SETEM "$setm"
		fi
	elif [ "$execenv" = "LXC" ]; then
		. /etc/ah/helper_du_lxc.sh
		helper_du_install "$duname" "$duurl"
		_ret=$?
	else
		du_log "Don't know how to install sw module to ExecEnv: $execenv"
		_ret=$FAULT_DU_EE_MISMATCH
	fi
	return $_ret
}
du_uninstall() {
	local _duobj="$1" _ret=0
	cmclient -v duname GETV "$_duobj.Name"
	cmclient -v dustatus GETV "$_duobj.Status"
	cmclient -v execenvobj GETV "$_duobj.ExecutionEnvRef"
	cmclient -v execenv GETV "$execenvobj.Name"
	if [ "$execenv" = "Linux" ]; then
		. /etc/ah/helper_du_linux.sh
		helper_du_uninstall "$duname"
		_ret=$?
	elif [ "$execenv" = "OSGi" ]; then
		. /etc/ah/helper_du_osgi.sh
		cmclient -v duid GETV "$_duobj.DUID"
		helper_du_uninstall "$duid"
		_ret=$?
	elif [ "$execenv" = "Docker" ]; then
		. /etc/ah/helper_du_docker.sh
		helper_du_uninstall "$duname" "$_duobj"
		_ret=$?
	elif [ "$execenv" = "LXC" ]; then
		. /etc/ah/helper_du_lxc.sh
		helper_du_uninstall "$duname" "$_duobj"
		_ret=$?
	else
		du_log "Don't know how to uninstall sw module from ExecEnv: $execenv"
		_ret=$FAULT_DU_EE_MISMATCH
	fi
	if [ $_ret = 0 ]; then
		cmclient SETE "$_duobj.Status" "Uninstalled"
		cmclient SETE "$_duobj.Resolved" "false"
	fi
	cmclient SAVE
	return $_ret
}
service_config() {
	local _ret=0
	if [ "$setX_ADB_Operation" = "1" ]; then
		du_log "$newX_ADB_Operation $obj"
		case "$newX_ADB_Operation" in
		Install)
			cmd="Install"
			du_install "$obj"
			;;
		Uninstall)
			cmd="Uninstall"
			du_uninstall "$obj"
			;;
		esac
	fi
	return $_ret
}
du_tr069_install() {
	local _url="$1" _uuid="$2" _username="$3" _password="$4" _execenvobj="$5" _duid="$6"
	local _ret=0 _fext dest url="" name="" ee_obj ee_name ee_enable dufile tmpfile=""
	[ -n "$_url" ] || return $FAULT_INVALID_ARGS
	if [ -z "$_execenvobj" ]; then
		case "$_url" in
		*.jar)
			ee_obj="Device.SoftwareModules.ExecEnv.2"
			;;
		*)
			ee_obj="Device.SoftwareModules.ExecEnv.1"
			;;
		esac
	else
		ee_obj=${_execenvobj%.}
	fi
	cmclient -v ee_enable GETV "$ee_obj.Enable"
	[ "$ee_enable" = "true" ] || return $FAULT_EE_DISABLED
	cmclient -v ee_name GETV "$ee_obj.Name"
	[ "$ee_name" = "OSGi" ] && _fext="jar" || _fext="ipk"
	case "$_url" in
	*?dest=USB1)
		dest=USB1
		;;
	*)
		dest=Root
		;;
	esac
	_url=${_url%?dest=*}
	case "$_url" in
	file://* | /*)
		url="$_url"
		;;
	http://* | ftp://* | https://* | ftps://*)
		tmpfile=$(mktemp -p /tmp)
		mv "$tmpfile" "$tmpfile.$_fext"
		tmpfile="$tmpfile.$_fext"
		_ret=$(yaft -L "$_username:$_password" -d "$_url" -o "$tmpfile")
		if [ ${#_ret} -gt 0 ]; then
			du_log "Cannot download sw module file. $_ret"
			rm -f "$tmpfile"
			return $FAULT_FILE_TRANS_FAILURE
		fi
		url="$tmpfile"
		;;
	*)
		name="$_url"
		;;
	esac
	if [ "$ee_name" = "Linux" ]; then
		. /etc/ah/helper_du_linux.sh
		du_log "Installing Linux package ${name}${url} to $dest..."
		helper_du_install "$name" "$url" "$dest"
		_ret=$?
		if [ $_ret = 0 ]; then
			if [ -n "$opkgname" ]; then
				cmclient -v duobj GETO "SoftwareModules.DeploymentUnit.[Name=$opkgname].[ExecutionEnvRef=$ee_obj]"
			fi
			if [ -z "$duobj" ] && [ -n "$_uuid" ]; then
				cmclient -v duobj GETO "SoftwareModules.DeploymentUnit.[UUID=$_uuid].[ExecutionEnvRef=$ee_obj]"
			fi
			if [ -z "$duobj" ]; then
				cmclient -v duid ADD SoftwareModules.DeploymentUnit
				duobj="Device.SoftwareModules.DeploymentUnit.$duid"
				du_log "created new DU instance $duobj"
				cmclient SETE "$duobj.ExecutionEnvRef" "$ee_obj"
			else
				cmclient -v duname GETV "$duobj.Name"
			fi
			if [ -n "$opkgname" ] && [ "$opkgname" != "$duname" ]; then
				cmclient SETE "$duobj.Name" "$opkgname"
			fi
			if [ -n "$opkgversion" ]; then
				cmclient SETE "$duobj.Version" "$opkgversion"
			fi
			if [ -n "$_uuid" ]; then
				cmclient SETE "$duobj.UUID" "$_uuid"
			else
				cmclient -v duuid GETV "$duobj.UUID"
				if [ -z "$duuid" ]; then
					duuid=$(du_uuid_gen "$opkgname" "$opkgversion")
					cmclient SETE "$duobj.UUID" "$duuid"
				fi
			fi
			cmclient SETE "$duobj.X_ADB_InstallDest" "$dest"
			cmclient SETE "$duobj.URL" "$_url"
			cmclient SETE "$duobj.Resolved" "true"
			cmclient SETE "$duobj.Status" "Installed"
			cmclient SAVE
		fi
	elif [ "$ee_name" = "OSGi" ]; then
		. /etc/ah/helper_du_osgi.sh
		du_log "installing OSGi bundle ${name}${url}..."
		helper_du_install "$name" "$url" "$_duid"
		_ret=$?
		if [ $_ret = 0 ] && [ -n "$bundleid" ]; then
			du_log "Wait for DU instance update for bundle $bundleid..."
			sleep 3
			if [ -n "$bundlename" ]; then
				cmclient -v duobj GETO "SoftwareModules.DeploymentUnit.[Name=$bundlename].[ExecutionEnvRef=$ee_obj]"
			fi
			if [ -z "$duobj" ] && [ -n "$_uuid" ]; then
				cmclient -v duobj GETO "SoftwareModules.DeploymentUnit.[UUID=$_uuid].[ExecutionEnvRef=$ee_obj]"
			fi
			if [ -z "$duobj" ]; then
				cmclient -v duobj GETO "SoftwareModules.DeploymentUnit.[DUID=$bundleid].[ExecutionEnvRef=$ee_obj]"
			fi
			if [ -z "$duobj" ]; then
				cmclient -v duid ADD SoftwareModules.DeploymentUnit
				duobj="Device.SoftwareModules.DeploymentUnit.$duid"
				du_log "created new DU instance $duobj"
				cmclient SETE "$duobj.ExecutionEnvRef" "$ee_obj"
				cmclient SETE "$duobj.DUID" "$bundleid"
				if [ -n "$bundlename" ]; then
					cmclient SETE "$duobj.Name" "$bundlename"
				fi
				if [ -n "$bundleversion" ]; then
					cmclient SETE "$duobj.Version" "$bundleversion"
				fi
				case "$bundlestatus" in
				"INSTALLED")
					cmclient SETE "$duobj.Resolved" "false"
					cmclient SETE "$duobj.Status" "Installed"
					;;
				"UNINSTALLED")
					cmclient SETE "$duobj.Resolved" "false"
					cmclient SETE "$duobj.Status" "Uninstalled"
					;;
				*)
					cmclient SETE "$duobj.Resolved" "true"
					cmclient SETE "$duobj.Status" "Installed"
					;;
				esac
			fi
			cmclient SETE "$duobj.URL" "$url"
			if [ -n "$_uuid" ]; then
				cmclient SETE "$duobj.UUID" "$_uuid"
			else
				cmclient -v duuid GETV "$duobj.UUID"
				if [ -z "$duuid" ]; then
					duuid=$(du_uuid_gen "$bundlename" "$bundleversion")
					cmclient SETE "$duobj.UUID" "$duuid"
				fi
			fi
			cmclient SAVE
		fi
	elif [ "$ee_name" = "Docker" ]; then
		. /etc/ah/helper_du_docker.sh
		helper_du_install "$_url"
		_ret=$?
		if [ $_ret = 0 ]; then
			local fullname id_and_sha shortname_and_tag tag id du_num eu_num setm host_numbridge_obj \
				hostn mng_port="" ip_obj=""
			fullname=$(docker inspect --format='{{(index .RepoTags 0)}}' --type=image ${_url})
			id_and_sha=$(docker inspect --format='{{.Id}}' --type=image ${_url})
			shortname_and_tag=${fullname##*/}
			cont_name=$(help_str_replace_all ":" "_" "$shortname_and_tag")
			tag=${shortname_and_tag##*:}
			id=${id_and_sha##*:}
			id=${id:0:12}
			cmclient -v du_num ADD Device.SoftwareModules.DeploymentUnit.[Name=${_url}]
			setm="Device.SoftwareModules.DeploymentUnit.${du_num}.ExecutionEnvRef=$_execenvobj"
			setm="$setm	Device.SoftwareModules.DeploymentUnit.${du_num}.Description=\"Docker image\""
			setm="$setm	Device.SoftwareModules.DeploymentUnit.${du_num}.Status=Installed"
			setm="$setm	Device.SoftwareModules.DeploymentUnit.${du_num}.Resolved=true"
			setm="$setm	Device.SoftwareModules.DeploymentUnit.${du_num}.DUID=${id}"
			setm="$setm	Device.SoftwareModules.DeploymentUnit.${du_num}.URL=${_url}"
			setm="$setm	Device.SoftwareModules.DeploymentUnit.${du_num}.Version=${tag}"
			duuid=$(du_uuid_gen "${_url}" "${tag}")
			setm="$setm	Device.SoftwareModules.DeploymentUnit.${du_num}.UUID=${duuid}"
			cmclient SETM "$setm"
			cmclient -v eu_num ADD Device.SoftwareModules.ExecutionUnit.[Name=${cont_name}]
			setm="Device.SoftwareModules.ExecutionUnit.${eu_num}.Status=Idle"
			setm="$setm	Device.SoftwareModules.ExecutionUnit.${eu_num}.ExecutionEnvRef=$_execenvobj"
			setm="$setm	Device.SoftwareModules.ExecutionUnit.${eu_num}.Description=\"Docker container\""
			setm="$setm	Device.SoftwareModules.ExecutionUnit.${eu_num}.Version=${tag}"
			setm="$setm	Device.SoftwareModules.DeploymentUnit.${du_num}.ExecutionUnitList=Device.SoftwareModules.ExecutionUnit.${eu_num}"
			cmclient SETM "$setm"
			cmclient -v bridge_obj GETV ${ee_obj}.X_ADB_DefaultBridge
			[ -n "$bridge_obj" ] && cmclient -v mng_port GETO ${bridge_obj}.Port.[ManagementPort=true]
			[ -n "$mng_port" ] && help_ip_interface_get_first ip_obj ${mng_port}
			hostn=${cont_name}_${id}
			cmclient -v host_num ADD Device.Hosts.Host.[HostName=${hostn}]
			setm="Device.Hosts.Host.${host_num}.Active=false"
			setm="$setm	Device.Hosts.Host.${host_num}.AddressSource=Static"
			setm="$setm	Device.Hosts.Host.${host_num}.Layer1Interface=${mng_port}"
			setm="$setm	Device.Hosts.Host.${host_num}.Layer3Interface=${ip_obj}"
			cmclient SETM "$setm"
			cmclient SET Device.SoftwareModules.ExecutionUnit.${eu_num}.X_ADB_VirtualHostRef Device.Hosts.Host.${host_num}
			_ret = 0
		fi
		cmclient SAVE
	elif [ "$ee_name" = "LXC" ]; then
		. /etc/ah/helper_du_lxc.sh
		helper_du_install "$_url"
		_ret=$?
		if [ $_ret = 0 ]; then
			container_name=${_url##*/}
			cmclient -v du_num ADD Device.SoftwareModules.DeploymentUnit.[Name="$container_name"]
			DepUnit="Device.SoftwareModules.DeploymentUnit.${du_num}"
			cmclient SETM "$DepUnit.ExecutionEnvRef=$_execenvobj	$DepUnit.Status=Installed	$DepUnit.Resolved=true	$DepUnit.URL=${_url}"
			cmclient -v eu_num ADD Device.SoftwareModules.ExecutionUnit.[Name="$container_name"]
			ExecUnit="Device.SoftwareModules.ExecutionUnit.${eu_num}"
			cmclient SETM "$ExecUnit.Status=Idle	$ExecUnit.RequestedState=Idle	$ExecUnit.ExecutionEnvRef=$_execenvobj	$ExecUnit.ExecutionFaultCode=NoFault	$ExecUnit.ExecutionFaultMessage="
			cmclient SET Device.SoftwareModules.DeploymentUnit.${du_num}.ExecutionUnitList Device.SoftwareModules.ExecutionUnit.${eu_num}
			_ret = 0
		fi
	else
		du_log "Don't know how to install sw module to ExecEnv: $ee_name"
		_ret=$FAULT_DU_EE_MISMATCH
	fi
	if [ $_ret != 0 ]; then
		du_log "Error installing sw module"
	fi
	[ -n "$tmpfile" ] && rm -f "$tmpfile"
	return $_ret
}
du_tr069_update() {
	local _uuid=$1 _version=$2 _url=$3 _username=$4 _password=$5 _ret=0 _execenvobj=""
	_ret=$FAULT_UNKNOWN_DU
	[ -n "$_uuid" -o -n "$_url" ] || return $FAULT_INVALID_ARGS
	[ -n "$_uuid" ] && quuid=".[UUID=$_uuid]"
	[ -n "$_version" ] && qversion=".[Version=$_version]"
	[ -z "$_uuid" ] && qurl=".[URL=$_url]"
	cmclient -v _duobj GETO "SoftwareModules.DeploymentUnit$quuid$qversion$qurl"
	if [ -n "$_duobj" ]; then
		[ -z "$_url" ] && cmclient -v _url GETV "$_duobj.URL"
		[ -z "$_uuid" ] && cmclient -v _uuid GETV "$_duobj.UUID"
		if [ -n "$_url" ]; then
			cmclient -v _execenvobj GETV "$_duobj.ExecutionEnvRef"
			cmclient -v _execenvname GETV "$_execenvobj.Name"
			if [ "$_execenvname" = "Linux" ]; then
				du_tr069_install "$_url" "$_uuid" "$_username" "$_password"
				_ret=$?
			else
				cmclient -v _duid GETV "$_duobj.DUID"
				du_tr069_install "$_url" "$_uuid" "$_username" "$_password" "$_duid"
				_ret=$?
			fi
		fi
	fi
	return $_ret
}
du_tr069_uninstall() {
	local _uuid=$1 _version=$2 _execenvobj=$3
	local _ret=0 _dufilter
	_execenvobj=${_execenvobj%.}
	_dufilter="[UUID=$_uuid]"
	if [ -n "$_version" ]; then
		_dufilter="${_dufilter}.[Version=${_version}]"
	fi
	if [ -n "$_execenvobj" ]; then
		_dufilter="${_dufilter}.[ExecutionEnvRef=${_execenvobj}]"
	fi
	cmclient -v duobj GETO "SoftwareModules.DeploymentUnit.${_dufilter}"
	if [ -n "$duobj" ]; then
		for duobj in $duobj; do
			du_uninstall $duobj
			_ret=$?
			break
		done
	else
		_ret=$FAULT_UNKNOWN_DU
	fi
	return $_ret
}
du_op_update() {
	local _cmd="$1" _code="$2" _opobj="$3" _duobj="$4" _stime="$5" _ctime="$6"
	local _param _value
	cmclient SETE "$_opobj.FaultCode" "$_code"
	cmclient SETE "$_opobj.OperationPerformed" "$_cmd"
	cmclient SETE "$_opobj.StartTime" "$_stime"
	cmclient SETE "$_opobj.CompleteTime" "$_ctime"
	if [ -n "$_duobj" ]; then
		cmclient SETE "$_opobj.DeploymentUnitRef" "$_duobj."
		for _param in UUID Version Resolved; do
			cmclient -v _value GETV "$_duobj.$_param"
			cmclient SETE "$_opobj.$_param" "$_value"
		done
		cmclient -v _value GETV "$_duobj.ExecutionUnitList"
		cmclient SETE "$_opobj.ExecutionUnitRefList" "$_value"
	fi
	if [ "$_code" = "0" ]; then
		case "$_cmd" in
		Install | Update)
			_value="Installed"
			;;
		Uninstall)
			_value="Uninstalled"
			;;
		esac
	else
		_value="Failed"
	fi
	cmclient SET "$_opobj.CurrentState" "$_value"
}
auton_du_op_report() {
	local _mserver="$1" _cmd="$2" _code="$3" _duobj="$4" _stime="$5" _ctime="$6"
	local _filter _duscc _opobj _idx
	cmclient -v _filter GETV "${_mserver}.DUStateChangeComplPolicy.[Enable=true].[OperationTypeFilter,${_cmd}].ResultTypeFilter"
	case "$_filter" in
	Success) [ "$_code" = "0" ] || return ;;
	Failure) [ "$_code" != "0" ] || return ;;
	Both) ;;
	*) return ;;
	esac
	cmclient -v _idx ADD "$_mserver.X_ADB_CWMPState.DUStateChangeComplete.[Autonomous=true]"
	_duscc="$_mserver.X_ADB_CWMPState.DUStateChangeComplete.$_idx"
	cmclient -v _idx ADD "$_duscc.Operation"
	_opobj="$_duscc.Operation.$_idx"
	du_op_update "$_cmd" "$_code" "$_opobj" "$_duobj" "$_stime" "$_ctime"
}
du_op_report() {
	local _client="$1" _cmd="$2" _code="$3" _opobj="$4" _duobj="$5" _stime="$6" _ctime="$7"
	if [ -z "$_opobj" ]; then
		if [ "$client" != "cwmp" ]; then
			auton_du_op_report "Device.ManagementServer" "$_cmd" "$_code" "$_duobj" "$_stime" "$_ctime"
		fi
	else
		du_op_update "$_cmd" "$_code" "$_opobj" "$_duobj" "$_stime" "$_ctime"
	fi
}
ret=0
stime=$(date -u +%FT%TZ)
if [ "$2" = "INSTALL" ]; then
	du_log "$1 $2 $3 $4"
	cmd="Install"
	client="$1"
	opobj="$8"
	du_tr069_install "$3" "$4" "$5" "$6" "$7"
	ret=$?
elif [ "$2" = "UPDATE" ]; then
	du_log "$1 $2 $3 $4 $5"
	cmd="Update"
	client="$1"
	opobj="$8"
	du_tr069_update "$3" "$4" "$5" "$6" "$7"
	ret=$?
elif [ "$2" = "UNINSTALL" ]; then
	du_log "$1 $2 $3 $4"
	cmd="Uninstall"
	client="$1"
	opobj="$6"
	du_tr069_uninstall "$3" "$4" "$5"
	ret=$?
elif [ "$op" = "s" ]; then
	duobj="$obj"
	client="$user"
	opobj=""
	service_config
	ret=$?
else
	exit 0
fi
ctime=$(date -u +%FT%TZ)
[ -n "$cmd" ] && du_op_report "$client" "$cmd" "$ret" "$opobj" "$duobj" "$stime" "$ctime"
exit $ret
