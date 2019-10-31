#!/bin/bash
#
# Copyright     2019 Tsinghua University (Author: Jiawen Kang)
#
# This is a x-vector baseline system script for CN-Celeb database.
# Each speaker enrolled with as least 20s audio withou singing 
# utterances, and the short segments (less than 5 seconds) in 
# training data are combined to improve traning effect.

. ./cmd.sh
. ./path.sh

set -e

dest_dir=`pwd`
corpus_dir=/work9/cslt/kangjiawen/database/CN-Celeb

mfccdir=`pwd`/_mfcc
vaddir=`pwd`/_vad
fbankdir=`pwd`/_fbank

name=cn-celeb
scores_dir=$dest_dir/scores_$name
trials=data/eval_test/trials
nnet_dir=exp/xvector_nnet_1a
egs_dir=exp/xvector_nnet_1a/egs

lda_dim=150

stage=5

if [ $stage -le 0 ]; then
  # data preparation
  # we make sure each speaker has at least 20s speech for enrollment,
  # and singing utterances are not included.
  local/make_cn-celeb.sh $corpus_dir $dest_dir
  datadir=$dest_dir/data
  echo "data preparation finished!"
fi

datadir=$dest_dir/data

if [ $stage -le 1 ]; then
  # get features
  # In this step, we do not calculate fbank feature for training data.
  for sub in train; do
    steps/make_mfcc.sh --write-utt2num-frames true --mfcc-config conf/mfcc.conf \
        --nj 20 --cmd "$cmd" \
        $datadir/$sub exp/make_mfcc $mfccdir
    utils/fix_data_dir.sh $datadir/$sub

    sid/compute_vad_decision.sh --vad-config conf/vad.conf \
        --nj 20 --cmd "$cmd" \
        $datadir/$sub exp/make_vad $vaddir
    utils/fix_data_dir.sh $datadir/$sub
  done

  for sub in eval_enroll eval_test; do
    steps/make_mfcc.sh --write-utt2num-frames true --mfcc-config conf/mfcc.conf \
        --nj 20 --cmd "$cmd" \
        $datadir/$sub exp/make_mfcc $mfccdir
    utils/fix_data_dir.sh $datadir/$sub

    sid/compute_vad_decision.sh --vad-config conf/vad.conf \
        --nj 20 --cmd "$cmd" \
        $datadir/$sub exp/make_vad $vaddir
    utils/fix_data_dir.sh $datadir/$sub

    steps/make_fbank.sh --fbank-config conf/fbank.conf \
        --nj 20 --cmd "$cmd" \
        $datadir/$sub exp/make_fbank $fbankdir
    utils/fix_data_dir.sh $datadir/$sub
  done
fi

if [ $stage -le 2 ]; then
  # In this step, we do data combination. Note that the combination
  # works on feats.scp file and without regenerating vad.scp file,
  # we cp a train_mfcc directory with mfcc feature, which also dose 
  # combination process to generates vad.scp file used for fank feature data.
  cp -r $datadir/train $datadir/train_mfcc
  # get fbank feature for train
  steps/make_fbank.sh --fbank-config conf/fbank.conf \
                      --nj 20 --cmd "$cmd" \
                      $datadir/train exp/make_fbank $fbankdir
  utils/fix_data_dir.sh $datadir/train
  # combine short segments, both mfcc and kbank feature
  local/combine_short_segments.sh $datadir/train 5 $datadir/train_comb
  local/combine_short_segments.sh $datadir/train_mfcc 5 $datadir/train_comb_mfcc
 
  # get vad using mfcc in train_comb_mfcc
  sid/compute_vad_decision.sh --vad-config conf/vad.conf \
      --nj 20 --cmd "$cmd" \
      $datadir/train_comb_mfcc exp/make_vad $vaddir
  utils/fix_data_dir.sh $datadir/train_comb_mfcc 
  # calculate utt2num_frames
  feat-to-len scp:$datadir/train_comb/feats.scp ark,t:$datadir/train_comb/utt2num_frames  
  #copy vad.scp for train_comb, which has fbank feature
  cp $datadir/train_comb_mfcc/vad.scp $datadir/train_comb/
fi

if [ $stage -le 3 ]; then
  #remove silence
  local/nnet3/xvector/prepare_feats_for_egs.sh --nj 20 --cmd "$train_cmd" \
      $datadir/train_comb $datadir/train_comb_no_sil exp/train_comb_no_sil
  utils/fix_data_dir.sh $datadir/train_comb_no_sil
    
  #remove spker with fewer than 8 utterances.
  min_num_utts=8
  awk '{print $1, NF-1}' $datadir/train_comb_no_sil/spk2utt > $datadir/train_comb_no_sil/spk2num
  awk -v min_num_utts=${min_num_utts} '$2 >= min_num_utts {print $1, $2}' $datadir/train_comb_no_sil/spk2num | utils/filter_scp.pl - $datadir/train_comb_no_sil/spk2utt > $datadir/train_comb_no_sil/spk2utt.new
  mv $datadir/train_comb_no_sil/spk2utt.new $datadir/train_comb_no_sil/spk2utt
  utils/spk2utt_to_utt2spk.pl $datadir/train_comb_no_sil/spk2utt > $datadir/train_comb_no_sil/utt2spk

  utils/filter_scp.pl $datadir/train_comb_no_sil/utt2spk $datadir/train_comb_no_sil/utt2num_frames > $datadir/train_comb_no_sil/utt2num_frames.new
  mv $datadir/train_comb_no_sil/utt2num_frames.new $datadir/train_comb_no_sil/utt2num_frames
  utils/fix_data_dir.sh $datadir/train_comb_no_sil
  
  # remove short utt 
  min_len=400
  mv $datadir/train_comb_no_sil/utt2num_frames $datadir/train_comb_no_sil/utt2num_frames.bak
  awk -v min_len=${min_len} '$2 > min_len {print $1, $2}' $datadir/train_comb_no_sil/utt2num_frames.bak > $datadir/train_comb_no_sil/utt2num_frames
  utils/filter_scp.pl $datadir/train_comb_no_sil/utt2num_frames $datadir/train_comb_no_sil/utt2spk > $datadir/train_comb_no_sil/utt2spk.new
  mv $datadir/train_comb_no_sil/utt2spk.new $datadir/train_comb_no_sil/utt2spk
  utils/fix_data_dir.sh $datadir/train_comb_no_sil
fi
  
if [ $stage -le 4 ]; then
  #train xvector net
  local/nnet3/xvector/run_xvector.sh   \
      --data $datadir/train_comb_no_sil --nnet-dir $nnet_dir \
      --egs-dir $egs_dir
fi

if [ $stage -le 5 ]; then
  # extract xvector 
  for sub in train_comb eval_enroll eval_test; do
    sid/nnet3/xvector/extract_xvectors.sh --cmd "$cmd" --nj 20 \
                          $nnet_dir $datadir/${sub} \
                          exp/xvectors_${name}_${sub}_tdnn6.affine
  done
fi
 
if [ $stage -le 6 ]; then 
  # lda_plda scoring
  local/lda_plda_scoring.sh --lda-dim $lda_dim --covar-factor 0.0 \
                         $datadir/train_comb $datadir/eval_enroll \
                         $datadir/eval_test exp/xvectors_${name}_train_comb_tdnn6.affine \
                         exp/xvectors_${name}_eval_enroll_tdnn6.affine \
                         exp/xvectors_${name}_eval_test_tdnn6.affine $trials \
                         $scores_dir
  eer=$(paste $trials ${scores_dir}/lda_plda_scores | awk '{print $6, $3}' | compute-eer - 2>/dev/null)
  echo " LDA_PLDA EER= $eer%"
  
  # cosine scoring
  local/cosine_scoring.sh $datadir/eval_enroll $datadir/eval_test \
                         exp/xvectors_${name}_eval_enroll_tdnn6.affine \
                         exp/xvectors_${name}_eval_test_tdnn6.affine \
                         $trials $scores_dir

  cosine_eer=$(paste $trials $scores_dir/cosine_scores | awk '{print $6, $3}' | compute-eer - 2>/dev/null)
  echo "CosineEER: $cosine_eer%"
fi



