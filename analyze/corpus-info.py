#!/usr/bin/env python3
# Copyright (c) Hiroyuki Deguchi
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import dataclasses
import fileinput
import os
import sys
from argparse import ArgumentParser
from collections import Counter, defaultdict
from multiprocessing import Pool
from typing import Dict, List

TICK = "▇"
SM_TICK = "▏"


@dataclasses.dataclass
class Stats:
    num_sentences: int = 0
    num_tokens: int = 0
    squared_num_tokens: int = 0
    vocabulary: Counter = dataclasses.field(default_factory=Counter)
    max_len: int = 0
    min_len: int = 1e9
    max_len_ids: List[int] = dataclasses.field(default_factory=list)
    min_len_ids: List[int] = dataclasses.field(default_factory=list)
    histogram: defaultdict = dataclasses.field(default_factory=lambda: defaultdict(int))

    @staticmethod
    def get_line_stats(stats, sent_id: int, line: str, histogram_width: int = 1):
        line = line.strip().split()

        stats.num_sentences += 1
        stats.vocabulary.update(line)

        seq_len = len(line)
        stats.num_tokens += seq_len
        stats.histogram[seq_len // histogram_width] += 1
        stats.squared_num_tokens += (seq_len ** 2)

        if seq_len > stats.max_len:
            stats.max_len_ids = [sent_id]
            stats.max_len = seq_len
        elif seq_len == stats.max_len:
            stats.max_len_ids.append(sent_id)
        if seq_len < stats.min_len:
            stats.min_len_ids = [sent_id]
            stats.min_len = seq_len
        elif seq_len == stats.min_len:
            stats.min_len_ids.append(sent_id)

        return stats

    @staticmethod
    def get_lines_stats(stats, batch, histogram_width):
        for sent_id, line in batch:
            Stats.get_line_stats(stats, sent_id, line, histogram_width)
        return stats

    def merge_stats(self, stats):
        self.num_sentences += stats.num_sentences
        self.vocabulary += stats.vocabulary
        self.num_tokens += stats.num_tokens
        self.squared_num_tokens += stats.squared_num_tokens

        for w, v in stats.histogram.items():
            self.histogram[w] += v

        if stats.max_len > self.max_len:
            self.max_len_ids = stats.max_len_ids
            self.max_len = stats.max_len
        elif stats.max_len == self.max_len:
            self.max_len_ids.extend(stats.max_len_ids)

        if stats.min_len < self.min_len:
            self.min_len_ids = stats.min_len_ids
            self.min_len = stats.min_len
        elif stats.min_len == self.min_len:
            self.min_len_ids.extend(stats.min_len_ids)


def parse_args():
    parser = ArgumentParser()
    parser.add_argument("--input", "-i", type=str, default="-", metavar="FILE")
    parser.add_argument("--no-histogram", action="store_true")
    parser.add_argument("--histogram-width", "-w", type=int, default=50, metavar="D")
    parser.add_argument("--raw-size", "-r", type=int, default=50, metavar="D")
    parser.add_argument("--num-workers", type=int, default=1, metavar="D")
    parser.add_argument("--batch-size", type=int, default=10000, metavar="D")
    args = parser.parse_args()
    return args


def main(args):
    print(args, file=sys.stderr, flush=True)

    stats = Stats()
    pool = Pool(processes=args.num_workers)
    batch = []
    workers = []

    def exec_one(batch):
        sharded_stats = Stats()
        return pool.apply_async(Stats.get_lines_stats, args=(sharded_stats, batch, args.histogram_width))

    with fileinput.input(files=[args.input]) as f:
        for sent_id, line in enumerate(f, start=1):
            batch.append((sent_id, line))
            if sent_id % args.batch_size == 0:
                workers.append(exec_one(batch))
                batch = []
            if len(workers) >= args.num_workers:
                for res in workers:
                    stats.merge_stats(res.get())
                workers = []

        workers.append(exec_one(batch))

        pool.close()
        pool.join()
        for res in workers:
            stats.merge_stats(res.get())

    ntokens_mean = stats.num_tokens / stats.num_sentences
    ntokens_var = (stats.squared_num_tokens - ntokens_mean ** 2) / stats.num_sentences
    ntokens_sd = ntokens_var ** 0.5
    vocab_size = len(stats.vocabulary)

    print("# of sentences     :\t{}".format(stats.num_sentences))
    print("# of tokens        :\t{}".format(stats.num_tokens))
    print("# of tokens (mean) :\t{}".format(ntokens_mean))
    print("# of tokens (SD)   :\t{}".format(ntokens_sd))
    print("max length         :\t{} (L.{})".format(stats.max_len, ", ".join(map(str, stats.max_len_ids))))
    print("min length         :\t{} (L.{})".format(stats.min_len, ", ".join(map(str, stats.min_len_ids))))
    print("vocabulary size    :\t{}".format(vocab_size))

    if not args.no_histogram:
        histogram = stats.histogram
        print("------------")
        print("histogram: (width={})".format(args.histogram_width))
        max_p = max(histogram)
        max_value = max(histogram.values())
        order = len(str(max_p * args.histogram_width))
        graph_format = "{{:{}d}}-{{:{}d}}: |{{}}{{}} {{}}".format(order, order)
        scaling = args.raw_size / max_value
        for w in range(max_p + 1):
            bar_size = histogram[w] * scaling
            bar = TICK * round(bar_size)
            if bar_size != round(bar_size):
                bar += SM_TICK
            print(
                graph_format.format(
                    w * args.histogram_width,
                    (w + 1) * args.histogram_width - 1,
                    bar,
                    " " * (args.raw_size - len(bar)),
                    histogram[w],
                )
            )


if __name__ == "__main__":
    args = parse_args()
    main(args)
