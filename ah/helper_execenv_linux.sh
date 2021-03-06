#!/bin/sh
OPKG_CONF_FILE="/etc/opkg.conf"
help_execenv_repository() {
	local _obj="$1"
	local _url="$2"
	tmp_file=$(mktemp -p /tmp)
	cat >$tmp_file <<EOF
src/gz snapshots $_url
dest root /
dest ram /tmp
dest usb1 /mnt/sda1
lists_dir ext /var/opkg-lists
option overlay_root /jffs
EOF
	mv $tmp_file $OPKG_CONF_FILE
	opkg update &
}
du_uuid_gen() {
	local _name="$1"
	local _version="$2"
	md5s=$(echo "$_name $_version" | md5sum | cut -d' ' -f 1)
	uuid="${md5s:0:8}-${md5s:8:4}-${md5s:12:4}-${md5s:16:4}-${md5s:20}"
	echo $uuid
}
help_execenv_check() {
	local _obj="$1"
	local _enabled="$2"
	local _security="$3"
	local _ret=0
	local duobj
	if [ "$_enabled" = "true" ]; then
		cmclient -v duobj GETO "SoftwareModules.DeploymentUnit.[ExecutionEnvRef=$_obj]"
		for duobj in $duobj; do
			cmclient -v duname GETV "$duobj.Name"
			[ -n "$duname" ] || continue
			version=""
			status=""
			set -f
			while IFS=": " read -r section a b c; do
				case "$section" in
				Version)
					version="$a"
					;;
				Status)
					status="$c"
					;;
				esac
			done <<-EOF
				$(opkg status "$duname")
			EOF
			set +f
			if [ "$status" = "installed" ]; then
				setm="$duobj.Status=Installed"
			else
				setm="$duobj.Status=Uninstalled"
			fi
			if [ -n "$version" ]; then
				setm="$setm	$duobj.Version=$version"
			fi
			cmclient -v duuid GETV "$duobj.UUID"
			if [ -z "$duuid" ]; then
				duuid=$(du_uuid_gen "$duname" "$version")
				setm="$setm	$duobj.UUID=$duuid"
			fi
			cmclient -v duid GETV "$duobj.DUID"
			if [ -z "$duid" ]; then
				duid=${duobj##*.}
				setm="$setm	$duobj.DUID=${duid}"
			fi
			cmclient SETM "$setm" >/dev/null
		done
	fi
	return $_ret
}
help_execenv_status() {
	local obj="$1"
	local section data
	local mem_total mem_free mem_buffers mem_cached mem_swapfree
	cmclient -v enabled GETV "$obj.Enable"
	if [ "$enabled" = "true" ]; then
		execenv_status="Up"
		IFS=. read -r execenv_uptime _ </proc/uptime
	else
		execenv_uptime=0
		execenv_status="Disabled"
	fi
	execenv_allocated_mem=-1
	execenv_available_mem=-1
	set -f
	while IFS=" " read -r section data _; do
		case "$section" in
		"MemTotal:")
			mem_total=${data}
			;;
		"MemFree:")
			mem_free=${data}
			;;
		"Buffers:")
			mem_buffers=${data}
			;;
		"Cached:")
			mem_cached=${data}
			;;
		"SwapTotal:")
			mem_swaptotal=${data}
			;;
		"SwapFree:")
			mem_swapfree=${data}
			;;
		esac
	done </proc/meminfo
	set +f
	execenv_allocated_mem=$((mem_total + mem_swaptotal))
	execenv_available_mem=$((mem_free + mem_buffers + mem_cached + mem_swapfree))
}
help_execenv_reset() {
	:
}
