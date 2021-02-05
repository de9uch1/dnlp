#!/bin/bash
# Copyright (c) Hiroyuki Deguchi
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# set the /path/to/ASPEC/ASPEC-JE/test/test.txt
TEST_DATA=${TEST_DATA:-/path/to/ASPEC/ASPEC-JE/test/test.txt}
DNLP_CACHE_DIR=${DNLP_CACHE_DIR:-$HOME/.cache/dnlp}

function usage() {
    if [[ -n "$*" ]]; then
        echo "$*"
        echo ""
    fi

    cat << __EOT__ >&2
usage: $(basename $0) [ ja | en | zh ]

arguments:
    [ ja | en | zh ]     language code

environment variables:
    TEST_DATA       set the /path/to/ASPEC/ASPEC-JE/test/test.txt (required)
    DNLP_CACHE_DIR  (optional) tools and translation reference will be created in DNLP_CACHE_DIR
                    default: "$HOME/.cache/dnlp"

You can also set these environment variables at this script to set static.
__EOT__
    exit -1
}

if ! [[ -d $DNLP_CACHE_DIR ]]; then
    mkdir -p $DNLP_CACHE_DIR
    if ! [[ -d $DNLP_CACHE_DIR ]]; then
        echo "'$DNLP_CACHE_DIR' cannot be created, abort" >&2
        exit -1
    fi
fi

TEST_DATA=$(readlink -f $TEST_DATA)
if [[ -z $TEST_DATA ]] || ! [[ -f $TEST_DATA ]]; then
    echo "reference file not found." >&2
    usage "TEST_DATA '$TEST_DATA' not found."
fi
ref_filename=$(basename $TEST_DATA)
test_set=$(basename $TEST_DATA .txt)
CORPORA=$(basename $(readlink -f $(dirname $TEST_DATA)/..))

WORKDIR=$DNLP_CACHE_DIR/wat/evaluate-aspec.sh
mkdir -p $WORKDIR
cd $WORKDIR

OUTDIR=references
prep=$OUTDIR/$CORPORA
orig=$prep/orig

if [[ $# -ne 1 ]] || \
       ([[ $1 != ja ]] && [[ $1 != en ]] && [[ $1 != zh ]]); then
    usage
fi
tgt=$1

MOSES_SCRIPTS=mosesdecoder-2.1.1/scripts
MOSES_TOKENIZER=$MOSES_SCRIPTS/tokenizer/tokenizer.perl
KYTEA_ROOT=kytea-0.4.6
KYTEA_TOKENIZER=$KYTEA_ROOT/bin/kytea
KYTEA_MODELNAME_JA=jp-0.4.2-utf8-1.mod
KYTEA_MODELNAME_ZH=msr-0.4.0-1.mod
KYTEA_MODEL_JA=$KYTEA_ROOT/$KYTEA_MODELNAME_JA
KYTEA_MODEL_ZH=$KYTEA_ROOT/$KYTEA_MODELNAME_ZH
CC=/usr/bin/gcc
WAT_SCRIPTS=WAT-scripts
SEG_SCRIPTS=script.segmentation.distribution

# for evaluation
MOSES_BLEU=$MOSES_SCRIPTS/generic/multi-bleu.perl
RIBES_DIR=RIBES-1.02.4
RIBES_SCRIPT=$RIBES_DIR/RIBES.py

if ! [[ -d $MOSES_SCRIPTS ]]; then
    echo 'Cloning Moses github repository (for tokenization and evaluation)...'
    git clone https://github.com/moses-smt/mosesdecoder.git \
        -b RELEASE-2.1.1 \
        mosesdecoder-2.1.1
fi >&2

if ([[ $tgt = "ja" ]] || [[ $tgt = "zh" ]]) && ! [[ -d $KYTEA_ROOT ]]; then
    echo 'Downloading Kytea source code (for tokenization)...'
    curl http://www.phontron.com/kytea/download/kytea-0.4.6.tar.gz | tar xzf -
fi >&2

if ! [[ -d $WAT_SCRIPTS ]]; then
    echo 'Cloning WAT-scripts github repository (for preprocess)...'
    git clone https://github.com/hassyGO/WAT-scripts.git
fi >&2

if ! [[ -d $SEG_SCRIPTS ]]; then
    echo 'Downloading script.segmentation.distribution (for preprocess)...'
    curl http://lotus.kuee.kyoto-u.ac.jp/WAT/evaluation/automatic_evaluation_systems/script.segmentation.distribution.tar.gz | tar xzf -
    sed -ie "s/use encoding 'utf8';/use utf8;/g" $SEG_SCRIPTS/z2h-utf8.pl
fi >&2

if ! [[ -f $RIBES_SCRIPT ]]; then
    echo 'Downloading RIBES script (for evaluation)...'
    curl http://www.kecl.ntt.co.jp/icl/lirg/ribes/package/RIBES-1.02.4.tar.gz | tar xzf -
fi >&2

if ([[ $tgt = "ja" ]] || [[ $tgt = "zh" ]]) && ! [[ -f $KYTEA_TOKENIZER ]]; then
    pushd $KYTEA_ROOT
    export CC
    ./configure --prefix=$(pwd)
    make clean
    make -j4
    make install
    popd
    if ! [[ -f $KYTEA_TOKENIZER ]]; then
        echo "kytea not successfully installed, abort."
        exit -1
    fi
fi >&2

if [[ $tgt = "ja" ]] && ! [[ -f $KYTEA_MODEL_JA ]]; then
    pushd $(dirname $KYTEA_MODEL_JA)
    curl -O http://www.phontron.com/kytea/download/model/$KYTEA_MODELNAME_JA.gz
    gzip -d $KYTEA_MODELNAME_JA.gz
    popd
    if ! [[ -f $KYTEA_MODEL_JA ]]; then
        echo "kytea model not successfully downloaded, abort."
        exit -1
    fi
fi

if [[ $tgt = "zh" ]] && ! [[ -f $KYTEA_MODEL_ZH ]]; then
    pushd $(dirname $KYTEA_MODEL_ZH)
    curl -O http://www.phontron.com/kytea/download/model/$KYTEA_MODELNAME_ZH.gz
    gzip -d $KYTEA_MODELNAME_ZH.gz
    popd
    if ! [[ -f $KYTEA_MODEL_ZH ]]; then
        echo "kytea model not successfully downloaded, abort."
        exit -1
    fi
fi

function extract() {
    mkdir -p $prep $orig
    cp $TEST_DATA $orig/$ref_filename

    if [[ $CORPORA = "ASPEC-JE" ]]; then
        perl -ne 'chomp; @a=split/ \|\|\| /; print $a[2], "\n";' < $orig/$ref_filename > $orig/$test_set.ja
        perl -ne 'chomp; @a=split/ \|\|\| /; print $a[3], "\n";' < $orig/$ref_filename > $orig/$test_set.en
    elif [[ $CORPORA = "ASPEC-JC" ]]; then
        perl -ne 'chomp; @a=split/ \|\|\| /; print $a[1], "\n";' < $orig/$ref_filename > $orig/$test_set.ja
        perl -ne 'chomp; @a=split/ \|\|\| /; print $a[2], "\n";' < $orig/$ref_filename > $orig/$test_set.zh
    fi
}

function tokenize_ja() {
    cat - | \
        perl -C -pe 'use utf8; s/(.)［[０-９．]+］$/${1}/;' | \
        sh $WAT_SCRIPTS/remove-space.sh | \
        perl -C $WAT_SCRIPTS/h2z-utf8-without-space.pl | \
        $KYTEA_TOKENIZER -model $KYTEA_MODEL_JA -out tok | \
        perl -C -pe 's/^ +//; s/ +$//; s/ +/ /g;' | \
        perl -C -pe 'use utf8; while(s/([０-９]) ([０-９])/$1$2/g){} s/([０-９]) (．) ([０-９])/$1$2$3/g; while(s/([Ａ-Ｚ]) ([Ａ-Ｚａ-ｚ])/$1$2/g){} while(s/([ａ-ｚ]) ([ａ-ｚ])/$1$2/g){}'
}

function tokenize_en() {
    perl -C $SEG_SCRIPTS/z2h-utf8.pl | \
        perl -C $MOSES_TOKENIZER -l en -threads 8
}

function tokenize_zh() {
    cat - | \
        sh $WAT_SCRIPTS/remove-space.sh | \
        perl -C $WAT_SCRIPTS/h2z-utf8-without-space.pl | \
        $KYTEA_TOKENIZER -model $KYTEA_MODEL_ZH -out tok | \
        perl -C -pe 's/^ +//; s/ +$//; s/ +/ /g;'
}

function tokenize() {
    tokenize_$1 2>/dev/null
}

function eval_bleu() {
    $MOSES_BLEU $prep/$test_set.$tgt < $1 2>/dev/null
}

function eval_ribes() {
    python3 $RIBES_SCRIPT -c -r $prep/$test_set.$tgt $1 2>/dev/null
}

function rmtemp() {
    [[ -d $TMPOUT ]] && rm -rf $TMPOUT
}

if ! [[ -f $prep/$test_set.$tgt ]]; then
    extract >/dev/null 2>&1
    cat $orig/$test_set.$tgt | \
        tokenize $tgt \
                 >$prep/$test_set.$tgt
fi

TMPOUT=$(mktemp -d)
trap rmtemp EXIT
trap "rmtemp; exit 1" INT PIPE TERM
sysout=$TMPOUT/sysout.tmp

cat - | tokenize $tgt > $sysout
eval_bleu $sysout
eval_ribes $sysout
