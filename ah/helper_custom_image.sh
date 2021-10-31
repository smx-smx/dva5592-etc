#!/bin/sh
compare_custom_versions() {
	local loc_ver="$1" rem_ver="$2" loc_dummy="" rem_dummy="" result
	loc_ver="${loc_ver%%.R}"
	rem_ver="${rem_ver%%.R}"
	loc_dummy="${loc_ver##*-}"
	rem_dummy="${rem_ver##*-}"
	loc_ver="${loc_ver##*_}"
	rem_ver="${rem_ver##*_}"
	loc_ver="${loc_ver%%-*}"
	rem_ver="${rem_ver%%-*}"
	[ "$loc_ver" != "$rem_ver" ] || [ "$loc_dummy" != "$rem_dummy" ]
	result="$?"
	return "$result"
}
