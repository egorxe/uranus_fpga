#!/bin/sh

cd $1
cat config.tcl $OLDPWD/scripts/load_design.tcl > tmp.tcl
env RUN_STANDALONE=1 MERGED_LEF_UNPADDED=./tmp/merged.nom.lef  LC_ALL=C openroad -gui tmp.tcl
