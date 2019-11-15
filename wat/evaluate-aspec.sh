#!/bin/bash
# Copyright (c) Hiroyuki Deguchi
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# set the /path/to/ASPEC/ASPEC-JE/test/test.txt
TEST_DATA=${TEST_DATA:-/path/to/ASPEC/ASPEC-JE/test/test.txt}

# set the path to moses detokenizer.perl for English or empty if not needed. (default: "")
EN_DETOKENIZER=${EN_DETOKENIZER:-""}


function usage() {
    if [[ -n "$*" ]]; then
        echo "$*"
        echo ""
    fi

    cat << __EOT__
usage: $(basename $0) LANG SYSOUT [DATADIR]

arguments:
    LANG        target language [ ja | en ]
    SYSOUT      MT system output file

    DATADIR     (optional) when this argument is given, translation reference is created in DATADIR
                if you not set this argument, DATADIR will be automatically set 'MLENV_EXPDIR/data' or current directory

environment variables:
    TEST_DATA             set the /path/to/ASPEC/ASPEC-JE/test/test.txt (requireqd)
    EN_DETOKENIZER        set the path to moses detokenizer.perl for English if you needed
                          (default: "")

You can also set these environment variables at this script to set static.
__EOT__
    exit -1
}

[[ -n $EN_DETOKENIZER ]] && \
    if ! [[ -f $EN_DETOKENIZER ]]; then
        EN_DETOKENIZER=$(realpath $EN_DETOKENIZER)
    else
        usage "EN_DETOKENIZER '$EN_DETOKENIZER' not found."
    fi

if [[ $# -lt 2 ]] || [[ $# -gt 3 ]] || \
       ([[ $1 != ja ]] && [[ $1 != en ]]); then
    usage
fi

if [[ -f $2 ]]; then
    SYSOUT=$(realpath $2)
else
    usage "$2 not found."
fi

# for mlenv (cf. https://github.com/de9uch1/mlenv.git)
if [[ $# = 2 ]] && [[ -n $MLENV_EXPDIR ]] && [[ -d $MLENV_EXPDIR/data ]]; then
    cd $MLENV_EXPDIR/data
elif [[ -n $3 ]]; then
    if [[ -d $3 ]]; then
        cd $3
    else
        usage "DATADIR '$3' not found."
    fi
fi

MOSES_VERSION=2.1.1
MOSES_SCRIPTS=mosesdecoder-$MOSES_VERSION/scripts
MOSES_TOKENIZER=$MOSES_SCRIPTS/tokenizer/tokenizer.perl
MOSES_BLEU=$MOSES_SCRIPTS/generic/multi-bleu.perl
KYTEA_VERSION=0.4.6
KYTEA_ROOT=kytea-$KYTEA_VERSION
KYTEA_TOKENIZER=$KYTEA_ROOT/bin/kytea
KYTEA_MODELNAME=jp-0.4.2-utf8-1.mod
KYTEA_MODEL=$KYTEA_ROOT/$KYTEA_MODELNAME
CC=/usr/bin/gcc
SCRIPTS=WAT-scripts
SEG_SCRIPTS=script.segmentation.distribution

if ! [[ -d $MOSES_SCRIPTS ]]; then
    echo 'Cloning Moses github repository (for tokenization scripts)...'
    git clone https://github.com/moses-smt/mosesdecoder.git \
        -b RELEASE-${MOSES_VERSION} \
        mosesdecoder-${MOSES_VERSION}
fi

if ! [[ -d $KYTEA_ROOT ]]; then
    echo 'Downloading Kytea source code (for tokenization scripts)...'
    curl http://www.phontron.com/kytea/download/kytea-${KYTEA_VERSION}.tar.gz | tar xzf -
fi

if ! [[ -d $SCRIPTS ]]; then
    echo 'Cloning WAT-scripts github repository (for preprocess)...'
    git clone https://github.com/hassyGO/WAT-scripts.git
fi

if ! [[ -d $SEG_SCRIPTS ]]; then
    echo 'Downloading script.segmentation.distribution (for preprocess)...'
    curl http://lotus.kuee.kyoto-u.ac.jp/WAT/evaluation/automatic_evaluation_systems/script.segmentation.distribution.tar.gz | tar xzf -
    sed -ie "s/use encoding 'utf8';/use utf8;/g" $SEG_SCRIPTS/z2h-utf8.pl
fi

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
fi

if ! [[ -f $KYTEA_MODEL ]]; then
    pushd $(dirname $KYTEA_MODEL)
    curl -O http://www.phontron.com/kytea/download/model/$(basename $KYTEA_MODEL).gz
    gzip -d $KYTEA_MODELNAME.gz
    popd
    if ! [[ -f $KYTEA_MODEL ]]; then
        echo "kytea model not successfully downloaded, abort."
        exit -1
    fi
fi

OUTDIR=wat19_aspec_ja_en
prep=$OUTDIR/ref
tmp=$prep/tmp
orig=$prep/orig

function extract() {
    if [[ -z $TEST_DATA ]] || ! [[ -f $TEST_DATA ]]; then
        echo "reference file not found."
        usage "TEST_DATA '$TEST_DATA' not found."
    fi

    mkdir -p $prep $orig $tmp
    cp $TEST_DATA $orig/$(basename $TEST_DATA)

    echo "extracting sentences..."
    perl -ne 'chomp; @a=split/ \|\|\| /; print $a[2], "\n";' < $orig/test.txt > $orig/test.ja
    perl -ne 'chomp; @a=split/ \|\|\| /; print $a[3], "\n";' < $orig/test.txt > $orig/test.en
}

function tokenize_ja() {
    cat - | \
        perl -C -pe 'use utf8; s/(.)［[０-９．]+］$/${1}/;' | \
        sh $SCRIPTS/remove-space.sh | \
        perl -C $SCRIPTS/h2z-utf8-without-space.pl | \
        $KYTEA_TOKENIZER -model $KYTEA_MODEL -out tok | \
        perl -C -pe 's/^ +//; s/ +$//; s/ +/ /g;' | \
        perl -C -pe 'use utf8; while(s/([０-９]) ([０-９])/$1$2/g){} s/([０-９]) (．) ([０-９])/$1$2$3/g; while(s/([Ａ-Ｚ]) ([Ａ-Ｚａ-ｚ])/$1$2/g){} while(s/([ａ-ｚ]) ([ａ-ｚ])/$1$2/g){}'
}

function tokenize_en() {
    perl -C $SEG_SCRIPTS/z2h-utf8.pl | $MOSES_TOKENIZER -l en -threads 8
}

function tokenize() {
    tokenize_$1 2>/dev/null
}

function detokenize_ja() {
    cat -
}

function detokenize_en() {
    if [[ -n "$EN_DETOKENIZER" ]]; then
        if [[ $(basename "$EN_DETOKENIZER") = detokenizer.perl ]]; then
            cat - | "$EN_DETOKENIZER" -l en
        else
            echo "detokenizer '$EN_DETOKENIZER' is not supported."
            exit -1
        fi
    else
        cat -
    fi
}

function detokenize() {
    detokenize_$1 2>/dev/null
}

lang=$1
if ! [[ -f $prep/ref.$lang ]]; then
    extract
    echo "tokenizing reference sentences..."
    cat $orig/test.$lang | tokenize $lang >$prep/ref.$lang
fi

echo "tokenizing $SYSOUT in $lang..."

cat "$SYSOUT" | \
    detokenize $lang | \
    tokenize $lang | \
    $MOSES_BLEU $prep/ref.$lang
