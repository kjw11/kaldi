#!/bin/bash
# Copyright   2019   Tsinghua University (Author: Lantian Li)
# Apache 2.0.
#
# This script uses 5 different scoring methods: 
# Cosine, LDA, PLDS, LDA_PLDA, PCA_PLD.

# number of components
lda_dim=150
pca_dim=150

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 8 ]; then
  echo "Usage: $0 [opts] <train-data> <train-vec> <enroll-data> <enroll-vec> <test-data> <test-vec> <trials> <scores-dir>"
  echo "  --lda-dim  # dim of lda-vector."
  echo "  --pca-dim  # dim of pca-vector."
  exit 1;
fi

train_data_dir=$1
train_ivec_dir=$2
enroll_data_dir=$3
enroll_ivec_dir=$4
test_data_dir=$5
test_ivec_dir=$6
trials=$7
scores_dir=$8

stage=0

if [ $stage -le 7 ]; then

  # Cosine metric.
  local/cosine_scoring.sh $enroll_data_dir $test_data_dir \
    $enroll_ivec_dir $test_ivec_dir $trials $scores_dir
  # Create a LDA model and do scoring.
  local/lda_scoring.sh --lda-dim $lda_dim $train_data_dir $enroll_data_dir $test_data_dir \
    $train_ivec_dir $enroll_ivec_dir $test_ivec_dir $trials $scores_dir
  # Create a PLDA model and do scoring.
  local/plda_scoring.sh $train_data_dir $enroll_data_dir $test_data_dir \
    $train_ivec_dir $enroll_ivec_dir $test_ivec_dir $trials $scores_dir
  # Create a LDA-PLDA model and do scoring.
  local/lda_plda_scoring.sh --lda-dim $lda_dim --covar-factor 0.0 $train_data_dir $enroll_data_dir $test_data_dir \
    $train_ivec_dir $enroll_ivec_dir $test_ivec_dir $trials $scores_dir
  # Create a PCA-PLDA model and do scoring.
  local/pca_plda_scoring.sh --pca-dim $pca_dim $train_data_dir $enroll_data_dir $test_data_dir \
    $train_ivec_dir $enroll_ivec_dir $test_ivec_dir $trials $scores_dir

  echo "Scores:"
  eer=$(paste $trials $scores_dir/cosine_scores | awk '{print $6, $3}' | compute-eer - 2>/dev/null)
  echo "Cosine EER: $eer%"
  eer=$(paste $trials $scores_dir/lda_scores | awk '{print $6, $3}' | compute-eer - 2>/dev/null)
  echo "LDA EER: $eer%"
  eer=$(paste $trials $scores_dir/plda_scores | awk '{print $6, $3}' | compute-eer - 2>/dev/null)
  echo "PLDA EER: $eer%"
  eer=$(paste $trials $scores_dir/lda_plda_scores | awk '{print $6, $3}' | compute-eer - 2>/dev/null)
  echo "LDA_PLDA EER: $eer%"
  eer=$(paste $trials $scores_dir/pca_plda_scores | awk '{print $6, $3}' | compute-eer - 2>/dev/null)
  echo "PCA_PLDA EER: $eer%"
fi

