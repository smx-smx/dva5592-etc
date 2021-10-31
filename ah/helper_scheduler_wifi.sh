#!/bin/sh
get_service_variable_from_enviroment() {
eval "$1"="$changedX_ADB_TimeSchedulerEnable"
eval "$2"="$newX_ADB_TimeSchedulerEnable"
eval "$3"="$changedX_ADB_TimeScheduler"
eval "$4"="$newX_ADB_TimeScheduler"
eval "$5"="$changedX_ADB_ServiceActivated"
eval "$6"="$newX_ADB_ServiceActivated"
}
