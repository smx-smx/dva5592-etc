#!/bin/sh
. /etc/ah/Printer-Common.sh
sleep 5
printer_job_delete "$1"
exit 0
