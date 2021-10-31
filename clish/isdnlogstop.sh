#!/bin/sh
FILE_DEC_CONF="/etc/tslink3/IsdnDecode.conf"
echo -e "#layer &lt; 0 , 1 , 2 , 3 &gt; verbosity &lt; no_verb, low, medium, high &gt;\nlayer 0 verbosity no_verb\nlayer 1 verbosity no_verb\nlayer 2 verbosity no_verb\nlayer 3 verbosity no_verb" > $FILE_DEC_CONF
base="/tmp/clish-isdnLog-"
pidfilelist=`ls $base* 2> /dev/null`
pids=`echo $pidfilelist | sed 's/[^0-9 ]//g'`
if [ -n "$pids" ]
then
kill $pids 2> /dev/null
rm $pidfilelist 2> /dev/null
sync
else
echo "There are no processes to stop."
fi
