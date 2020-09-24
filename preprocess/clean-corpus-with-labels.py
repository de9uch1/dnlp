#!/usr/bin/env python3
# Copyright (c) Hiroyuki Deguchi
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser
import itertools
import sys


def main(args):
    f = '{}.{}'.format(args.corpus, args.l1)
    e = '{}.{}'.format(args.corpus, args.l2)
    fo = '{}.{}'.format(args.clean_corpus, args.l1)
    eo = '{}.{}'.format(args.clean_corpus, args.l2)

    cnt = 0
    lines = 0
    label_in = [open('{}.{}'.format(args.corpus, l), 'r') for l in args.label_ext]
    label_out = [open('{}.{}'.format(args.clean_corpus, l), 'w') for l in args.label_ext]
    if len(label_in) < 1:
        label_in.append(itertools.cycle([None]))
        label_out.append(itertools.cycle([None]))
    with \
      open(f, 'r', encoding='utf-8') as fp, \
      open(e, 'r', encoding='utf-8') as ep, \
      open(fo, 'w', encoding='utf-8') as fop, \
      open(eo, 'w', encoding='utf-8') as eop:
        for fl, el, *lip in zip(fp, ep, *label_in):
            lines += 1
            fn = len(fl.strip().split())
            en = len(el.strip().split())
            if (fn > args.max_len or
                en > args.max_len or
                fn < args.min_len or
                en < args.min_len or
                fn / en > args.ratio or
                en / fn > args.ratio
            ):
                continue
            fop.write(fl)
            eop.write(el)
            if len(args.label_ext) > 0:
                for ll, lop in zip(lip, label_out):
                    lop.write(ll)
            cnt += 1

    if len(args.label_ext) > 0:
        for lip, lop in zip(label_in, label_out):
            lip.close()
            lop.close()

    print('input sentences: {}, output sentences: {}'.format(lines, cnt), file=sys.stderr)


if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('--label-ext', '-l', action='append', default=[])
    parser.add_argument('--ratio', type=float, default=9)
    parser.add_argument('corpus')
    parser.add_argument('l1')
    parser.add_argument('l2')
    parser.add_argument('clean_corpus')
    parser.add_argument('min_len', type=int)
    parser.add_argument('max_len', type=int)
    args = parser.parse_args()
    main(args)
