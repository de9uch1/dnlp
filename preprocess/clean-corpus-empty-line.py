#!/usr/bin/env python3
# Copyright (c) Hiroyuki Deguchi
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser
import re
import sys


def main(args):
    f = '{}.{}'.format(args.corpus, args.l1)
    e = '{}.{}'.format(args.corpus, args.l2)
    fo = '{}.{}'.format(args.clean_corpus, args.l1)
    eo = '{}.{}'.format(args.clean_corpus, args.l2)

    pattern = re.compile('^\s*$')
    cnt = 0
    lines = 0

    with \
      open(f, 'r', encoding='utf-8') as fp, \
      open(e, 'r', encoding='utf-8') as ep, \
      open(fo, 'w', encoding='utf-8') as fop, \
      open(eo, 'w', encoding='utf-8') as eop:
        for fl, el in zip(fp, ep):
            lines += 1
            if pattern.fullmatch(fl) is not None or pattern.fullmatch(el) is not None:
                continue
            fop.write(fl)
            eop.write(el)
            cnt += 1

    print('input sentences: {}, output sentences: {}'.format(lines, cnt), file=sys.stderr)


if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('corpus')
    parser.add_argument('l1')
    parser.add_argument('l2')
    parser.add_argument('clean_corpus')
    args = parser.parse_args()
    main(args)
