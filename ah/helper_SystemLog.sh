#!/bin/sh
help_systemlog_lvol_online_change()
{
local lvobj="$1"
cmclient SET Device.X_ADB_SystemLog.FileLogging.[Enable=true].[StorageVolume=$lvobj].Enable true
}
