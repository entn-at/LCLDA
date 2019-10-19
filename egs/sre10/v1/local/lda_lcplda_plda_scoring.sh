#!/bin/bash
# Copyright 2015   David Snyder
# Apache 2.0.
# modified by z3c
# This script trains LDA and PLDA models and does scoring.

use_existing_models=false
simple_length_norm=false # If true, replace the default length normalization
                         # performed in PLDA  by an alternative that
                         # normalizes the length of the iVectors to be equal
                         # to the square root of the iVector dimension.

echo "$0 $@"  # Print the command line for logging

lda_dim=200
use_existing_models=false
covar_factor=0.0
beta=1.0
rest_dim=50
nj=32

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 8 ]; then
  echo "Usage: $0 --lda-dim 200 <plda-data-dir> <enroll-data-dir> <test-data-dir> <plda-ivec-dir> <enroll-ivec-dir> <test-ivec-dir> <trials-file> <scores-dir>"
fi


plda_data_dir=$1 #data/sre
enroll_data_dir=$2 #data/sre10_train
test_data_dir=$3 # nouse: data/sre10_test 
plda_ivec_dir=$4 #sub_sre_path_cs
enroll_ivec_dir=$5 #sub_sre_train_path_cs
test_ivec_dir=$6 #sub_sre_test_path_cs
trials=$7
scores_dir=$8 # exp/cs_score

lda_dim1=$[lda_dim+rest_dim]

if [ "$use_existing_models" == "true" ]; then
  for f in ${plda_ivec_dir}/mean.vec ${plda_ivec_dir}/transform_lda.mat \
  		 ${plda_ivec_dir}/transform_lda_lcp.ark ${plda_ivec_dir}/spk_mean.ark \
  		 ${plda_ivec_dir}/lda_lcplda_plda ; do
    [ ! -f $f ] && echo "No such file $f" && exit 1;
  done
else
	# Compute the mean vector for centering the evaluation ivector. without length normalization
	mkdir -p ${plda_ivec_dir}/log	

	# leave 50 for lclda to reduce
	run.pl ${plda_ivec_dir}/log/lda_lcplda_plda1.log \
		ivector-compute-lplda --dim=$lda_dim1 --total-covariance-factor=$covar_factor \
			"ark:ivector-normalize-length scp:${plda_ivec_dir}/ivector.scp ark:- |" \
	  		ark:${plda_data_dir}/utt2spk \
	  		${plda_ivec_dir}/transform_lp.mat  || exit 1;


	# run.pl ${plda_ivec_dir}/log/lplda_lcplda_plda1.log \
	#     ivector-compute-lplda --dim=$lda_dim1  --total-covariance-factor=$covar_factor \
	#     "ark:ivector-normalize-length scp:${plda_ivec_dir}/ivector.scp ark:- |" \
	#       ark:${plda_data_dir}/utt2spk \
	#       ${plda_ivec_dir}/transform_${lda_dim1}.mat || exit 1;


	$train_cmd $plda_ivec_dir/log/compute_mean.log \
		ivector-mean scp:$plda_ivec_dir/ivector.scp \
		$plda_ivec_dir/mean.vec || exit 1;


	run.pl ${plda_ivec_dir}/log/lda_lcplda_plda2.log \
    	ivector-compute-lcplda-pdf --nj=$nj \
	      --pdf=${test_ivec_dir}/gmm_pdf.mat \
	      --dim=$lda_dim --total-covariance-factor=$covar_factor \
    	"ark:ivector-normalize-length scp:${plda_ivec_dir}/ivector.scp ark:- |	transform-vec  ${plda_ivec_dir}/transform_lp.mat ark:- ark:- | ivector-normalize-length ark:-  ark:- |" \
			ark:${plda_data_dir}/utt2spk \
			ark:${plda_ivec_dir}/transform_lda_lcp.ark \
			ark,t:${plda_ivec_dir}/spk_mean_lda.ark || exit 1;
	
	# it contain the total mean at the last row
	run.pl ${plda_ivec_dir}/log/spk_mean_ln.log \
		ivector-normalize-length ark:${plda_ivec_dir}/spk_mean_lda.ark ark:${plda_ivec_dir}/spk_mean_ln_lda.ark || exit 1;


	# Train a PLDA model. using transform-vec-lclda function
	# apply spk_mean_ln here, use cosine distance to find nearest spker
	$train_cmd $plda_ivec_dir/log/lda_lcplda_plda3.log \
	    ivector-compute-plda-set --nj=$nj \
	      --pdf=${test_ivec_dir}/gmm_pdf.mat \
	      --spk-mean=ark:${plda_ivec_dir}/spk_mean_ln_lda.ark \
	      ark:$plda_data_dir/spk2utt \
	      ark:${plda_ivec_dir}/transform_lda_lcp.ark  \
		"ark:ivector-normalize-length scp:${plda_ivec_dir}/ivector.scp ark:- |	transform-vec  ${plda_ivec_dir}/transform_lp.mat ark:- ark:- | ivector-normalize-length ark:-  ark:- |" \
	      ark:$plda_ivec_dir/lda_lcplda_plda_set.ark || exit 1;


fi

# Get results using the PLDA model. 
# $train_cmd $scores_dir/log/eval_scoring.log \
# 	ivector-lclda-plda-scoring --normalize-length=true \
# 	--simple-length-normalization=$simple_length_norm \
# 	--num-utts=ark:$enroll_ivec_dir/num_utts.ark \
# 	"ivector-copy-plda --smoothing=0.0  $plda_ivec_dir/lda_lclda_plda - |" \
# 	"ark:ivector-mean ark:$enroll_data_dir/spk2utt scp:$enroll_ivec_dir/ivector.scp ark:- | ivector-subtract-global-mean $plda_ivec_dir/mean.vec ark:- ark:- | 
# 		transform-vec  ${plda_ivec_dir}/transform_${lda_dim1}.mat ark:- ark:- |
# 		 ivector-normalize-length ark:- ark:- |" \
# 	"ark:ivector-subtract-global-mean $plda_ivec_dir/mean.vec scp:$test_ivec_dir/ivector.scp ark:- | transform-vec  ${plda_ivec_dir}/transform_${lda_dim1}.mat ark:- ark:- |
# 		 ivector-normalize-length ark:- ark:- |" \
# 	"cat '$trials' | cut -d\  --fields=1,2 |" \
# 	"ark:${plda_ivec_dir}/transform_${lda_dim}.ark" \
# 	"ark:${plda_ivec_dir}/spk_mean_ln.ark" \
# 	$scores_dir/eval_scores || exit 1

$train_cmd $scores_dir/log/eval_scoring.log \
	ivector-lclda-pldaset-scoring --normalize-length=true \
	  --simple-length-normalization=$simple_length_norm \
	  --num-utts=ark:$enroll_ivec_dir/num_utts.ark \
	  --transform=ark:${plda_ivec_dir}/transform_lda_lcp.ark \
	  --spk-mean=ark:${plda_ivec_dir}/spk_mean_ln_lda.ark \
	  ark:"$plda_ivec_dir/lda_lcplda_plda_set.ark" \
	  ark:"ivector-mean ark:$enroll_data_dir/spk2utt scp:$enroll_ivec_dir/ivector.scp ark:- | ivector-subtract-global-mean --subtract-mean=false $plda_ivec_dir/mean.vec ark:- ark:- | transform-vec ${plda_ivec_dir}/transform_lp.mat ark:- ark:- |" \
	  ark:"ivector-subtract-global-mean --subtract-mean=false $plda_ivec_dir/mean.vec scp:$test_ivec_dir/ivector.scp ark:- | transform-vec  ${plda_ivec_dir}/transform_lp.mat ark:- ark:- |" \
	  "cat '$trials' | cut -d\  --fields=1,2 |" \
	  $scores_dir/eval_scores  || exit 1;

# the following shows that when enroll and test ivectors project to different spaces respectively, and do dot production, it will greatly decrease the performance!!!!
# $train_cmd $scores_dir/log/eval_scoring.log \
# 	ivector-plda-scoring --normalize-length=true \
# 	--simple-length-normalization=$simple_length_norm \
# 	--num-utts=ark:$enroll_ivec_dir/num_utts.ark \
# 	"ivector-copy-plda --smoothing=0.0  $plda_ivec_dir/lda_lclda_plda - |" \
# 	"ark:ivector-mean ark:$enroll_data_dir/spk2utt scp:$enroll_ivec_dir/ivector.scp ark:- | ivector-subtract-global-mean $plda_ivec_dir/mean.vec ark:- ark:- | 
# 		transform-vec  ${plda_ivec_dir}/transform_${lda_dim1}.mat ark:- ark:- |
# 		transform-vec-lclda ark:${plda_ivec_dir}/transform_${lda_dim}.ark ark:${plda_ivec_dir}/spk_mean.ark ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
# 	"ark:ivector-subtract-global-mean $plda_ivec_dir/mean.vec scp:$test_ivec_dir/ivector.scp ark:- | 
# 		transform-vec  ${plda_ivec_dir}/transform_${lda_dim1}.mat ark:- ark:- |
# 		transform-vec-lclda ark:${plda_ivec_dir}/transform_${lda_dim}.ark ark:${plda_ivec_dir}/spk_mean.ark ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
# 	"cat '$trials' | cut -d\  --fields=1,2 |" $scores_dir/eval_scores || exit 1;