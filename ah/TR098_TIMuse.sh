#!/bin/sh
AH_NAME="TIMuser"
DST_START_2012="2012-03-25T02:00:00Z"
DST_START_2013="2013-03-31T02:00:00Z"
DST_START_2014="2014-03-30T02:00:00Z"
DST_START_2015="2015-03-29T02:00:00Z"
DST_START_2016="2016-03-27T02:00:00Z"
DST_START_2017="2017-03-26T02:00:00Z"
DST_START_2018="2018-03-25T02:00:00Z"
DST_START_2019="2019-03-31T02:00:00Z"
DST_END_2012="2012-10-28T03:00:00Z"
DST_END_2013="2013-10-27T03:00:00Z"
DST_END_2014="2014-10-26T03:00:00Z"
DST_END_2015="2015-10-25T03:00:00Z"
DST_END_2016="2016-10-30T03:00:00Z"
DST_END_2017="2017-10-29T03:00:00Z"
DST_END_2018="2018-10-28T03:00:00Z"
DST_END_2019="2019-10-27T03:00:00Z"
service_g() {
	dateL="$(date)"
	if [ "$1" = "DaylightSavingsUsed" ]; then
		case "$dateL" in
		*"DST"*)
			echo true
			;;
		*"GMT"*)
			echo false
			;;
		*)
			echo false
			;;
		esac
	elif [ "$1" = "DaylightSavingsStart" ]; then
		case "$dateL" in
		*"2012"*)
			echo $DST_START_2012
			;;
		*"2013"*)
			echo $DST_START_2013
			;;
		*"2014"*)
			echo $DST_START_2014
			;;
		*"2015"*)
			echo $DST_START_2015
			;;
		*"2016"*)
			echo $DST_START_2016
			;;
		*"2017"*)
			echo $DST_START_2017
			;;
		*"2018"*)
			echo $DST_START_2018
			;;
		*"2019"*)
			echo $DST_START_2019
			;;
		*)
			echo $DST_START_2019
			;;
		esac
	elif [ "$1" = "DaylightSavingsEnd" ]; then
		case "$dateL" in
		*"2012"*)
			echo $DST_END_2012
			;;
		*"2013"*)
			echo $DST_END_2013
			;;
		*"2014"*)
			echo $DST_END_2014
			;;
		*"2015"*)
			echo $DST_END_2015
			;;
		*"2016"*)
			echo $DST_END_2016
			;;
		*"2017"*)
			echo $DST_END_2017
			;;
		*"2018"*)
			echo $DST_END_2018
			;;
		*"2019"*)
			echo $DST_END_2019
			;;
		*)
			echo $DST_END_2019
			;;
		esac
	fi
}
case "$op" in
g)
	for arg; do # Arg list as separate words
		service_g "$arg"
	done
	;;
esac
exit 0
