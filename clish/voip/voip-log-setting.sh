#!/bin/sh

. /etc/clish/clish-commons.sh


module=$1
loglevel=$2
command=$3

NONE=0
ERROR=1
WARNING=2
INFO=4
DEBUG=8
USR1=16
USR2=32
MESSAGE=$USR1
PROXYMESSAGE=$USR2

if [ "`pidof voip`" = "" ]; then
    echo "voip not running: log commands are not available"
    exit 0
fi

case "$module" in
    "CallManager" )
        modname=CM
    ;;
    "AnalogEndPoint" )
        modname=AEP
    ;;
    "DECT" )
        modname=DECT
    ;;
    "DigitalEndPoint" )
        modname=DEP
    ;;
    "HardwareAbstractionLayer" )
        modname=HAL
    ;;
    "Statistics" )
        modname=STATS
    ;;
    "VoIP" )
        modname=VoIP
    ;;
    "SIP" )
        modname=SIP
    ;;
    "FXO" )
        modname=FXO
    ;;
    "BSP" )
        if [ "$command" = "SET" ] ; then
            case "$loglevel" in
                "DEBUG" )
                    echo l ept 3 > /proc/bcmlog
                    echo l xdrv 3 > /proc/bcmlog
                    echo l xdrv_slic 3 > /proc/bcmlog
                    ;;
                "NONE"|"DEFAULT" )
                    echo l ept 0 > /proc/bcmlog
                    echo l xdrv 0 > /proc/bcmlog
                    echo l xdrv_slic 0 > /proc/bcmlog
                ;;
            esac
        fi
        exit 0
    ;;
    "OUTPUT" )
        output="$2"
        command="OUTPUT"
esac

if [ "$command" = "SET" ] ; then
    siplevel=0
    if [ "$modname" = "SIP" ]; then
        siplevel=`echo LOGLEVEL GET SIP | nc local:/tmp/voip_socket`
        siplevel=`printf "%d" 0x$siplevel`
        if [ "$siplevel" -gt "$MESSAGE" ]; then
            siplevel=$MESSAGE
        else
            siplevel=0
        fi
    fi
    messagename=""
    case "$loglevel" in
        "DEBUG" )
            newlevel=$((ERROR+WARNING+INFO+DEBUG))
        ;;
        "DEFAULT" )
            newlevel=$((ERROR+WARNING+INFO))
        ;;
         "PROXYMESSAGE" | "NOPROXYMESSAGE" )
            messagelevel=$PROXYMESSAGE
            messagename="PROXYMESSAGE"
        ;;
         "MESSAGE" | "NOMESSAGE" )
            messagelevel=$MESSAGE
            messagename="MESSAGE"
        ;;
        "NONE" )
            newlevel=0
        ;;
        "dummy" )
        ;;
    esac
    if [ "$messagename" != "" ]; then
        newlevel=`echo LOGLEVEL GET $modname | nc local:/tmp/voip_socket`
        newlevel=`printf "%d" 0x$newlevel`
        if [ "$loglevel" = "$messagename" ]; then
            siplevel=$messagelevel
        else
            if [ "$newlevel" = "$((newlevel|$messagelevel))" ]; then
                newlevel=$((newlevel-messagelevel))
            fi
            siplevel=0
        fi
    fi
    newlevel=$((newlevel|siplevel))
    newlevel=`printf "%X" $newlevel`

    echo LOGLEVEL SET $modname $newlevel | nc local:/tmp/voip_socket
elif [ "$command" = "GET" ] ; then
    oldlevel=`echo LOGLEVEL GET $modname | nc local:/tmp/voip_socket`
    oldlevel=`printf "%d" 0x$oldlevel`
    oldstring=""
    if [ "$oldlevel" = "0" ] ; then
        oldstring=NONE
    else
        if [ "$oldlevel" -ge "$USR1" ] ; then
            oldstring="$oldstring MESSAGE"
            oldlevel=$((oldlevel-MESSAGE))
        fi
        if [ "$oldlevel" -ge "$DEBUG" ] ; then
            oldstring="$oldstring DEBUG"
            oldlevel=$((oldlevel-DEBUG))
        fi
        if [ "$oldlevel" -ge "$INFO" ] ; then
            oldstring="$oldstring INFO"
            oldlevel=$((oldlevel-INFO))
        fi
        if [ "$oldlevel" -ge "$WARNING" ] ; then
            oldstring="$oldstring WARNING"
            oldlevel=$((oldlevel-WARNING))
        fi
        if [ "$oldlevel" -ge "$ERROR" ] ; then
            oldstring="$oldstring ERROR"
        fi
    fi
    echo "Current LOGLEVEL for module $module is: $oldstring"
elif [ "$command" = "OUTPUT" ] ; then
    if [ "$output" != "CONSOLE" ]; then
       output="SYSLOG"
    fi
    echo LOGOUTPUT SET "$output" | nc local:/tmp/voip_socket
fi

