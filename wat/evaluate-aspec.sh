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
usage: $(basename $0) [ ja | en ]

arguments:
    [ ja | en ]     language code

environment variables:
    TEST_DATA       set the /path/to/ASPEC/ASPEC-JE/test/test.txt (required)
    DNLP_CACHE_DIR  (optional) tools and translation reference will be created in DNLP_CACHE_DIR
                    default: "$HOME/.cache/dnlp"

You can also set these environment variables at this script to set static.
__EOT__
    exit -1
}

OUTDIR=references
prep=$OUTDIR
orig=$prep/orig
ref=$(basename $TEST_DATA .txt)

if ! [[ -d $DNLP_CACHE_DIR ]]; then
    mkdir -p $DNLP_CACHE_DIR
    if ! [[ -d $DNLP_CACHE_DIR ]]; then
        echo "'$DNLP_CACHE_DIR' cannot be created, abort" >&2
        exit -1
    fi
fi

WORKDIR=$DNLP_CACHE_DIR/wat/evaluate-aspec.sh
mkdir -p $WORKDIR
cd $WORKDIR

if [[ -z $TEST_DATA ]] || ! [[ -f $TEST_DATA ]]; then
    if ! [[ -f $prep/$(basename $TEST_DATA) ]]; then
        echo "reference file not found." >&2
        usage "TEST_DATA '$TEST_DATA' not found."
    fi
fi

if [[ $# -ne 1 ]] || \
       ([[ $1 != ja ]] && [[ $1 != en ]]); then
    usage
fi
tgt=$1

MOSES_SCRIPTS=mosesdecoder-2.1.1/scripts
MOSES_TOKENIZER=$MOSES_SCRIPTS/tokenizer/tokenizer.perl
MOSES_BLEU=$MOSES_SCRIPTS/generic/multi-bleu.perl
KYTEA_ROOT=kytea-0.4.6
KYTEA_TOKENIZER=$KYTEA_ROOT/bin/kytea
KYTEA_MODELNAME=jp-0.4.2-utf8-1.mod
KYTEA_MODEL=$KYTEA_ROOT/$KYTEA_MODELNAME
CC=/usr/bin/gcc
WAT_SCRIPTS=WAT-scripts
SEG_SCRIPTS=script.segmentation.distribution

if ! [[ -d $MOSES_SCRIPTS ]]; then
    echo 'Cloning Moses github repository (for tokenization scripts)...'
    git clone https://github.com/moses-smt/mosesdecoder.git \
        -b RELEASE-2.1.1 \
        mosesdecoder-2.1.1
fi >&2

if ! [[ -d $KYTEA_ROOT ]]; then
    echo 'Downloading Kytea source code (for tokenization scripts)...'
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

if ! [[ -f $KYTEA_TOKENIZER ]]; then
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

if ! [[ -f $KYTEA_MODEL ]]; then
    pushd $(dirname $KYTEA_MODEL)
    curl -O http://www.phontron.com/kytea/download/model/$KYTEA_MODELNAME.gz
    gzip -d $KYTEA_MODELNAME.gz
    popd
    if ! [[ -f $KYTEA_MODEL ]]; then
        echo "kytea model not successfully downloaded, abort."
        exit -1
    fi
fi >&2

function extract() {
    mkdir -p $prep $orig
    cp $TEST_DATA $orig/$ref.txt

    perl -ne 'chomp; @a=split/ \|\|\| /; print $a[2], "\n";' < $orig/$ref.txt > $orig/$ref.ja
    perl -ne 'chomp; @a=split/ \|\|\| /; print $a[3], "\n";' < $orig/$ref.txt > $orig/$ref.en
}

function tokenize_ja() {
    cat - | \
        perl -C -pe 'use utf8; s/(.)［[０-９．]+］$/${1}/;' | \
        sh $WAT_SCRIPTS/remove-space.sh | \
        perl -C $WAT_SCRIPTS/h2z-utf8-without-space.pl | \
        $KYTEA_TOKENIZER -model $KYTEA_MODEL -out tok | \
        perl -C -pe 's/^ +//; s/ +$//; s/ +/ /g;' | \
        perl -C -pe 'use utf8; while(s/([０-９]) ([０-９])/$1$2/g){} s/([０-９]) (．) ([０-９])/$1$2$3/g; while(s/([Ａ-Ｚ]) ([Ａ-Ｚａ-ｚ])/$1$2/g){} while(s/([ａ-ｚ]) ([ａ-ｚ])/$1$2/g){}'
}

function tokenize_en() {
    perl -C $SEG_SCRIPTS/z2h-utf8.pl | \
        perl -C $MOSES_TOKENIZER -l en -threads 8
}

function tokenize() {
    tokenize_$1 2>/dev/null
}

if ! [[ -f $prep/$ref.$tgt ]]; then
    extract >/dev/null 2>&1
    cat $orig/$ref.$tgt | \
        tokenize $tgt \
                 >$prep/$ref.$tgt
fi

cat - |
    tokenize $tgt | \
    $MOSES_BLEU $prep/$ref.$tgt 2>/dev/null
