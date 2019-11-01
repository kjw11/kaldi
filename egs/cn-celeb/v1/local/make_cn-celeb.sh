#!/bin/bash
#
# Copyrigh	2019 Tsinghua University (Author: Jiawen Kang) 
# Apache 2.0.
#
# This is a data preparation script for CN-Celeb database. It creats train, 
# eval_enroll, eval_test directories for model training and evaluation. 
# Note that we randomly subset 20s speech for each speaker as enrollment.

set -e

train_list=local/train_id_list
eval_list=local/eval_id_list
random_enroll=false

# config n_job, to make this script run in parallel
nj=10
tmp_fifofile="/tmp/$$.fifo" #pipeline file
mkfifo "$tmp_fifofile"

echo "$0 $@"

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
  echo "Usage: $0 <corpus_dir> <dest_dir>"
  echo "E.g.: $0 /database/CN-Celeb data"
  echo "Options:"
  echo "--train-list <train-list>>	:choose training id list file. Default: local/train_id_list"
  echo "--eval-list <eval-liat>		:choose evaluation id list file. Default: local/eval_id_list"
  exit 1;
fi

corpus_dir=`readlink -f $1`
dir=`readlink -f $2`

required="local/subdata_by_dur.py local/prepare_trials.py local/subdata_by_dur.sh $train_list $eval_list"

for file in $required; do
  if [ ! -e $file ]; then
    echo "$0: no such file $file"
    exit 1;
  fi
done

cd $dir

# make directory
if [ ! -d $dir/data ]; then
  echo "creating data/{train,eval}"
  mkdir -p $dir/data/{train,eval}
else
  rm -r $dir/data
  echo "cleaning data/$x"
  mkdir -p $dir/data/{train,eval}
fi

# preparing files 
for list in `readlink -f $train_list` `readlink -f $eval_list`; do
  if [[ $list =~ train ]]; then
    cd $dir/data/train
  else
    cd $dir/data/eval
  fi
  
  # associate descriptor 6 and pipeline file
  # add blank line to pipeline file
  exec 6<>"$tmp_fifofile"
  for ((i=0;i<$nj;i++));do
    echo
  done >&6

  # preparing scp file
  for spk in `cat $list`; do
    read -u6  # read line from pipeline file
    {
    spkid=$spk
    for utt in `ls $corpus_dir/data/$spk | sort -u  | xargs -I {} basename {} .wav`; do
      sceid=`echo $utt | awk -F"-" '{print "" $1}'`
      uttid1=`echo $utt | awk -F"-" '{print "" $2}'`
      uttid2=`echo $utt | awk -F"-" '{print "" $3}'`
      uttid=$(printf '%s_%s_%s' "$sceid" "$uttid1" "$uttid2")

      # wav.scp
      echo ${spkid}_${uttid} $corpus_dir/data/$spkid/$utt.wav >> wav.scp

      # utt2spk
      echo ${spkid}_${uttid} $spkid >> utt2spk
    done

    # write blank line
    echo "" >&6
    } &  # running in subshell
  done
    
  wait  # waiting for subshell
  exec 6>&-  # delete descriptor 

  sort wav.scp -o wav.scp
  sort utt2spk -o utt2spk
done

cd $dir

# make spk2utt
utils/utt2spk_to_spk2utt.pl $dir/data/train/utt2spk > $dir/data/train/spk2utt
utils/utt2spk_to_spk2utt.pl $dir/data/eval/utt2spk > $dir/data/eval/spk2utt

# subdata eval_test and eval_enroll
rm -rf $dir/data/eval_test $dir/data/eval_enroll
mkdir $dir/data/eval_enroll

# subdata by duration, do not randomly enroll
local/subdata_by_dur.sh $dir/data/eval $dir/data/eval_enroll --random $random_enroll

# fix files
utils/fix_data_dir.sh $dir/data/eval_enroll
utils/filter_scp.pl --exclude $dir/data/eval_enroll/wav.scp \
  $dir/data/eval/wav.scp > $dir/data/eval/wav.scp.rest
mv $dir/data/eval/wav.scp.rest $dir/data/eval/wav.scp
utils/fix_data_dir.sh $dir/data/eval
mv $dir/data/eval $dir/data/eval_test

# make trials
python local/prepare_trials.py $dir/data/eval_enroll $dir/data/eval_test
