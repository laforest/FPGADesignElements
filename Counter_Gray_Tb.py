import vunit
import os
import sys

vu = vunit.VUnit.from_argv()

source_dir = os.path.dirname(__file__)

lib = vu.add_library('lib')

for file_name in [
    'Gray_to_Binary.v',
    'Binary_to_Gray.v',
    'Gray.sv'
    ]:

    src_file = lib.add_source_file(os.path.join(source_dir,file_name))
    src_file.set_compile_option('modelsim.vlog_flags',['-vlog01compat'])

for file_name in [
    'Counter_Gray_Tb.sv',
    'Counter_Gray_SV_Tb.sv'
    ]:
    lib.add_source_file(os.path.join(source_dir,file_name))

lib.add_source_files('/usr/local/lib/python3.6/dist-packages/vunit/verilog/vunit_pkg.sv')

counter_gray_tb = lib.test_bench('Counter_Gray_Tb')

for test in counter_gray_tb.get_tests('*'):
    for width in [4,5,6]:
        test.add_config(
            name="W%d"%(width),
            generics={
                'WIDTH':width,
                'PRINT':1
            })

counter_gray_sv_tb = lib.test_bench('counter_gray_sv_tb')

for test in counter_gray_sv_tb.get_tests('*'):
    for width in [4,5,6]:
        test.add_config(
            name="W%d"%(width),
            generics={
                'WIDTH':width
            })


vu.main()
