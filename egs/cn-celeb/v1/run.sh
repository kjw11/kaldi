#!/bin/bash
#
# Copyright	2019 Tsinghua University (Author: Jiawen Kang)	
#
# This is a i-vector baseline system script for CN-Celeb database.
# Each speaker enrolled with as least 20s audio withou singing
# utterances, and the short segments (less than 5 seconds) in
# training data are combined to train PLDA model.

. ./cmd.sh
. ./path.sh
set -e

dest_dir=`pwd`
corpus_dir=/work9/cslt/kangjiawen/database/CN-Celeb

mfccdir=`pwd`/_mfcc
vaddir=`pwd`/_vad

name=cn-celeb
scores_dir=$dest_dir/scores_$name
trials=$dest_dir/data/eval_test/trials

lda_dim=150
cnum=2048
civ=400

stage=0

if [ $stage -le 0 ]; then
  # data preparation
  # we make sure each speaker has at least 20s speech for enrollment,
  # and singing utterances are not included.
  local/make_cn-celeb.sh $corpus_dir $dest_dir
  datadir=$dest_dir/data
  echo "Finish data preparation."
fi

datadir=$dest_dir/data

if [ $stage -le 1 ]; then
  # get features
  for sub in train eval_enroll eval_test; do
    steps/make_mfcc.sh --write-utt2num-frames true --mfcc-config conf/mfcc.conf \
      --nj 20 --cmd "$cmd" \
      $datadir/$sub exp/make_mfcc $mfccdir
    utils/fix_data_dir.sh $datadir/$sub

    sid/compute_vad_decision.sh --vad-config conf/vad.conf \
      --nj 20 --cmd "$cmd" \
      $datadir/$sub exp/make_vad $vaddir
    utils/fix_data_dir.sh $datadir/$sub
  done
fi

if [ $stage -le 2 ]; then
  # Train the UBM
  sid/train_diag_ubm.sh --cmd "$train_cmd" \
    --nj 20 --num-threads 1 \
    $datadir/train $cnum \
    exp/diag_ubm_${cnum}

  sid/train_full_ubm.sh --cmd "$train_cmd" \
    --nj 20 --remove-low-count-gaussians false \
    $datadir/train \
    exp/diag_ubm_${cnum} exp/full_ubm_${cnum}
fi

if [ $stage -le 3 ]; then
  # Train the i-vector extractor.
  sid/train_ivector_extractor.sh --nj 20 --cmd "$iv_cmd" --ivector-dim $civ \
    --num-iters 5 --num-threads 1 --num-processes 1 \
    exp/full_ubm_${cnum}/final.ubm \
    $datadir/train \
    exp/extractor_${cnum}_${civ}
fi

if [ $stage -le 4 ]; then
  # extract i-vector
  for sub in train eval_enroll eval_test; do
    sid/extract_ivectors.sh --cmd "$cmd" --nj 20 \
      exp/extractor_${cnum}_${civ} $datadir/${sub} \
      exp/ivectors_${name}_${sub}
  done
fi

if [ $stage -le 5 ]; then
  # combine the short utterance less than 5 seconds,i
  # and calculate utt2num_frames.
  local/combine_short_segments.sh $datadir/train 5 $datadir/train_comb
  feat-to-len scp:$datadir/train_comb/feats.scp ark,t:$datadir/train_comb/utt2num_frames
  
  # get vad.scp
  sid/compute_vad_decision.sh --vad-config conf/vad.conf \
      --nj 20 --cmd "$cmd" \
      $datadir/train_comb exp/make_vad $vaddir
  utils/fix_data_dir.sh $datadir/train_comb
fi

if [ $stage -le 6 ]; then 
  # get ivector for combined training data
    sid/extract_ivectors.sh --cmd "$cmd" --nj 20 \
                          exp/extractor_${cnum}_${civ} $datadir/train_comb \
                          exp/ivectors_${name}_train_comb
fi

if [ $stage -le 7 ]; then
  # train plda with conbined training data, and get LDA_PLDA scores.
  local/lda_plda_scoring.sh --lda-dim $lda_dim --covar-factor 0.0\
                         $datadir/train_comb $datadir/eval_enroll \
                         $datadir/eval_test exp/ivectors_${name}_train_comb \
                         exp/ivectors_${name}_eval_enroll \
                         exp/ivectors_${name}_eval_test $trials $scores_dir
  eer=$(paste $trials ${scores_dir}/lda_plda_scores | awk '{print $6, $3}' | compute-eer - 2>/dev/null)
  echo " LDA_PLDA EER= $eer%"
  
  # calculate cosine scores.
  local/cosine_scoring.sh $datadir/eval_enroll $datadir/eval_test \
                         exp/ivectors_${name}_eval_enroll \
                         exp/ivectors_${name}_eval_test \
                         $trials $scores_dir
  eer=$(paste $trials $scores_dir/cosine_scores | awk '{print $6, $3}' | compute-eer - 2>/dev/null)
  echo "CosineEER: $eer%" 
fi




