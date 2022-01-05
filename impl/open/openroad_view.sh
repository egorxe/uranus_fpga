#!/bin/sh

cd $1
cat config.tcl /home/egor/proj/OpenLane/scripts/openroad/sta.tcl > tmp.tcl
env RUN_STANDALONE=1 MERGED_LEF_UNPADDED=./tmp/merged_unpadded.lef LC_ALL=C openroad -gui tmp.tcl
