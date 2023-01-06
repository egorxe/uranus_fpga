#!/usr/bin/env bash

set -e
shopt -s nullglob

RUN=$1
OPENMPW_REPO=$2
MACRO_RUN=$3

PRJ=user_project_wrapper
PRJSRC="designs/$PRJ"
RESULT="$RUN/results/final"

PRJMACRO=$(basename $MACRO_RUN)
PRJMACROSRC="designs/$PRJMACRO"
MACRORESULT="$MACRO_RUN/results/final"

NETLIST="$RESULT/verilog/gl/$PRJ".v
GDS="$RESULT/gds/$PRJ".gds
LEF="$RESULT/lef/$PRJ".lef
MAG="$RESULT/mag/$PRJ".mag
DEF="$RESULT/def/$PRJ".def
SDF="$RESULT/sdf/$PRJ".sdf

MACRONETLIST="$MACRORESULT/verilog/gl/$PRJMACRO".v
MACROLEF="$MACRORESULT/lef/$PRJMACRO".lef
MACRODEF="$MACRORESULT/def/$PRJMACRO".def
MACROSDF="$MACRORESULT/sdf/$PRJMACRO".sdf
MACROGDS="$MACRORESULT/gds/$PRJMACRO".gds

GZIP="gzip --keep --best -c"

# remove files which could be unpacked by precheck
echo "Cleaning up..."
rm -f $OPENMPW_REPO/gds/$PRJ.gds $OPENMPW_REPO/mag/$PRJ.mag $OPENMPW_REPO/verilog/gl/$PRJ.v \
    $OPENMPW_REPO/verilog/gl/$PRJMACRO.v $OPENMPW_REPO/def/$PRJMACRO.def $OPENMPW_REPO/sdf/$PRJMACRO.sdf $OPENMPW_REPO/def/$PRJ.def $OPENMPW_REPO/sdf/$PRJ.sdf

# copy project sources
echo "Copying sources..."
cp $PRJSRC/*.v $OPENMPW_REPO/verilog/rtl
cp $PRJSRC/config.tcl $OPENMPW_REPO/openlane/
cp $PRJSRC/*.cfg $OPENMPW_REPO/openlane/
cp $PRJSRC/*.sdc $OPENMPW_REPO/openlane/

# copy FPGA block sources
if [ ! -z "$MACRO_RUN" ]; then
    echo "Copying macro sources..."
    mkdir -p $OPENMPW_REPO/verilog/rtl/$PRJMACRO
    mkdir -p $OPENMPW_REPO/openlane/$PRJMACRO
    cp $PRJMACROSRC/*.v $MACRO_RUN/*.v $OPENMPW_REPO/verilog/rtl/$PRJMACRO
    [ -f $PRJMACROSRC/config.tcl ] && cp $PRJMACROSRC/config.tcl $OPENMPW_REPO/openlane/$PRJMACRO
    [ -f $PRJMACROSRC/config.tcl ] && cp $PRJMACROSRC/*.cfg $OPENMPW_REPO/openlane/$PRJMACRO
    [ -f $PRJMACROSRC/config.tcl ] && cp $PRJMACROSRC/*.sdc $OPENMPW_REPO/openlane/$PRJMACRO
    
    echo "Gziping macro implementation products..."
    $GZIP $MACRONETLIST > $OPENMPW_REPO/verilog/gl/$PRJMACRO.v.gz 
    cp $MACROLEF $OPENMPW_REPO/lef/
    $GZIP $MACRODEF > $OPENMPW_REPO/def/$PRJMACRO.def.gz 
    $GZIP $MACROSDF > $OPENMPW_REPO/sdf/$PRJMACRO.sdf.gz 
    $GZIP $MACROGDS > $OPENMPW_REPO/gds/$PRJMACRO.gds.gz 
fi

# copy implementation products
echo "Gzipping implementation products..."
$GZIP $NETLIST > $OPENMPW_REPO/verilog/gl/$PRJ.v.gz &
#$GZIP $MAG > $OPENMPW_REPO/mag/$PRJ.mag.gz &
$GZIP $DEF > $OPENMPW_REPO/def/$PRJ.def.gz &
$GZIP $SDF > $OPENMPW_REPO/sdf/$PRJ.sdf.gz &
$GZIP $GDS > $OPENMPW_REPO/gds/$PRJ.gds.gz 
cp $LEF $OPENMPW_REPO/lef/
wait
