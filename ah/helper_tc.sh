#!/bin/sh
help_tc_commit() {
	tc -force -batch "$tmptcfile"
	rm "$tmptcfile"
}
help_tc() {
	[ ${#tmptcfile} -eq 0 ] && tmptcfile=$(mktemp /tmp/tc_XXXXXX) &&
		help_append_trap "help_tc_commit" EXIT
	echo "$@" >>"$tmptcfile"
}
