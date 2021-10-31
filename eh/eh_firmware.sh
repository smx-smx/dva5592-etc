#!/bin/sh
#nl:add,firmware,*
FIRM_PATH=/lib/firmware
firmware="$OBJ"
devpath="$A1"
file=$FIRM_PATH/$firmware
if [ ! -f $file ]; then
echo "-1" > /sys${devpath}/loading
exit 1
fi
echo "Loading firmware ${file} to /sys${devpath}"
echo "1" > /sys${devpath}/loading
cat $file > /sys${devpath}/data
echo "0" > /sys${devpath}/loading
