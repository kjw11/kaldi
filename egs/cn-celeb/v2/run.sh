#!/bin/bash
#
# Copyright     2019 Tsinghua University (Author: Jiawen Kang)
#
# Apache 2.0.
#
# This is a x-vector baseline script for CN-Celeb database.
# Each speaker enrolled with as least 20s audio without singing 
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

scores_dir=$dest_dir/scores
trials=data/eval_test/trials
nnet_dir=exp/xvector_nnet_1a
egs_dir=exp/xvector_nnet_1a/egs

lda_dim=150

stage=0

if [ $stage -le 0 ]; then
  # Data preparation:
  # We use default training and evaluation speaker list (in local/)
  # whose test set has been checked to meeting the requirement
  # of our enrollment strategy (stated in the top of this script). 
  local/make_cn-celeb.sh --train-list local/train_id_list \
                         --eval-list local/eval_id_list \
                         $corpus_dir $dest_dir
  datadir=$dest_dir/data
  echo "Finish data preparation"
fi

datadir=$dest_dir/data

if [ $stage -le 1 ]; then
  # Get features
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
  # works on feats.scp file and do not regenerate vad.scp file. we
  # copy out a "train_mfcc" directory with mfcc features, which make 
  # combination process to generate vad.scp file for the "train" 
  # directory with fbank features.
  cp -r $datadir/train $datadir/train_mfcc
  # Get fbank feature for "train" directory
  steps/make_fbank.sh --fbank-config conf/fbank.conf \
                      --nj 20 --cmd "$cmd" \
                      $datadir/train exp/make_fbank $fbankdir
  utils/fix_data_dir.sh $datadir/train
  # Combine short segments, both on mfcc and fbank features
  local/combine_short_segments.sh $datadir/train 5 $datadir/train_comb
  local/combine_short_segments.sh $datadir/train_mfcc 5 $datadir/train_comb_mfcc
 
  # Get vad using mfcc in "train_comb_mfcc"
  sid/compute_vad_decision.sh --vad-config conf/vad.conf \
      --nj 20 --cmd "$cmd" \
      $datadir/train_comb_mfcc exp/make_vad $vaddir
  utils/fix_data_dir.sh $datadir/train_comb_mfcc 
  # Calculate utt2num_frames
  feat-to-len scp:$datadir/train_comb/feats.scp ark,t:$datadir/train_comb/utt2num_frames  
  # Copy vad.scp for "train_comb", which use fbank features
  cp $datadir/train_comb_mfcc/vad.scp $datadir/train_comb/
fi

if [ $stage -le 3 ]; then
  # Remove silence
  local/nnet3/xvector/prepare_feats_for_egs.sh --nj 20 --cmd "$train_cmd" \
      $datadir/train_comb $datadir/train_comb_no_sil exp/train_comb_no_sil
  utils/fix_data_dir.sh $datadir/train_comb_no_sil
    
  # Remove spker with fewer than 8 utterances.
  min_num_utts=8
  awk '{print $1, NF-1}' $datadir/train_comb_no_sil/spk2utt > $datadir/train_comb_no_sil/spk2num
  awk -v min_num_utts=${min_num_utts} '$2 >= min_num_utts {print $1, $2}' $datadir/train_comb_no_sil/spk2num | utils/filter_scp.pl - $datadir/train_comb_no_sil/spk2utt > $datadir/train_comb_no_sil/spk2utt.new
  mv $datadir/train_comb_no_sil/spk2utt.new $datadir/train_comb_no_sil/spk2utt
  utils/spk2utt_to_utt2spk.pl $datadir/train_comb_no_sil/spk2utt > $datadir/train_comb_no_sil/utt2spk

  utils/filter_scp.pl $datadir/train_comb_no_sil/utt2spk $datadir/train_comb_no_sil/utt2num_frames > $datadir/train_comb_no_sil/utt2num_frames.new
  mv $datadir/train_comb_no_sil/utt2num_frames.new $datadir/train_comb_no_sil/utt2num_frames
  utils/fix_data_dir.sh $datadir/train_comb_no_sil
  
  # Remove short utterances 
  min_len=400
  mv $datadir/train_comb_no_sil/utt2num_frames $datadir/train_comb_no_sil/utt2num_frames.bak
  awk -v min_len=${min_len} '$2 > min_len {print $1, $2}' $datadir/train_comb_no_sil/utt2num_frames.bak > $datadir/train_comb_no_sil/utt2num_frames
  utils/filter_scp.pl $datadir/train_comb_no_sil/utt2num_frames $datadir/train_comb_no_sil/utt2spk > $datadir/train_comb_no_sil/utt2spk.new
  mv $datadir/train_comb_no_sil/utt2spk.new $datadir/train_comb_no_sil/utt2spk
  utils/fix_data_dir.sh $datadir/train_comb_no_sil
fi
  
if [ $stage -le 4 ]; then
  # Train xvector net
  local/nnet3/xvector/run_xvector.sh   \
      --data $datadir/train_comb_no_sil --nnet-dir $nnet_dir \
      --egs-dir $egs_dir
fi

if [ $stage -le 5 ]; then
  # Extract xvector 
  for sub in train_comb eval_enroll eval_test; do
    sid/nnet3/xvector/extract_xvectors.sh --cmd "$cmd" --nj 20 \
                          $nnet_dir $datadir/${sub} \
                          exp/xvectors_${sub}_tdnn6.affine
  done
fi
 
if [ $stage -le 6 ]; then 
  # LDA_PLDA scoring
  local/lda_plda_scoring.sh --lda-dim $lda_dim --covar-factor 0.0 \
                         $datadir/train_comb $datadir/eval_enroll \
                         $datadir/eval_test exp/xvectors_train_comb_tdnn6.affine \
                         exp/xvectors_eval_enroll_tdnn6.affine \
                         exp/xvectors_eval_test_tdnn6.affine $trials \
                         $scores_dir
  # Calculate EER 
  eer=$(paste $trials ${scores_dir}/lda_plda_scores | awk '{print $6, $3}' | compute-eer - 2>/dev/null)
  echo " LDA_PLDA EER= $eer%"  
fi



