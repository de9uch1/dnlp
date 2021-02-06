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
    parser.add_argument("--input", "-i", type=str, default="-", metavar="FILE")
    parser.add_argument("--no-histogram", action="store_true")
    parser.add_argument("--histogram-width", "-w", type=int, default=50, metavar="D")
    parser.add_argument("--raw-size", "-r", type=int, default=50, metavar="D")
    args = parser.parse_args()
    return args


def main(args):
    print(args, file=sys.stderr, flush=True)

    ntokens = 0
    squared_ntokens = 0
    vocabulary = defaultdict(int)
    max_len = 0
    max_len_ids = []
    min_len = 1e9
    min_len_ids = []
    nsentences = 0
    histogram = defaultdict(int)

    with fileinput.input(files=[args.input]) as f:
        for sent_id, line in enumerate(f, start=1):
            line = line.strip().split()

            for token in line:
                vocabulary[token] += 1

            n = len(line)
            ntokens += n
            squared_ntokens += n**2
            if n > max_len:
                max_len_ids = [sent_id]
                max_len = n
            elif n == max_len:
                max_len_ids.append(sent_id)
            if n < min_len:
                min_len_ids = [sent_id]
                min_len = n
            elif n == min_len:
                min_len_ids.append(sent_id)
            histogram[n // args.histogram_width] += 1
            nsentences += 1

    ntokens_mean = ntokens / nsentences
    ntokens_var = (squared_ntokens - ntokens_mean ** 2) / nsentences
    ntokens_sd = ntokens_var ** 0.5
    vocab_size = len(vocabulary)

    print("# of sentences     :\t{}".format(nsentences))
    print("# of tokens        :\t{}".format(ntokens))
    print("# of tokens (mean) :\t{}".format(ntokens_mean))
    print("# of tokens (SD)   :\t{}".format(ntokens_sd))
    print("max length         :\t{} (L.{})".format(max_len, ", ".join(map(str, max_len_ids))))
    print("min length         :\t{} (L.{})".format(min_len, ", ".join(map(str, min_len_ids))))
    print("vocabulary size    :\t{}".format(vocab_size))

    if not args.no_histogram:
        print("------------")
        print("histogram: (width={})".format(args.histogram_width))
        max_p = max(histogram)
        max_value = max(histogram.values())
        order = len(str(max_p * args.histogram_width))
        graph_format = "{{:{}d}}-{{:{}d}}: |{{}}{{}} {{}}".format(order, order)
        scaling = args.raw_size / max_value
        for w in range(max_p):
            count = histogram[w] * scaling
            ticks = TICK * round(count)
            if count != round(count):
                ticks += SM_TICK
            print(graph_format.format(
                w * args.histogram_width,
                (w + 1) * args.histogram_width,
                ticks, " " * (args.raw_size - len(ticks)),
                histogram[w]
            ))


if __name__ == "__main__":
    args = parse_args()
    main(args)
