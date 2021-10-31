#!/bin/sh

# Function   : get_peer
# Parameters : obj that can be a CallControl.Extension object
#              or a CallControl.Line object
# Description
# This function translates input parameter in its object name with
# the following rules:
# * a CallControl Line object in its related Directory number
# * a CallControl Extension object in its name or if the
#   provider is a group, in the list of names belonging to the
#   group

get_peer() {
   local peer provider exts name

   case "$1" in
   *"Extension"*)
       cmclient -v provider GETV $1.Provider
       case "$provider" in
       *"Group"*)
           IFS=","
           cmclient -v exts GETV "${provider}.Extensions"
           peer=""
           for ext in $exts; do
               cmclient -v name GETV $ext.Name
               peer=${peer:+$peer,}$name
           done
           unset IFS
           ;;
       *)
           cmclient -v peer GETV $1.Name
           ;;
       esac
       ;;
   *"Line"*)
       cmclient -v provider GETV $1.Provider
       cmclient -v peer GETV $provider.DirectoryNumber
       ;;
   *)
       peer=""
   esac
   echo $peer
}

#Remove X_ADB_ if present in order to be readable
cause=${cause#X_ADB_}
cmclient -v callobjs GETO Device.Services.VoiceService.1.CallLog
for callobj in $callobjs; do
   cmclient -v calling  GETV $callobj.CallingPartyNumber
   cmclient -v called   GETV $callobj.CalledPartyNumber
   cmclient -v dir      GETV $callobj.Direction
   cmclient -v start    GETV $callobj.Start
   cmclient -v duration GETV $callobj.Duration
   cmclient -v cause    GETV $callobj.CallTerminationCause

   cmclient -v extcount GETV Device.Services.VoiceService.1.Capabilities.MaxExtensionCount
   # be sure not empty
   [ "$extcount" = "" ] && extcount=0
   printf "$dir call   : Calling=$calling Called=$called TerminationCause $cause\n"
   printf "                : Start=$start Duration=$duration\n"
   # if extcount not equal 0 : callcontrol is present. Make sense show source and destination
   if [ $extcount -ne 0 ]; then
      cmclient -v Obj   GETV $callobj.Source
      source=`get_peer $Obj`
      cmclient -v Obj   GETV $callobj.Destination
      dest=`get_peer $Obj`
      printf "                  Source=$source Destination $dest\n"
   fi
   cmclient -v sessobjs GETO ${callobj}.Session
   for sessobj in $sessobjs; do
      cmclient -v stype GETV $sessobj.StreamType
      cmclient -v start GETV $sessobj.Start
      cmclient -v duration GETV $sessobj.Duration
      cmclient -v sid GETV $sessobj.SessionID
      printf "Session         : Type=$stype Start=$start Duration=$duration SessionId=$sid\n"
      cmclient -v farendip GETV $sessobj.Source.RTP.FarEndIPAddress
      cmclient -v farendport GETV $sessobj.Source.RTP.FarEndUDPPort
      cmclient -v localport GETV $sessobj.Source.RTP.LocalUDPPort
      printf "                : LocalPort=$localport Remote=${farendip}:${farendport}\n"
      cmclient -v pktrcv  GETV $sessobj.Source.RTP.PacketsReceived
      cmclient -v pktsent GETV $sessobj.Source.RTP.PacketsSent
      cmclient -v pktlost GETV $sessobj.Source.RTP.PacketsLost
      cmclient -v bytesrcv GETV $sessobj.Source.RTP.BytesReceived
      cmclient -v bytessent GETV $sessobj.Source.RTP.BytesSent

      cmclient -v rcvlossrate GETV $sessobj.Source.RTP.ReceivePacketLossRate
      cmclient -v farendlossrate GETV $sessobj.Source.RTP.FarEndPacketLossRate

      cmclient -v rcvj GETV $sessobj.Source.RTP.ReceiveInterarrivalJitter
      cmclient -v farj GETV $sessobj.Source.RTP.FarEndInterarrivalJitter
      cmclient -v rtd GETV $sessobj.Source.RTP.RoundTripDelay

      cmclient -v avgrcvj GETV $sessobj.Source.RTP.AverageReceiveInterarrivalJitter
      cmclient -v avgfarj GETV $sessobj.Source.RTP.AverageFarEndInterarrivalJitter
      cmclient -v avgrtd GETV $sessobj.Source.RTP.AverageRoundTripDelay

      cmclient -v sample GETV $sessobj.Source.RTP.SamplingFrequency
      printf "Packets         : Received=$pktrcv Sent=$pktsent Lost=$pktlost\n"
      printf "Bytes           : Received=$bytesrcv Sent=$bytessent\n"
      printf "Packet loss rate: Receive=$rcvlossrate%% FarEnd=$farendlossrate%%\n"
      printf "Jitter          : Receive=$rcvj [Average=$avgrcvj] - FarEnd=$farj [Average=$avgfarj] in ts eq 125 us\n"
      printf "RoundTripDelay  : $rtd [Average=$avgrtd] us\n"
      printf "Sample          : $sample\n"
      cmclient -v codecobj GETV $sessobj.Source.DSP.ReceiveCodec.Codec
      cmclient -v rcvcodecname GETV $codecobj.Codec
      cmclient -v codecobj GETV $sessobj.Source.DSP.TransmitCodec.Codec
      cmclient -v trascodecname GETV $codecobj.Codec
      cmclient -v ssup GETV $sessobj.Source.DSP.TransmitCodec.SilenceSuppression
      cmclient -v ptime GETV $sessobj.Source.DSP.TransmitCodec.PacketizationPeriod
      printf "Codec           : Receive=$rcvcodecname Transmit=$trascodecname:$ptime SilenceSuppression=$ssup\n"
   done
   printf "--------------------------------------------------------------------------------\n"
done
