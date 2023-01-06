# Copyright 2020 Efabless Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if { $::env(RUN_STANDALONE) == 1 } {
    #if { [info exists ::env(LIB_SYNTH_COMPLETE) ] } {
        #foreach lib $::env(LIB_SYNTH_COMPLETE) {
            #read_liberty $lib
        #}
    #}

    #if { [info exists ::env(EXTRA_LIBS) ] } {
        #foreach lib $::env(EXTRA_LIBS) {
            #read_liberty $lib
        #}
    #}

    if {[catch {read_lef $::env(MERGED_LEF_UNPADDED)} errmsg]} {
        puts stderr $errmsg
        exit 1
    }

    if { $::env(CURRENT_DEF) != 0 } {
        if {[catch {read_def $::env(CURRENT_DEF)} errmsg]} {
            puts stderr $errmsg
            exit 1
        }
    } else {
        if {[catch {read_verilog $::env(CURRENT_NETLIST)} errmsg]} {
            puts stderr $errmsg
            exit 1
        }
        link_design $::env(DESIGN_NAME)
    }

    #read_sdc -echo $::env(CURRENT_SDC)
    #if { $::env(STA_PRE_CTS) == 1 } {
        #unset_propagated_clock [all_clocks]
    #} else {
        #set_propagated_clock [all_clocks]
    #}
}
set_cmd_units -time ns -capacitance pF -current mA -voltage V -resistance kOhm -distance um

report_design_area
puts "area_report_end"
