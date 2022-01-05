#!/usr/bin/env bash

set -e

OPENMPW_REPO=$HOME/proj/ariel_fpga_openmpw
RUN=$1
PRJ=user_project_wrapper
PRJSRC=designs/$PRJ
NETLIST="$RUN/results/routing/$PRJ".powered.v
RESULT=$RUN/results/finishing/$PRJ
GZIP="gzip --keep --best -c"

# remove files which could be unpacked by precheck
echo "Cleaning up..."
rm -f $OPENMPW_REPO/gds/$PRJ.gds $OPENMPW_REPO/mag/$PRJ.mag $OPENMPW_REPO/verilog/gl/$PRJ.v

# copy project sources
echo "Copying sources..."
cp $PRJSRC/*.v $OPENMPW_REPO/verilog/rtl
cp $PRJSRC/config.tcl $OPENMPW_REPO/openlane/
cp $PRJSRC/*.cfg $OPENMPW_REPO/openlane/
cp $PRJSRC/*.sdc $OPENMPW_REPO/openlane/

# patch netlist to add unused power ports :(
set +e
grep 'input vccd2' $NETLIST > /dev/null
PATCH_NEEDED=$?
set -e
if [ $PATCH_NEEDED != 0 ]; then
    echo "Patching netlist $NETLIST"
    sed -i '0,/vccd1,/s//vccd1, vccd2, vdda1, vdda2, vssa1, vssa2, vssd2,/g' $NETLIST
    sed -i '0,/wire vccd2;/s//input vccd2;/g' $NETLIST
    sed -i '0,/wire vdda1;/s//input vdda1;/g' $NETLIST
    sed -i '0,/wire vdda2;/s//input vdda2;/g' $NETLIST
    sed -i '0,/wire vssa1;/s//input vssa1;/g' $NETLIST
    sed -i '0,/wire vssa2;/s//input vssa2;/g' $NETLIST
    sed -i '0,/wire vssd2;/s//input vssd2;/g' $NETLIST
else
    echo "Netlist already patched"
fi

# copy implementation products
echo "Gzipping implementation products..."
$GZIP $RESULT.gds > $OPENMPW_REPO/gds/$PRJ.gds.gz 
$GZIP $RESULT.mag > $OPENMPW_REPO/mag/$PRJ.mag.gz
$GZIP $NETLIST > $OPENMPW_REPO/verilog/gl/$PRJ.v.gz
cp $RESULT.lef $OPENMPW_REPO/lef/
