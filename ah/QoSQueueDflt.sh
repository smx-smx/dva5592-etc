#!/bin/sh
for instance in `cmclient GETO Device.QoS.Queue.` 
do
nop=$instance
done
echo $instance
