#!/bin/sh
printf "UTC   time: %s\n" "$(date -u)"
local=$(date)
printf "Local time: %s\n" "$local"
if [ "${local##*CET}" = "${local##CET*}" ]; then
	printf "Timezone  : Europe/Zurich, offset = 120\n"
else
	printf "Timezone  : Europe/Zurich, offset = 60\n"
fi
