#!/bin/sh
cmclient -v cliPrompt  GETV Device.Users.User.[Username="$USER"].X_ADB_CLIPrompt
cmclient -v cliLang    GETV Device.UserInterface.CurrentLanguage
[ -n "$cliPrompt" ] &&  export CLISH_PROMPT="$cliPrompt" || export CLISH_PROMPT="ADB"
export CLISH_LANGUAGE="$cliLang"
exec /bin/clish.elf
