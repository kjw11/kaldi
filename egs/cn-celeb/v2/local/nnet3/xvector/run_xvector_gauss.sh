#!/bin/bash
# Copyright      2017   David Snyder
#                2017   Johns Hopkins University (Author: Daniel Garcia-Romero)
#                2017   Johns Hopkins University (Author: Daniel Povey)
#
# Copied from egs/sre16/v1/local/nnet3/xvector/tuning/run_xvector_1a.sh (commit e082c17d4a8f8a791428ae4d9f7ceb776aef3f0b).
#
# Apache 2.0.

# This script trains a DNN similar to the recipe described in
# http://www.danielpovey.com/files/2018_icassp_xvectors.pdf

. ./cmd.sh
set -e

stage=1
train_stage=0
use_gpu=true
remove_egs=false

# Gauss Constrain
intra_ratio=
constrain_component=
output_plus=

data=data/train
init_dir=exp/xvector_nnet_1a
nnet_dir=exp/xvector_nnet_1c
egs_dir=exp/xvector_nnet_1a/egs

. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh

if [ $stage -le 7 ]; then
  mkdir -p $nnet_dir
  echo "output-node name=output_plus input=$output_plus" > $nnet_dir/init.config
  nnet3-init $init_dir/final.raw $nnet_dir/init.config $nnet_dir/base.raw
  cp $init_dir/max_chunk_size $nnet_dir/max_chunk_size
  cp $init_dir/min_chunk_size $nnet_dir/min_chunk_size
fi

srand=123
if [ $stage -le 8 ]; then
  steps/nnet3/train_raw_dnn_gauss.py --stage=$train_stage \
    --cmd="$gpu_cmd" \
    --trainer.input-model=$nnet_dir/base.raw \
    --trainer.optimization.proportional-shrink 10 \
    --trainer.optimization.momentum=0.5 \
    --trainer.optimization.num-jobs-initial=3 \
    --trainer.optimization.num-jobs-final=8 \
    --trainer.optimization.initial-effective-lrate=0.001 \
    --trainer.optimization.final-effective-lrate=0.0001 \
    --trainer.optimization.minibatch-size=64 \
    --trainer.srand=$srand \
    --trainer.max-param-change=2 \
    --trainer.num-epochs=2 \
    --trainer.shuffle-buffer-size=1000 \
    --trainer.intra-ratio=$intra_ratio \
    --trainer.constrain-component="$constrain_component" \
    --egs.frames-per-eg=1 \
    --egs.dir="$egs_dir" \
    --cleanup.remove-egs $remove_egs \
    --cleanup.preserve-model-interval=10 \
    --use-gpu=true \
    --dir=$nnet_dir  || exit 1;
fi

exit 0;
