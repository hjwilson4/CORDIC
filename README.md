# CORDIC
### 16-bit fixed point pipelined cordic calculator in VHDL.

  This repo contains a fully parallel CORDIC calculator for 16-bit non  
  negative Q1.14 fixed point values. Two 16-bit values are input to the  
  system for performing the calculation, x(15 downto 0) and y(15 downto 0).   
  For calculations requiring only a single operand, the unused input may   
  be any value. The result is output to r(15 downto 0). There is also a  
  5-bit function input, f(4 downto 0) to select which function to perform.   
 
  The functions available are:  
  &emsp;&emsp;      00001 --- cos(x)  
  &emsp;&emsp;      00101 --- sin(x)   
  &emsp;&emsp;      00100 --- x*y   
  &emsp;&emsp;     00010 --- cosh(x)  
  &emsp;&emsp;      00110 --- sinh(x)  
  &emsp;&emsp;      01100 --- y/x   
  &emsp;&emsp;      01101 --- arctan(x)   
  &emsp;&emsp;      01110 --- arctanh(x)  
 
  The CORDIC is implemented using 3 arrays labeled x_sum, y_sum, and z_sum.  
  To achieve the best accuracy, internal signals and operations are done in   
  Q1.20 format. Each 22 bits in the x and y arrays represents the outcome  
  of a right shift and sum operation which we will call a 'slice'. There are  
  a total of 21 slices or iterations run in the CORDIC.  
  &emsp; E.g. &emsp; x_sum(43 downto 22) = x_sum(21 downto 0) +/- y_sum_sft(21 downto 0)  
  &emsp;&emsp;&emsp;&emsp; y_sum(43 downto 22) = y_sum(21 downto 0) +/- x_sum_sft(21 downto 0) 
  
  The z_sum array operates similarly but using ROM values which are   
  added/subtracted as iterations pass.  

  Different functions implemented in the CORDIC choose differently between  
  addition and subtraction modes and certain functions are enabled to skip  
  iterations of the process described above.  
 
  Altogether, there are three modes (circular, linear, hyperbolic) and 2 types  
  for each mode (rotation or vectoring). Different combinations of modes and  
  types implement the different functions listed above. Each of the three modes  
  has a different set of ROM values that are added/subtracted with the z_sum  
  array as iterations pass.  
 
  The different ROM values are as follows:   
  &emsp;&emsp; Circular Mode   -- arctan(1/2^i) , i = 0,1,2,3...  
  &emsp;&emsp; Linear Mode     -- 1/2^i         , i = 0,1,2,3...   
  &emsp;&emsp; Hyperbolic Mode -- arctanh(1/2^i), i = 1,2,3,4...  
  *Note hyperbolic mode skips slice/iteration 0 of the CORDIC to obtain accurate  
   results  

  The combination of modes and their outputs are listed below:  
  **Rotation**  
  Circular Mode   |(K,0,A)-->(cos(A),sin(A),0)  |  
  Linear Mode     |(x,0,z) --> (x, x*z, 0)      |   
  Hyperbolic Mode |(K,0,A)-->(cosh(A),sinh(A),0)|  

  **Vectoring**  
  Circular Mode   |(x,y,0)-->(K_inv*|(x,y)|,0,arctan(y/x)) |  
  Linear Mode     |(x,y,0)-->(x,0,y/x)                     |  
  Hyperbolic Mode |(x,y,0)-->(K_inv*|(x,y)|,0,arctanh(y/x))|   
  
  *K (0.607253) and K_inv (1.6467) are constant terms which are stored in the  
   system.  

  Listed above are the inputs that are fed into the CORDIC system and what   
  they output depending on the mode/modetype of the function being    
  implemented. In each of the implementations listed above, one of the input  
  variables is driven to 0 through the course of the shift-right and sum  
  operation explained above. The variable that is being driven to 0 is the  
  decision variable that determines whether addition or subtraction is  
  performed on a slice of the arrays (e.g. x_sum(43 downto 0)). In rotation  
  it is the last variable (z) that is driven to 0 during calculation. When  
  z is negative the decision variable selects subtraction for the next  
  iteration. In vectoring it is the second variable (y) that is driven to 0  
  during calculation. When y is positive the decision variable selects  
  subtraction for the next iteration.  
 
  The z_sum terms do the opposite arithmatic of whatever the decision variable  
  selects. The y_sum terms do exactly the operation of whatever the decision  
  variable selects. The x_sum terms do the opposite operation in circular mode,  
  the exact operation in hyperbolic mode, and no operation when in linear mode.  
  After 10 iterations of the shift and sum process the the necessary response is  
  output the r(15 downto 0) signal as explained at the beginning. A history of  
  operations through the slices are stored in the ops(9 downto 0) signal.   

  After completing the architecture above, it is adapted for pipelining. DFFs  
  added to the modified sum arrays (e.g. x_sum) that are input into the adders  
  on a total of 5 pipelined slices. Additionally, the function codes testmode,  
  modetype, and f_pipe are now used to synchronize the added latency of the  
  pipelined CORDIC so that the correct output is displayed. Altogether, the  
  total latency with pipelining is 7 clock cycles and the throughput is one  
  16-bit Q1.14 input every clock cycle and one 16-bit Q1.14 output every clock  
  cycle.  
