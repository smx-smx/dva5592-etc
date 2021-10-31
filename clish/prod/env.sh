#!/bin/sh
wlctl () {
case "$1" in
down)	ledctl wlan off	> /dev/null 2>&1 ;;
up)	ledctl wlan on	> /dev/null 2>&1 ;;
esac
/bin/wlctl "$@"
}
