#!/bin/bash
# Copyright 2015   David Snyder
# Copyright 2018   Lantian Li
# Apache 2.0.
#
# This script trains PCA-PLDA models and does scoring.

use_existing_models=false
pca_dim=150
simple_length_norm=false # If true, replace the default length normalization
                         # performed in PLDA  by an alternative that
                         # normalizes the length of the iVectors to be equal
                         # to the square root of the iVector dimension.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 8 ]; then
  echo "Usage: $0 <plda-data-dir> <enroll-data-dir> <test-data-dir> <plda-ivec-dir> <enroll-ivec-dir> <test-ivec-dir> <trials-file> <scores-dir>"
fi

plda_data_dir=$1
enroll_data_dir=$2
test_data_dir=$3
plda_ivec_dir=$4
enroll_ivec_dir=$5
test_ivec_dir=$6
trials=$7
scores_dir=$8

if [ "$use_existing_models" == "true" ]; then
  for f in $plda_ivec_dir/mean.vec $plda_ivec_dir/pca_plda ; do
    [ ! -f $f ] && echo "No such file $f" && exit 1;
  done
else
  run.pl $plda_ivec_dir/log/compute_mean.log \
    ivector-mean scp:$plda_ivec_dir/ivector.scp \
    $plda_ivec_dir/mean.vec || exit 1;

  if [ ! -f $plda_ivec_dir/transform_pca.mat ]; then
    run.pl $plda_ivec_dir/log/pca.log \
      est-pca --dim=$pca_dim --read-vectors=true --normalize-mean=true \
      "ark:ivector-subtract-global-mean scp:$plda_ivec_dir/ivector.scp ark:- |" \
      $plda_ivec_dir/transform_pca.mat || exit 1;
  fi

  if [ ! -f $plda_ivec_dir/pca_plda ]; then
    run.pl $plda_ivec_dir/log/pca_plda.log \
      ivector-compute-plda ark:$plda_data_dir/spk2utt \
      "ark:ivector-subtract-global-mean scp:$plda_ivec_dir/ivector.scp ark:- | transform-vec $plda_ivec_dir/transform_pca.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
      $plda_ivec_dir/pca_plda || exit 1;
  fi
fi

mkdir -p $scores_dir/log

run.pl $scores_dir/log/pca_plda_scoring.log \
  ivector-plda-scoring --normalize-length=true \
    --num-utts=ark:${enroll_ivec_dir}/num_utts.ark \
    "ivector-copy-plda --smoothing=0.0 ${plda_ivec_dir}/pca_plda - |" \
    "ark:ivector-mean ark:$enroll_data_dir/spk2utt scp:$enroll_ivec_dir/ivector.scp ark:- | ivector-subtract-global-mean $plda_ivec_dir/mean.vec ark:- ark:- | transform-vec $plda_ivec_dir/transform_pca.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
    "ark:ivector-subtract-global-mean $plda_ivec_dir/mean.vec scp:$test_ivec_dir/ivector.scp ark:- | transform-vec $plda_ivec_dir/transform_pca.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
    "cat '$trials' | cut -d\  --fields=1,2 |" $scores_dir/pca_plda_scores || exit 1;
