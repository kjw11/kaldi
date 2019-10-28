#!usr/bin/python
# --coding: utf-8 —**
#
# Copyright 2019	Tsinghua University (Author: Jiawen Kang)
#
# This script is used for CN-Celeb database. It randomly selects 
# 20s audio for each speaker as enrollment utterances and skip 
# singing genres to insure the quality.

import sys
import os
from random import shuffle


def sub_set(srcdir, desdir):
    f = open(srcdir+'/spk2utt', 'r')
    spk2utt = f.readlines()
    f.close()
    f = open(srcdir+'/wav.scp', 'r')
    scp = f.readlines()
    f.close()
    sub_spk2utt = open(desdir+'/spk2utt', 'w')

    for spk_line in spk2utt:
        sum = 0
        name = spk_line.strip().split()[0]
        utts = spk_line.strip().split()[1:]
        shuffle(utts)
        sub_spk2utt.write(name)
        
        for utt in utts:
            # 20s per speaker
            if sum >= 20:
                sub_spk2utt.write('\n')
                break
            # skip singing genres
            if 'song' in utt:
                continue
            
            for utt_line in scp:
                if  utt_line.strip().split()[0]== utt:
                    wavdir = utt_line.strip().split()[1]
                    dur = os.popen('soxi -D %s' % wavdir).read()
                    sum += float(dur.strip())
                    sub_spk2utt.write(' ' + utt)
                    break
    f.close()


def main():
    srcdir = sys.argv[1]
    desdir = sys.argv[2]
    sub_set(srcdir, desdir)


if __name__ =="__main__":
    main()
