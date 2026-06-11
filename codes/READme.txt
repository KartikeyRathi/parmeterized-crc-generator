one of the major issues in this is that the lut_array is being compiled at the start of the module due to the initial-----begin block and so is the testbench cases being regulated. 
So, to counter this, we have introduced a delay of 10 clock cycles in the testbench so that the LuT calculations take place prior to this and thus the issue is not encountered. 
HOWEVER this is a simulation  based error and not a synthesis based error so it will not cause issue in actual synthesizing of the module. 
A beta-version of the crc_lut_array is also present which might be able to counter these issues. 