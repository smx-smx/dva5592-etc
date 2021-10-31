#!/bin/sh
pref=$1
fmt=$2
tagpri=$3
file=$4
size=$5
if [ $size ]
then
size=$(($size/512))
ulimit -f $size
fi
if [ $file ]
then
touch "/tmp/clish-log-""$$"".pid"
touch $file
fi
while true; do
timenow=`date +%s`
timenow=$(($timenow-1))
cmd="$pref $timenow $timenow $fmt $tagpri"
if [ $file ]
then
$cmd >> $file
else
$cmd
fi
if [ $? -ne 0 ]
then
rm "/tmp/clish-log-""$$"".pid"
sync
break
fi
sleep 1
done
