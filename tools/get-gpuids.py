#!/usr/bin/env python3
# Copyright (c) Hiroyuki Deguchi
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


def parse_args():
    parser = ArgumentParser()
    parser.add_argument('--num-gpus', '-n', type=int, default=1,
                        help='To specify the number of GPUs.')
    args = parser.parse_args()
    return args


def err(msg, exit_code=1):
    print(msg, file=sys.stderr)
    exit(exit_code)


def main(args):
    command = 'nvidia-smi'
    command_args = ['-q', '-x']
    command_line = [command] + command_args
    ngpus = args.num_gpus

    exists_command = shutil.which(command)

    if exists_command is None:
        err("'{}' not found, abort.".format(command))

    command_output = subprocess.run(command_line, capture_output=True)
    outputs = getattr(command_output, 'stdout', None)
    if outputs is None:
        err("'{}' execution failed, abort.".format(command))

    gpuinfo = ET.fromstring(outputs)
    gpuids = [
        id for id, gpu in enumerate(gpuinfo.findall('gpu'))
        if gpu.find('processes').find('process_info') is None
    ]
    if len(gpuids) < ngpus:
        err("Could not find {} free GPUs.".format(ngpus))

    if ngpus >= 1:
        print(','.join(str(i) for i in gpuids[:ngpus]))


if __name__ == '__main__':
    main(parse_args())
