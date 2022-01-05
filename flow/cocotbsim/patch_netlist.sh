#!/usr/bin/env bash

set -e

NL=$1
SDF=$2

TMP=$NL.tmp
NLP=$NL.v

grep -v ' vccd1\| vssd1\| vdda1\| vdda2\| vccd2\| vssa1\| vssa2\| vssd2' $NL > $TMP
mv $TMP $NLP

LINE=$(grep -n ");" $NLP | head -1 | cut -f1 -d':')
head -$LINE $NLP > $TMP
printf "supply0 vssd1;\nsupply1 vccd1;\n" >> $TMP
[ ! -z $(grep $SDF $NL) ] || printf "initial\nbegin\n\$sdf_annotate(\""$SDF"\",,,,\"MAXIMUM\");\nend\n" >> $TMP
let "LINE=$LINE+1"
tail -n +$LINE $NLP >> $TMP

mv $TMP $NL
rm -f $TMP $NLP

