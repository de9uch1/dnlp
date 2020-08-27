#!/usr/bin/env python3
# Copyright (c) Hiroyuki Deguchi
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser
from collections import defaultdict
import fileinput
import sys

TICK = "▇"
SM_TICK = "▏"


def parse_args():
    parser = ArgumentParser()
    parser.add_argument('--input', '-i', type=str, default='-', metavar='FILE')
    parser.add_argument('--width-histogram', '-w', type=int, default=50, metavar='D')
    parser.add_argument('--raw-size', '-r', type=int, default=50, metavar='D')
    args = parser.parse_args()
    return args


def main(args):
    print(args, file=sys.stderr, flush=True)

    num_tokens = 0
    max_tokens = 0
    max_tokens_id = 0
    min_tokens = 1e9
    min_tokens_id = 0
    num_sentences = 0
    histogram = defaultdict(int)

    with fileinput.input(files=[args.input]) as f:
        for line in f:
            line = line.strip().split()
            n = len(line)

            num_tokens += n
            num_sentences += 1
            if n > max_tokens:
                max_tokens = n
                max_tokens_id = num_sentences
            if n < min_tokens:
                min_tokens = n
                min_tokens_id = num_sentences
            histogram[n // args.width_histogram] += 1

    print('num_sentences:\t{}'.format(num_sentences))
    print('num_tokens:\t{}'.format(num_tokens))
    print('average_tokens:\t{}'.format(num_tokens / num_sentences))
    print('max_tokens:\t{}\t(line: {})'.format(max_tokens, max_tokens_id))
    print('min_tokens:\t{}\t(line: {})'.format(min_tokens, min_tokens_id))
    print('------------')

    print('histogram: (width={})'.format(args.width_histogram))
    max_p = max(histogram)
    max_value = max(histogram.values())
    order = len(str(max_p * args.width_histogram))
    graph_format = "{{:{}d}}-{{:{}d}}: |{{}}{{}} {{}}".format(order, order)
    scaling = args.raw_size / max_value
    for w in range(max_p):
        count = histogram[w] * scaling
        ticks = TICK * round(count)
        if count != round(count):
            ticks += SM_TICK
        print(graph_format.format(
            w * args.width_histogram,
            (w + 1) * args.width_histogram,
            ticks, " " * (args.raw_size - len(ticks)),
            histogram[w]
        ))


if __name__ == '__main__':
    args = parse_args()
    main(args)
