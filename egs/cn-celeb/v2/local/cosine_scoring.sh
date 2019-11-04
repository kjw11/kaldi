#!/bin/bash
# Copyright 2015   David Snyder
# Copyright 2018   Lantian Li
# Apache 2.0.
#
# This script does cosine scoring.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 6 ]; then
  echo "Usage: $0 <enroll-data-dir> <test-data-dir> <enroll-xvec-dir> <test-xvec-dir> <trials-file> <scores-dir>"
fi

enroll_data_dir=$1
test_data_dir=$2
enroll_xvec_dir=$3
test_xvec_dir=$4
trials=$5
scores_dir=$6

mkdir -p $scores_dir/log
run.pl $scores_dir/log/cosine_scoring.log \
  cat $trials \| awk '{print $1" "$2}' \| \
 ivector-compute-dot-products - \
  scp:${enroll_xvec_dir}/spk_xvector.scp \
  "ark:ivector-normalize-length scp:${test_xvec_dir}/xvector.scp ark:- |" \
   $scores_dir/cosine_scores || exit 1;
