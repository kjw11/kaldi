#!/bin/bash
# Copyright 2015   David Snyder
# Copyright 2018   Lantian Li
# Apache 2.0.
#
# This script trains LDA-PLDA models and does scoring.

use_existing_models=false
lda_dim=150
covar_factor=0.1
simple_length_norm=false # If true, replace the default length normalization
                         # performed in PLDA  by an alternative that
                         # normalizes the length of the iVectors to be equal
                         # to the square root of the iVector dimension.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 8 ]; then
  echo "Usage: $0 <plda-data-dir> <enroll-data-dir> <test-data-dir> <plda-xvec-dir> <enroll-xvec-dir> <test-xvec-dir> <trials-file> <scores-dir>"
fi

plda_data_dir=$1
enroll_data_dir=$2
test_data_dir=$3
plda_xvec_dir=$4
enroll_xvec_dir=$5
test_xvec_dir=$6
trials=$7
scores_dir=$8

if [ "$use_existing_models" == "true" ]; then
  for f in $plda_xvec_dir/mean.vec $plda_xvec_dir/lda_plda ; do
    [ ! -f $f ] && echo "No such file $f" && exit 1;
  done
else
  run.pl $plda_xvec_dir/log/compute_mean.log \
    ivector-mean scp:$plda_xvec_dir/xvector.scp \
    $plda_xvec_dir/mean.vec || exit 1;

  run.pl $plda_xvec_dir/log/lda.log \
    ivector-compute-lda --total-covariance-factor=$covar_factor --dim=$lda_dim \
    "ark:ivector-subtract-global-mean scp:$plda_xvec_dir/xvector.scp ark:- |" \
    ark:$plda_data_dir/utt2spk $plda_xvec_dir/transform_lda.mat || exit 1;

  run.pl $plda_xvec_dir/log/lda_plda.log \
    ivector-compute-plda ark:$plda_data_dir/spk2utt \
    "ark:ivector-subtract-global-mean scp:$plda_xvec_dir/xvector.scp ark:- | transform-vec $plda_xvec_dir/transform_lda.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
    $plda_xvec_dir/lda_plda || exit 1;
fi

mkdir -p $scores_dir/log

run.pl $scores_dir/log/lda_plda_scoring.log \
  ivector-plda-scoring --normalize-length=true \
    --num-utts=ark:${enroll_xvec_dir}/num_utts.ark \
    "ivector-copy-plda --smoothing=0.0 ${plda_xvec_dir}/lda_plda - |" \
    "ark:ivector-mean ark:$enroll_data_dir/spk2utt scp:$enroll_xvec_dir/xvector.scp ark:- | ivector-subtract-global-mean $plda_xvec_dir/mean.vec ark:- ark:- | transform-vec $plda_xvec_dir/transform_lda.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
    "ark:ivector-subtract-global-mean $plda_xvec_dir/mean.vec scp:$test_xvec_dir/xvector.scp ark:- | transform-vec $plda_xvec_dir/transform_lda.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
    "cat '$trials' | cut -d\  --fields=1,2 |" $scores_dir/lda_plda_scores || exit 1;
