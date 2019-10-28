#!/bin/bash
#
# Copyright     2019 Tsinghua University (Author: Jiawen Kang)
#
# This script is called by ../run.sh, it is a outer script for
# subdata_by_dur.py and the do_filtering function is borrowed
# from ../utils/subset_data_dir.sh.
set -e

srcdir=$1
destdir=$2

function do_filtering {
  # assumes the utt2spk and spk2utt files already exist.
  [ -f $srcdir/feats.scp ] && utils/filter_scp.pl $destdir/utt2spk <$srcdir/feats.scp >$destdir/feats.scp
  [ -f $srcdir/vad.scp ] && utils/filter_scp.pl $destdir/utt2spk <$srcdir/vad.scp >$destdir/vad.scp
  [ -f $srcdir/dvad.scp ] && utils/filter_scp.pl $destdir/utt2spk <$srcdir/dvad.scp >$destdir/dvad.scp
  [ -f $srcdir/utt2lang ] && utils/filter_scp.pl $destdir/utt2spk <$srcdir/utt2lang >$destdir/utt2lang
  [ -f $srcdir/utt2dur ] && utils/filter_scp.pl $destdir/utt2spk <$srcdir/utt2dur >$destdir/utt2dur
  [ -f $srcdir/utt2num_frames ] && utils/filter_scp.pl $destdir/utt2spk <$srcdir/utt2num_frames >$destdir/utt2num_frames
  [ -f $srcdir/utt2uniq ] && utils/filter_scp.pl $destdir/utt2spk <$srcdir/utt2uniq >$destdir/utt2uniq
  [ -f $srcdir/wav.scp ] && utils/filter_scp.pl $destdir/utt2spk <$srcdir/wav.scp >$destdir/wav.scp
  [ -f $srcdir/spk2warp ] && utils/filter_scp.pl $destdir/spk2utt <$srcdir/spk2warp >$destdir/spk2warp
  [ -f $srcdir/utt2warp ] && utils/filter_scp.pl $destdir/utt2spk <$srcdir/utt2warp >$destdir/utt2warp
  [ -f $srcdir/text ] && utils/filter_scp.pl $destdir/utt2spk <$srcdir/text >$destdir/text
  [ -f $srcdir/spk2gender ] && utils/filter_scp.pl $destdir/spk2utt <$srcdir/spk2gender >$destdir/spk2gender
  # [ -f $srcdir/cmvn.scp ] && utils/filter_scp.pl $destdir/spk2utt <$srcdir/cmvn.scp >$destdir/cmvn.scp
  [ -f $srcdir/cmvn.scp ] && utils/filter_scp.pl $destdir/utt2spk <$srcdir/cmvn.scp >$destdir/cmvn.scp
  if [ -f $srcdir/segments ]; then
     utils/filter_scp.pl $destdir/utt2spk <$srcdir/segments >$destdir/segments
     awk '{print $2;}' $destdir/segments | sort | uniq > $destdir/reco # recordings.
     # The next line would override the command above for wav.scp, which would be incorrect.
     [ -f $srcdir/wav.scp ] && utils/filter_scp.pl $destdir/reco <$srcdir/wav.scp >$destdir/wav.scp
     [ -f $srcdir/reco2file_and_channel ] && \
       utils/filter_scp.pl $destdir/reco <$srcdir/reco2file_and_channel >$destdir/reco2file_and_channel

     # Filter the STM file for proper sclite scoring
     # Copy over the comments from STM file
     [ -f $srcdir/stm ] && grep "^;;" $srcdir/stm > $destdir/stm
     [ -f $srcdir/stm ] && utils/filter_scp.pl $destdir/reco < $srcdir/stm >> $destdir/stm

     rm $destdir/reco
  else
     awk '{print $1;}' $destdir/wav.scp | sort | uniq > $destdir/reco
     [ -f $srcdir/reco2file_and_channel ] && \
       utils/filter_scp.pl $destdir/reco <$srcdir/reco2file_and_channel >$destdir/reco2file_and_channel

     rm $destdir/reco
  fi
  srcutts=`cat $srcdir/utt2spk | wc -l`
  destutts=`cat $destdir/utt2spk | wc -l`
  echo "$0: reducing #utt from $srcutts to $destutts"
}


python local/subdata_by_dur.py $srcdir $destdir
echo "subdata $srcdir to $destdir"
utils/spk2utt_to_utt2spk.pl < $destdir/spk2utt > $destdir/utt2spk
do_filtering; # bash function
