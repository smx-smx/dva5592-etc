#!/bin/sh
command -v help_serialize >/dev/null || . /etc/ah/helper_serialize.sh
help_ip6tables() {
	if [ -z "$tmpiptablesprefix" ]; then
		if [ -n "$user" ] && [ -d "/tmp/$user" ]; then
			export tmpiptablesprefix="/tmp/$user"
		else
			export tmpiptablesprefix=$(mktemp -d /tmp/iptables_XXXXXX)
		fi
	elif ! [ -d "$tmpiptablesprefix" ]; then
		[ "$1" != commit ] &&
			echo "$0 $tmpiptablesprefix directory does not exists when executing help_ip6tables $@" >/dev/console
		return 1
	fi
	local current_table="filter"
	if [ "$1" = "-t" ]; then
		current_table=$2
		shift 2
	fi
	local tmpfile="$tmpiptablesprefix/ip6tables-$current_table"
	if [ ! -s "$tmpfile" ]; then
		echo "*$current_table" >"$tmpfile"
		help_append_trap "help_ip6tables commit && rmdir \"$tmpiptablesprefix\" 2>/dev/null" EXIT
	fi
	case "$1" in
	commit)
		set +f
		help_serialize iptables-commit notrap >/dev/null
		for rulefile in "$tmpiptablesprefix"/ip6tables-*; do
			[ -f "$rulefile" ] || continue
			echo "COMMIT" >>"$rulefile"
			cat "$rulefile" >>"$tmpiptablesprefix/ip6tables"
		done
		rm -f "$tmpiptablesprefix"/ip6tables-*
		if [ -s "$tmpiptablesprefix/ip6tables" ]; then
			if [ "$2" = "noerr" ]; then
				ip6tables-restore --noflush <"$tmpiptablesprefix/ip6tables" 2>/dev/null
			else
				if ip6tables-restore --noflush <"$tmpiptablesprefix/ip6tables" 2>/dev/console; then :; else
					printf '\n\e[47;35mERROR!\e[0m\n\n' >/dev/console
					local i=1
					while IFS= read -r x; do
						echo "$i: $x" >/dev/console
						i=$((i + 1))
					done <"$tmpiptablesprefix/ip6tables"
				fi
			fi
		fi
		rm -f "$tmpiptablesprefix/ip6tables"
		if [ -f "$tmpiptablesprefix/do_flush" ]; then
			cmclient SET Device.X_ADB_FastForward.Yatta.FlushConnections true
			rm -f "$tmpiptablesprefix/do_flush"
		fi
		local lastFlush=0
		[ -s /tmp/last_fc_flush ] && read -r lastFlush </tmp/last_fc_flush
		local now
		IFS=. read -r now _ </proc/uptime
		if [ $((now - 5)) -gt $lastFlush ]; then
			[ -x /bin/fc ] && fc flush
			echo $now >/tmp/last_fc_flush
		fi
		help_serialize_unlock iptables-commit
		;;
	-[NF])
		echo ":$2 -" >>"$tmpfile"
		;;
	*)
		echo "$@" >>"$tmpfile"
		;;
	esac
}
