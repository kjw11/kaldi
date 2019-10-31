#!/bin/bash
#
# Copyrigh	2019 Tsinghua University (Author: Jiawen Kang) 
#
# This is a data preparation script for CN-Celeb database. It creats train, 
# eval_enroll, eval_test directories for model training and evaluation. 
# Note that we randomly subset 20s speech for each speaker as enrollment.

set -e

corpus_dir=`readlink -f $1`
dir=`readlink -f $2`

if [ $# != 2 ]; then
  echo "Usage: make_cnceleb.sh <corpus_dir> <dest_dir>"
  echo "E.g.: make_cnceleb.sh /database/CN-Celeb data"
  exit 1;
fi

cd $dir

if [ ! -d $dir/data ]; then
  echo "creating data/{train,eval}"
  mkdir -p $dir/data/{train,eval}
else
  for x in train eval;do
    echo "cleaning data/$x"
    rm -rf $dir/data/$x/*
  done
fi

(
n=0
# clean old files

echo "preparing scp file"
for sub in "CN-Celeb(E)" "CN-Celeb(T)"; do
  curdir=$corpus_dir/${sub}
  if [ ${sub} = "CN-Celeb(E)" ]; then
    cd $dir/data/eval
  else
    cd $dir/data/train
  fi

  for name in `ls $curdir | sort -u | xargs -I {} basename {}`; do
    #make id for each speaker
    spkid=$name

    for utt in `ls $curdir/$name | sort -u  | xargs -I {} basename {} .wav`; do
      sceid=`echo $utt | awk -F"-" '{print "" $1}'`
      uttid1=`echo $utt | awk -F"-" '{print "" $2}'`
      uttid2=`echo $utt | awk -F"-" '{print "" $3}'`
      uttid=$(printf '%s_%s_%s' "$sceid" "$uttid1" "$uttid2")
      echo ${spkid}_${uttid} $curdir/$name/$utt.wav >> wav.scp
      echo ${spkid}_${uttid} $spkid >> utt2spk
    done

    echo $spkid $name >> spkid2name

    n=$[n+1]
    sort wav.scp -o wav.scp
    sort utt2spk -o utt2spk
  done
  
done
) || exit 1

# make spk2utt
utils/utt2spk_to_spk2utt.pl $dir/data/train/utt2spk > $dir/data/train/spk2utt
utils/utt2spk_to_spk2utt.pl $dir/data/eval/utt2spk > $dir/data/eval/spk2utt

# subdata eval_test and eval_enroll
rm -rf $dir/data/eval_test $dir/data/eval_enroll
mkdir $dir/data/eval_enroll
local/subdata_by_dur.sh $dir/data/eval $dir/data/eval_enroll
utils/fix_data_dir.sh $dir/data/eval_enroll
utils/filter_scp.pl --exclude $dir/data/eval_enroll/wav.scp \
  $dir/data/eval/wav.scp > $dir/data/eval/wav.scp.rest
mv $dir/data/eval/wav.scp.rest $dir/data/eval/wav.scp
utils/fix_data_dir.sh $dir/data/eval
mv $dir/data/eval $dir/data/eval_test

#make trials
python local/prepare_trials.py $dir/data/eval_enroll $dir/data/eval_test
