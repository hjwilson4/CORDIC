----------------------------------------------------------------------------
--
--  16-bit PIPELINED CORDIC CALCULATOR
--
--  This file contains a fully parallel CORDIC calculator for 16-bit non 
--  negative Q1.14 fixed point values. Two 16-bit values are input to the 
--  system for performing the calculation, x(15 downto 0) and y(15 downto 0). 
--  For calculations requiring only a single operand, the unused input may 
--  be any value. The result is output to r(15 downto 0). There is also a 
--  5-bit function input, f(4 downto 0) to select which function to perform. 
-- 
--  The functions available are:
--        00001 --- cos(x)
--        00101 --- sin(x) 
--        00100 --- x*y 
--        00010 --- cosh(x)
--        00110 --- sinh(x)
--        01100 --- y/x 
--        01101 --- arctan(x) 
--        01110 --- arctanh(x)
-- 
--  The CORDIC is implemented using 3 arrays labeled x_sum, y_sum, and z_sum. 
--  To achieve the best accuracy, internal signals and operations are done in 
--  Q1.20 format. Each 22 bits in the x and y arrays represents the outcome 
--  of a right shift and sum operation which we will call a 'slice'. There are 
--  a total of 21 slices or iterations run in the CORDIC.
--     E.g. x_sum(43 downto 22) = x_sum(21 downto 0) +/- y_sum_sft(21 downto 0)
--          y_sum(43 downto 22) = y_sum(21 downto 0) +/- x_sum_sft(21 downto 0) 
--  The z_sum array operates similarly but using ROM values which are 
--  added/subtracted as iterations pass. 
--
--  Different functions implemented in the CORDIC choose differently between 
--  addition and subtraction modes and certain functions are enabled to skip 
--  iterations of the process described above. 
-- 
--  Altogether, there are three modes (circular, linear, hyperbolic) and 2 types 
--  for each mode (rotation or vectoring). Different combinations of modes and 
--  types implement the different functions listed above. Each of the three modes 
--  has a different set of ROM values that are added/subtracted with the z_sum 
--  array as iterations pass. 
-- 
--  The different ROM values are as follows:
--      Circular Mode   -- arctan(1/2^i) , i = 0,1,2,3... 
--      Linear Mode     -- 1/2^i         , i = 0,1,2,3... 
--      Hyperbolic Mode -- arctanh(1/2^i), i = 1,2,3,4...
--  *Note hyperbolic mode skips slice/iteration 0 of the CORDIC to obtain accurate 
--   results
--
--  The combination of modes and their outputs are listed below:
--                  |          Rotation           |
--  Circular Mode   |(K,0,A)-->(cos(A),sin(A),0)  |
--  Linear Mode     |(x,0,z) --> (x, x*z, 0)      |
--  Hyperbolic Mode |(K,0,A)-->(cosh(A),sinh(A),0)|
--
--                  |          Vectoring                     |
--  Circular Mode   |(x,y,0)-->(K_inv*|(x,y)|,0,arctan(y/x)) |
--  Linear Mode     |(x,y,0)-->(x,0,y/x)                     |
--  Hyperbolic Mode |(x,y,0)-->(K_inv*|(x,y)|,0,arctanh(y/x))| 
--  
--  *K (0.607253) and K_inv (1.6467) are constant terms which are stored in the 
--   system. 
--
--  Listed above are the inputs that are fed into the CORDIC system and what 
--  they output depending on the mode/modetype of the function being  
--  implemented. In each of the implementations listed above, one of the input 
--  variables is driven to 0 through the course of the shift-right and sum 
--  operation explained above. The variable that is being driven to 0 is the 
--  decision variable that determines whether addition or subtraction is 
--  performed on a slice of the arrays (e.g. x_sum(43 downto 0)). In rotation 
--  it is the last variable (z) that is driven to 0 during calculation. When 
--  z is negative the decision variable selects subtraction for the next 
--  iteration. In vectoring it is the second variable (y) that is driven to 0 
--  during calculation. When y is positive the decision variable selects 
--  subtraction for the next iteration. 
-- 
--  The z_sum terms do the opposite arithmatic of whatever the decision variable 
--  selects. The y_sum terms do exactly the operation of whatever the decision 
--  variable selects. The x_sum terms do the opposite operation in circular mode,
--  the exact operation in hyperbolic mode, and no operation when in linear mode. 
--  After 10 iterations of the shift and sum process the the necessary response is 
--  output the r(15 downto 0) signal as explained at the beginning. A history of 
--  operations through the slices are stored in the ops(9 downto 0) signal.  
--
--  After completing the architecture above, it is adapted for pipelining. DFFs 
--  added to the modified sum arrays (e.g. x_sum) that are input into the adders 
--  on a total of 5 pipelined slices. Additionally, the function codes testmode, 
--  modetype, and f_pipe are now used to synchronize the added latency of the 
--  pipelined CORDIC so that the correct output is displayed. Altogether, the 
--  total latency with pipelining is 7 clock cycles and the throughput is one 
--  16-bit Q1.14 input every clock cycle and one 16-bit Q1.14 output every clock 
--  cycle. 
--
--  Revision History:
--     01 Jan 09  Hector Wilson     Initial revision
--     01 Jan 10  Hector Wilson     Created basic structure of CORDIC slices 
--                                  and added ROM/constant values 
--     01 Jan 11  Hector Wilson     Implemented trig functions cos and sin in 
--                                  circular+rotation mode
--     01 Jan 12  Hector Wilson     Added x*y function using linear+rotation 
--                                  mode and hyperbolic functions cosh/sinh 
--                                  using hyperbolic+rotation mode 
--     01 Jan 13  Hector Wilson     Added constants and implemented y/x function 
--                                  which uses linear+vectoring mode
--     01 Jan 15  Hector Wilson     Added comments. Implemented arctan and 
--                                  arctanh functions
--     01 Jan 16  Hector Wilson     Updated comments
--     01 Jan 18  Hector Wilson     Began adapting architecture for pipelining 
--     01 Jan 19  Hector Wilson     Added DFFs to adder inputs for pipelining 
--     01 Jan 20  Hector Wilson     Updated design to fix bugs
--     01 Jan 22  Hector Wilson     Added pipelining DFFs for function codes 
--                                  testmode and modetype.
--     01 Jan 23  Hector Wilson     Finished pipelining & updated comments
--
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL; 
use IEEE.STD_LOGIC_UNSIGNED.ALL; 

entity cordic is
    port ( 
        x           :   in  std_logic_vector(15 downto 0);
        y           :   in  std_logic_vector(15 downto 0);
        f           :   in  std_logic_vector(4 downto 0);
        CLK         :   in  std_logic;
        r           :   out  std_logic_vector(15 downto 0)
    );
end cordic;

architecture Behavioral of cordic is
    
    ----------------------------------------------
    -- This component is used to perform the 22 bit addition/subtraction in  
    -- each slice of the CORDIC
    component  Adder
        port (
            X, Y :  in  std_logic_vector(21 downto 0);    -- addends
            Ci   :  in  std_logic;                              -- carry in
            S    :  out  std_logic_vector(21 downto 0);   -- sum out
            Co   :  out  std_logic                              -- carry bit    
        );
    end  component;
    ----------------------------------------------
    -- FUNCTION CODES
    ----------------------------------------------
    constant cos     :   std_logic_vector(4 downto 0) := "00001"; -- cos(x)
    constant sin     :   std_logic_vector(4 downto 0) := "00101"; -- sin(x)
    constant mul     :   std_logic_vector(4 downto 0) := "00100"; -- x*y
    constant cosh    :   std_logic_vector(4 downto 0) := "00010"; -- cosh(x)
    constant sinh    :   std_logic_vector(4 downto 0) := "00110"; -- sinh(x)
    constant div     :   std_logic_vector(4 downto 0) := "01100"; -- y/x
    constant atan    :   std_logic_vector(4 downto 0) := "01101"; -- tan^-1(x)
    constant atanh   :   std_logic_vector(4 downto 0) := "01110"; -- tanh^-1(x)
    ----------------------------------------------
    constant c_size  :   integer := 22;-- each slice does arithmatic w/ Q3.18 (22 bits)
    ----------------------------------------------
    -- These constants are used to skip certain slices/iterations of the CORDIC 
    constant zeros   : std_logic_vector(c_size-1 downto 0) := (others => '0');
    constant ones    : std_logic_vector(c_size-1 downto 0) := (others => '1');
    
    ----------------------------------------------
    -- The are the K and K^-1 constants used in the CORDIC arithmatic process 
    -- described in the header. 
    
    -- 0.607253 K
    constant K       :  std_logic_vector(c_size-1 downto 0) := "0010011011011101001111";
    -- 1.20514 K^-1
    constant K_inv   :  std_logic_vector(c_size-1 downto 0) := "0100110100100001000001";
    
    ----------------------------------------------
    -- ROM CONSTANTS (Q1.20 format)
    constant iter    :  integer := 21; -- number of slices = 21
    
    constant angle0  :  std_logic_vector(c_size-1 downto 0) := "0011001001000011111110"; -- 0.7853
    constant two0    :  std_logic_vector(c_size-1 downto 0) := "0100000000000000000000"; -- 1
    constant hangle0 :  std_logic_vector(c_size-1 downto 0) := "1111111111111111111111"; -- hyperbolics skip first iteration
    
    constant angle1  :  std_logic_vector(c_size-1 downto 0) := "0001110110101100011010"; -- 0.4636
    constant two1    :  std_logic_vector(c_size-1 downto 0) := "0010000000000000000000"; -- 0.5
    constant hangle1 :  std_logic_vector(c_size-1 downto 0) := "0010001100100111101111"; -- 0.5493
    
    constant angle2  :  std_logic_vector(c_size-1 downto 0) := "0000111110101101101111"; -- 0.244978
    constant two2    :  std_logic_vector(c_size-1 downto 0) := "0001000000000000000000"; -- 0.25
    constant hangle2 :  std_logic_vector(c_size-1 downto 0) := "0001000001011000101001"; -- 0.25541
    
    constant angle3  :  std_logic_vector(c_size-1 downto 0) := "0000011111110101011100"; -- 0.12435
    constant two3    :  std_logic_vector(c_size-1 downto 0) := "0000100000000000000000"; -- 0.125
    constant hangle3 :  std_logic_vector(c_size-1 downto 0) := "0000100000001010110100"; -- 0.12566
    
    constant angle4  :  std_logic_vector(c_size-1 downto 0) := "0000001111111110101011"; -- 0.06241
    constant two4    :  std_logic_vector(c_size-1 downto 0) := "0000010000000000000000"; -- 0.0625
    constant hangle4 :  std_logic_vector(c_size-1 downto 0) := "0000010000000001010100"; -- 0.06258
    
    constant angle5  :  std_logic_vector(c_size-1 downto 0) := "0000000111111111110110"; -- 0.03124
    constant two5    :  std_logic_vector(c_size-1 downto 0) := "0000001000000000000000"; -- 0.03125
    constant hangle5 :  std_logic_vector(c_size-1 downto 0) := "0000001000000000001010"; -- 0.03126
    
    constant angle6  :  std_logic_vector(c_size-1 downto 0) := "0000000011111111111111"; -- 0.015624
    constant two6    :  std_logic_vector(c_size-1 downto 0) := "0000000100000000000000"; -- 0.015625
    constant hangle6 :  std_logic_vector(c_size-1 downto 0) := "0000000100000000000001"; -- 0.015626
    
    constant angle7  :  std_logic_vector(c_size-1 downto 0) := "0000000010000000000000"; -- 0.007812
    constant two7    :  std_logic_vector(c_size-1 downto 0) := "0000000010000000000000"; -- 0.007812
    constant hangle7 :  std_logic_vector(c_size-1 downto 0) := "0000000010000000000000"; -- 0.007813
    
    -- 
    constant angle8  :  std_logic_vector(c_size-1 downto 0) := "0000000001000000000000"; -- 0.003906
    constant two8    :  std_logic_vector(c_size-1 downto 0) := "0000000001000000000000"; -- 0.003906
    constant hangle8 :  std_logic_vector(c_size-1 downto 0) := "0000000001000000000000"; -- 0.003906
    
    constant angle9  :  std_logic_vector(c_size-1 downto 0) := "0000000000100000000000"; -- 0.001953
    constant two9    :  std_logic_vector(c_size-1 downto 0) := "0000000000100000000000"; -- 0.001953
    constant hangle9 :  std_logic_vector(c_size-1 downto 0) := "0000000000100000000000"; -- 0.001953
    
    constant angle10 :  std_logic_vector(c_size-1 downto 0) := "0000000000010000000000"; -- 0.000976
    constant two10   :  std_logic_vector(c_size-1 downto 0) := "0000000000010000000000"; -- 0.000976
    constant hangle10:  std_logic_vector(c_size-1 downto 0) := "0000000000010000000000"; -- 0.000976 

    constant angle11 :  std_logic_vector(c_size-1 downto 0) := "0000000000001000000000"; -- 0.000488
    constant two11   :  std_logic_vector(c_size-1 downto 0) := "0000000000001000000000"; -- 0.000488
    constant hangle11:  std_logic_vector(c_size-1 downto 0) := "0000000000001000000000"; -- 0.000488

    constant angle12 :  std_logic_vector(c_size-1 downto 0) := "0000000000000100000000"; -- 0.000244
    constant two12   :  std_logic_vector(c_size-1 downto 0) := "0000000000000100000000"; -- 0.000244
    constant hangle12:  std_logic_vector(c_size-1 downto 0) := "0000000000000100000000"; -- 0.000244 

    constant angle13 :  std_logic_vector(c_size-1 downto 0) := "0000000000000010000000"; -- 0.000122
    constant two13   :  std_logic_vector(c_size-1 downto 0) := "0000000000000010000000"; -- 0.000122
    constant hangle13:  std_logic_vector(c_size-1 downto 0) := "0000000000000010000000"; -- 0.000122 

    constant angle14 :  std_logic_vector(c_size-1 downto 0) := "0000000000000001000000"; -- 0.000061
    constant two14   :  std_logic_vector(c_size-1 downto 0) := "0000000000000001000000"; -- 0.000061
    constant hangle14:  std_logic_vector(c_size-1 downto 0) := "0000000000000001000000"; -- 0.000061 

    constant angle15 :  std_logic_vector(c_size-1 downto 0) := "0000000000000000100000"; -- 0.000031
    constant two15   :  std_logic_vector(c_size-1 downto 0) := "0000000000000000100000"; -- 0.000031
    constant hangle15:  std_logic_vector(c_size-1 downto 0) := "0000000000000000100000"; -- 0.000031 

    constant angle16 :  std_logic_vector(c_size-1 downto 0) := "0000000000000000010000"; -- 0.000015
    constant two16   :  std_logic_vector(c_size-1 downto 0) := "0000000000000000010000"; -- 0.000015
    constant hangle16:  std_logic_vector(c_size-1 downto 0) := "0000000000000000010000"; -- 0.000015 

    constant angle17 :  std_logic_vector(c_size-1 downto 0) := "0000000000000000001000"; -- 0.0000076
    constant two17   :  std_logic_vector(c_size-1 downto 0) := "0000000000000000001000"; -- 0.0000076
    constant hangle17:  std_logic_vector(c_size-1 downto 0) := "0000000000000000001000"; -- 0.0000076 

    constant angle18 :  std_logic_vector(c_size-1 downto 0) := "0000000000000000000100"; -- 0.0000038
    constant two18   :  std_logic_vector(c_size-1 downto 0) := "0000000000000000000100"; -- 0.0000038
    constant hangle18:  std_logic_vector(c_size-1 downto 0) := "0000000000000000000100"; -- 0.0000038 

    constant angle19 :  std_logic_vector(c_size-1 downto 0) := "0000000000000000000010"; -- 0.0000019
    constant two19   :  std_logic_vector(c_size-1 downto 0) := "0000000000000000000010"; -- 0.0000019
    constant hangle19:  std_logic_vector(c_size-1 downto 0) := "0000000000000000000010"; -- 0.0000019 

    constant angle20 :  std_logic_vector(c_size-1 downto 0) := "0000000000000000000001"; -- 0.0000009
    constant two20   :  std_logic_vector(c_size-1 downto 0) := "0000000000000000000001"; -- 0.0000009
    constant hangle20:  std_logic_vector(c_size-1 downto 0) := "0000000000000000000001"; -- 0.0000009 
    ----------------------------------------------
    -- these arrays contain the ROM values above 
    type ROM is array (0 to iter-1) of std_logic_vector(c_size-1 downto 0);
    constant Linears    : ROM := (two0, two1, two2, two3, two4, 
                                  two5, two6, two7, two8, two9,
                                  two10,two11,two12,two13,two14,
                                  two15,two16,two17,two18,two19,two20);
    constant Circulars  : ROM := (angle0, angle1, angle2, angle3, angle4, 
                                  angle5, angle6, angle7, angle8, angle9,
                                  angle10,angle11,angle12,angle13,angle14,
                                  angle15,angle16,angle17,angle18,angle19,angle20);
    constant Hyperbolics: ROM := (hangle0, hangle1, hangle2, hangle3, hangle4, 
                                  hangle5, hangle6, hangle7, hangle8, hangle9,
                                  hangle10,hangle11,hangle12,hangle13,hangle14,
                                  hangle15,hangle16,hangle17,hangle18,hangle19,hangle20);
    ----------------------------------------------
    -- these signals contain each slice/shifted-slice of the CORDIC
    signal x_sum     :   std_logic_vector(c_size*iter-1 downto 0);
    signal x_sum_sft :   std_logic_vector(c_size*(iter-1)-1 downto 0);
    signal y_sum     :   std_logic_vector(c_size*iter-1 downto 0);
    signal y_sum_sft :   std_logic_vector(c_size*(iter-1)-1 downto 0);
    signal z_sum     :   std_logic_vector(c_size*iter-1 downto 0);
    ---------------------------------------------
    -- these signals contain a history of operations performed on each slice 
    -- when calculating
    signal ops       :  std_logic_vector(iter-1 downto 0);
    signal ops_ext   :  std_logic_vector(c_size*iter-1 downto 0);
    ---------------------------------------------
    -- this signal is used to indicate which slice is being skipped if any. 
    -- The slice that is skipped should be filled with ones in the corresponding 
    -- skip signal below. E.g. to skip iteration 1 for hyperbolics we set 
    -- skip(21 downto 0) to 1's and the rest to 0's. 
    signal skip      :  std_logic_vector(c_size*iter-1 downto 0);
    ---------------------------------------------
    -- these signals contain the modified version of the previous that is input 
    -- into the adder(s) feeding into the next slice. 
    signal y_sum_mod :  std_logic_vector(c_size*iter-1 downto 0);
    signal x_sum_mod :  std_logic_vector(c_size*iter-1 downto 0);
    signal x_ci      :  std_logic_vector(c_size*iter-1 downto 0);
    signal y_sum_ang :  std_logic_vector(c_size*iter-1 downto 0);
    
    -- TEST MODE --------------------------------
    -- (00)--> linear (01)--> circular (11)--> hyperbolic
    signal testmode     :  std_logic_vector(2*iter-1 downto 0);
    constant linear     :  std_logic_vector(1 downto 0) := "00";
    constant circular   :  std_logic_vector(1 downto 0) := "01";
    constant hyperbolic :  std_logic_vector(1 downto 0) := "11";
    -- TEST TYPE --------------------------------
    -- (0)--> rotation mode (1)--> vectoring mode
    signal modetype     :  std_logic_vector(iter-1 downto 0);
    constant rotation   :  std_logic := '0';
    constant vectoring  :  std_logic := '1';
    -- PIPELINING -------------------------------
    -- these constants indicate which slices of the CORDIC are pipelined. 
    -- f_pipe is used to hold a function code for a latency of 7 clocks to 
    -- synchronize with the CORDIC pipelining. 
    signal f_pipe       :  std_logic_vector(5*iter-1 downto 0);
    
    constant pipeline   :  std_logic_vector(iter-1 downto 0) := "0000100100"
                                                              & "01001001000";
    constant pipeline_ext: std_logic_vector(c_size*iter-1 downto 0) := zeros & zeros & zeros & zeros & ones
                                                                     & zeros & zeros & ones & zeros & zeros 
                                                                     & zeros & ones & zeros & zeros & ones 
                                                                     & zeros & zeros & ones & zeros & zeros & zeros; 
    -----------------------------------------------
    -- These signals contain the DFF-added modified sum arrays for the purposes
    -- of pipelining the CORDIC. 
    signal xadd_x       :  std_logic_vector(c_size*iter-1 downto 0);     
    signal xadd_y       :  std_logic_vector(c_size*iter-1 downto 0);
    signal xadd_c       :  std_logic_vector(iter-1 downto 0);
    
    signal yadd_x       :  std_logic_vector(c_size*iter-1 downto 0);
    signal yadd_y       :  std_logic_vector(c_size*iter-1 downto 0);
    signal yadd_c       :  std_logic_vector(iter-1 downto 0);
    
    signal zadd_x       :  std_logic_vector(c_size*iter-1 downto 0);
    signal zadd_y       :  std_logic_vector(c_size*iter-1 downto 0);
    signal zadd_c       :  std_logic_vector(iter-1 downto 0);
    ----------------------------------------------
    -- These signals are the inputs into the adders of each slice of the CORDIC. 
    -- Their value depends on whether a slice is pipelined or unpipelined. 
    -- If unpipelined: e.g. x_inputx will read from the x sum array. 
    -- If pipelined :       x_inputx will read from xadd_x which is 1 clock 
    --                      delayed version (i.e. with an added DFF). 
    signal x_inputx       :  std_logic_vector(c_size*iter-1 downto 0);     
    signal x_inputy       :  std_logic_vector(c_size*iter-1 downto 0);
    signal x_inputc       :  std_logic_vector(iter-1 downto 0);
    
    signal y_inputx       :  std_logic_vector(c_size*iter-1 downto 0);
    signal y_inputy       :  std_logic_vector(c_size*iter-1 downto 0);
    signal y_inputc       :  std_logic_vector(iter-1 downto 0);
    
    signal z_inputx       :  std_logic_vector(c_size*iter-1 downto 0);
    signal z_inputy       :  std_logic_vector(c_size*iter-1 downto 0);
    signal z_inputc       :  std_logic_vector(iter-1 downto 0);
   
begin
--------------------------------------------------------
-- this process loads inputs into the cordic on rising edge of clk. 
-- depending on the function being calculated, different values are passed
-- into different signals as done below. 
--
-- certain signals such as testmode, modetype, and f_pipe are input extended 
-- versions such as f_pipe(19 downto 0) = cos | cos | cos | cos since the first 4 
-- slices of the CORDIC are unpipelined. The other processes below take care of 
-- the rest. 
process(CLK) begin
    if rising_edge(CLK) then
        case(f) is 
            when cos =>
                x_sum(21 downto 0) <= K; -- start first x slice at K
                y_sum(21 downto 0) <= (others => '0'); -- y_sum starts at 0
                z_sum(21 downto 0) <= x & "000000"; -- load x input into first z slice
                skip <= (others => '0'); -- no skipped iterations
                testmode(7 downto 0) <= circular & circular & circular & circular;
                modetype(3 downto 0) <= (others => rotation); 
                ops(0) <= '0'; -- start at addition
                ops_ext(21 downto 0) <= (others => '0');
                f_pipe(19 downto 0) <= cos & cos & cos & cos;
            when sin => 
                x_sum(21 downto 0) <= K; -- start first x slice at K
                y_sum(21 downto 0) <= (others => '0'); -- y_sum starts at 0
                z_sum(21 downto 0) <= x & "000000"; -- load x input into first z slice
                skip <= (others => '0'); -- no skipped iterations
                testmode(7 downto 0) <= circular & circular & circular & circular;
                modetype(3 downto 0) <= (others => rotation); 
                ops(0) <= '0'; -- start at addition
                ops_ext(21 downto 0) <= (others => '0');
                f_pipe(19 downto 0) <= sin & sin & sin & sin;
            when mul => 
                x_sum(21 downto 0) <= x & "000000"; -- load x input into first x slice
                y_sum(21 downto 0) <= (others => '0'); -- start y_sum at 0
                z_sum(21 downto 0) <= y & "000000"; -- load y input into first z slice
                skip <= (others => '0'); -- no skipped iterations
                testmode(7 downto 0) <= linear & linear & linear & linear;
                modetype(3 downto 0) <= (others => rotation);
                ops(0) <= '0'; -- start at addition
                ops_ext(21 downto 0) <= (others => '0');
                f_pipe(19 downto 0) <= mul & mul & mul & mul;
            when cosh => 
                x_sum(21 downto 0) <= K_inv; -- start first x slice at K^-1
                y_sum(21 downto 0) <= (others => '0'); -- y_sum starts at 0
                z_sum(21 downto 0) <= x & "000000"; -- load x input into first z slice
                skip <= zeros & zeros & zeros & zeros & zeros 
                      & zeros & zeros & zeros & zeros & zeros 
                      & zeros & zeros & zeros & zeros & zeros 
                      & zeros & zeros & zeros & zeros & zeros & ones; -- skip first iteration
                testmode(7 downto 0) <= hyperbolic & hyperbolic & hyperbolic & hyperbolic;
                modetype(3 downto 0) <= (others => rotation); 
                ops(0) <= '0'; -- start at addition
                ops_ext(21 downto 0) <= (others => '0');
                f_pipe(19 downto 0) <= cosh & cosh & cosh & cosh;
            when sinh =>
                x_sum(21 downto 0) <= K_inv; -- start first x slice at K^-1
                y_sum(21 downto 0) <= (others => '0'); -- y_sum starts at 0
                z_sum(21 downto 0) <= x & "000000"; -- load x input into first z slice
                skip <= zeros & zeros & zeros & zeros & zeros 
                      & zeros & zeros & zeros & zeros & zeros 
                      & zeros & zeros & zeros & zeros & zeros 
                      & zeros & zeros & zeros & zeros & zeros & ones; -- skip first iteration
                testmode(7 downto 0) <= hyperbolic & hyperbolic & hyperbolic & hyperbolic;
                modetype(3 downto 0) <= (others => rotation); 
                ops(0) <= '0'; -- start at addition
                ops_ext(21 downto 0) <= (others => '0');
                f_pipe(19 downto 0) <= sinh & sinh & sinh & sinh;
            when div => 
                x_sum(21 downto 0) <= x & "000000"; -- load x input into first x slice
                y_sum(21 downto 0) <= y & "000000"; -- load y input into first y slice
                z_sum(21 downto 0) <= (others => '0'); -- z_sum starts at 0
                skip <= (others => '0'); -- no skipped iterations for division
                testmode(7 downto 0) <= linear & linear & linear & linear;
                modetype(3 downto 0) <= (others => vectoring); 
                ops(0) <= '1'; -- start at subtraction
                ops_ext(21 downto 0) <= (others => '1');
                f_pipe(19 downto 0) <= div & div & div & div;
            when atan => 
                x_sum(21 downto 0) <= "0100000000000000000000"; -- load 1 into first x slice
                y_sum(21 downto 0) <= x & "000000"; -- load input into first y slice
                z_sum(21 downto 0) <= (others => '0'); -- z_sum starts at 0
                skip <= (others => '0'); -- no skipped iterations for arctan
                testmode(7 downto 0) <= circular & circular & circular & circular;
                modetype(3 downto 0) <= (others => vectoring); 
                ops(0) <= '1'; -- start at subtraction
                ops_ext(21 downto 0) <= (others => '1');
                f_pipe(19 downto 0) <= atan & atan & atan & atan;
            when atanh => 
                x_sum(21 downto 0) <= "0100000000000000000000"; -- load 1 into first x slice 
                y_sum(21 downto 0) <= x & "000000"; -- load input into first y slice
                z_sum(21 downto 0) <= (others => '0'); -- z_sum starts at 0
                skip <= zeros & zeros & zeros & zeros & zeros 
                      & zeros & zeros & zeros & zeros & zeros 
                      & zeros & zeros & zeros & zeros & zeros 
                      & zeros & zeros & zeros & zeros & zeros & ones; -- skip first iteration
                testmode(7 downto 0) <= hyperbolic & hyperbolic & hyperbolic & hyperbolic;
                modetype(3 downto 0) <= (others => vectoring); 
                ops(0) <= '1'; -- start at subtraction
                ops_ext(21 downto 0) <= (others => '1');
                f_pipe(19 downto 0) <= atanh & atanh & atanh & atanh;
            when others =>
        end case;
    end if;
end process;
--------------------------------------------------------
-- FUNCTION PIPELINING
-- this process pipelines the function codes: modetype, testmode, and f_pipe. 
-- modetype contains the type of mode of the function: rotation or vectoring 
-- testmode contains mode of the function: circular, linear, or hyperbolic. 
-- f_pipe passes the function through so that the correct output is sent.
--
-- Each of these signals passes through a latency of 7 clocks so it synchronizes 
-- with the latency of the cordic operations. 
process(CLK) begin 
    if rising_edge(CLK) then 
        modetype(6 downto 4) <= (others => modetype(3));
        testmode(13 downto 8) <= testmode(7 downto 6) & testmode(7 downto 6) & testmode(7 downto 6);
        f_pipe(34 downto 20) <= f_pipe(19 downto 15) & f_pipe(19 downto 15) & f_pipe(19 downto 15);
        
        modetype(9 downto 7) <= (others => modetype(6));
        testmode(19 downto 14) <= testmode(13 downto 12) & testmode(13 downto 12) & testmode(13 downto 12);
        f_pipe(49 downto 35) <= f_pipe(34 downto 30) & f_pipe(34 downto 30) & f_pipe(34 downto 30);
        
        modetype(13 downto 10) <= (others => modetype(9));
        testmode(27 downto 20) <= testmode(19 downto 18) & testmode(19 downto 18) & testmode(19 downto 18) & testmode(19 downto 18);
        f_pipe(69 downto 50) <= f_pipe(49 downto 45) & f_pipe(49 downto 45) & f_pipe(49 downto 45) & f_pipe(49 downto 45);
        
        modetype(16 downto 14) <= (others => modetype(13));
        testmode(33 downto 28) <= testmode(27 downto 26) & testmode(27 downto 26) & testmode(27 downto 26);
        f_pipe(84 downto 70) <= f_pipe(69 downto 65) & f_pipe(69 downto 65) & f_pipe(69 downto 65);
        
        modetype(20 downto 17) <= (others => modetype(16));
        testmode(41 downto 34) <= testmode(33 downto 32) & testmode(33 downto 32) & testmode(33 downto 32) & testmode(33 downto 32);
        f_pipe(104 downto 85) <= f_pipe(84 downto 80) & f_pipe(84 downto 80) & f_pipe(84 downto 80) & f_pipe(84 downto 80);
    end if;
end process;
--------------------------------------------------------
-- Now we generate the CORDIC slices using a for generate 
-- loop. 
CORDIC: for i in 0 to iter-2 generate 
begin 
    -- this process adds DFFs to pipeline the adder inputs of each of the 21 slices. 
    process(CLK) begin 
        if rising_edge(CLK) then 
            if pipeline(i) = '1' then
                xadd_y(22*i+21 downto 22*i) <= y_sum_mod(22*i+21 downto 22*i);
                xadd_x(22*i+21 downto 22*i) <= x_sum(22*i+21 downto 22*i);
                xadd_c(i) <= x_ci(i);
                
                yadd_x(22*i+21 downto 22*i) <= x_sum_mod(22*i+21 downto 22*i);
                yadd_y(22*i+21 downto 22*i) <= y_sum(22*i+21 downto 22*i);
                yadd_c(i) <= ops(i);
                
                zadd_x(22*i+21 downto 22*i) <= z_sum(22*i+21 downto 22*i);
                zadd_y(22*i+21 downto 22*i) <= y_sum_ang(22*i+21 downto 22*i);
                zadd_c(i) <= not ops(i);
            end if; 
        end if;
    end process;
    
    -- SHIFTED ARRAYS -----------------------
    -- these are the right shifted inputs for each segment of the sum array
    x_sum_sft(22*i+21-i downto 22*i) <= x_sum(22*i+21 downto 22*i+i);
    x_sum_sft(22*i+21 downto 22*i+21-i+1) <= (others => '0');
    
    y_sum_sft(22*i+21-i downto 22*i) <= y_sum(22*i+21 downto 22*i+i);
    y_sum_sft(22*i+21 downto 22*i+21-i+1) <= (others => '0');
    
    -- MODIFIED ADDER INPUTS ----------------
    -- these signals are modified versions of the previous slice that are input into the 
    -- 22 bit adders defined below
    y_sum_mod(22*i+21 downto 22*i) <= (zeros) when testmode(2*i+1 downto 2*i) = linear else 
                                      (not skip(22*i+21 downto 22*i)) and (not ops_ext(22*i+21 downto 22*i) xor y_sum_sft(22*i+21 downto 22*i)) when testmode(2*i+1 downto 2*i) = circular else
                                      (not skip(22*i+21 downto 22*i)) and (ops_ext(22*i+21 downto 22*i) xor y_sum_sft(22*i+21 downto 22*i));
    x_ci(i) <= not ops(i) when testmode(2*i+1 downto 2*i) = circular else 
               '0'        when testmode(2*i+1 downto 2*i) = linear else
               ops(i);
    x_sum_mod(22*i+21 downto 22*i) <= (not skip(22*i+21 downto 22*i)) and (ops_ext(22*i+21 downto 22*i) xor x_sum_sft(22*i+21 downto 22*i));
    y_sum_ang(22*i+21 downto 22*i) <= (not skip(22*i+21 downto 22*i)) and (not ops_ext(22*i+21 downto 22*i) xor Circulars(i))   when testmode(2*i+1 downto 2*i) = circular   and modetype(i) = rotation else 
                                      (not skip(22*i+21 downto 22*i)) and (not ops_ext(22*i+21 downto 22*i) xor Linears(i))     when testmode(2*i+1 downto 2*i) = linear     and modetype(i) = rotation else 
                                      (not skip(22*i+21 downto 22*i)) and (not ops_ext(22*i+21 downto 22*i) xor Hyperbolics(i)) when testmode(2*i+1 downto 2*i) = hyperbolic and modetype(i) = rotation else
                                      (not skip(22*i+21 downto 22*i)) and (not ops_ext(22*i+21 downto 22*i) xor Linears(i))     when testmode(2*i+1 downto 2*i) = linear     and modetype(i) = vectoring else
                                      (not skip(22*i+21 downto 22*i)) and (not ops_ext(22*i+21 downto 22*i) xor Circulars(i))   when testmode(2*i+1 downto 2*i) = circular   and modetype(i) = vectoring else
                                      (not skip(22*i+21 downto 22*i)) and (not ops_ext(22*i+21 downto 22*i) xor Hyperbolics(i));  
    -- ADDER INPUTS --------------------------
    -- these signals are sent into the adders for each slice. Each of these inputs contain a simple 
    -- 2x1 mux depending on whether or not this slice is being pipelined. 
    x_inputx(22*i+21 downto 22*i) <= (x_sum(22*i+21 downto 22*i) and not pipeline_ext(22*i+21 downto 22*i))
                                  or (xadd_x(22*i+21 downto 22*i) and pipeline_ext(22*i+21 downto 22*i));
    x_inputy(22*i+21 downto 22*i) <= (y_sum_mod(22*i+21 downto 22*i) and not pipeline_ext(22*i+21 downto 22*i))
                                  or (xadd_y(22*i+21 downto 22*i) and pipeline_ext(22*i+21 downto 22*i));
    x_inputc(i) <= (x_ci(i) and not pipeline(i))
                or (xadd_c(i) and pipeline(i));
        
    y_inputx(22*i+21 downto 22*i) <= (x_sum_mod(22*i+21 downto 22*i) and not pipeline_ext(22*i+21 downto 22*i))
                                  or (yadd_x(22*i+21 downto 22*i) and pipeline_ext(22*i+21 downto 22*i));
    y_inputy(22*i+21 downto 22*i) <= (y_sum(22*i+21 downto 22*i)  and not pipeline_ext(22*i+21 downto 22*i)) 
                                  or (yadd_y(22*i+21 downto 22*i) and pipeline_ext(22*i+21 downto 22*i));
    y_inputc(i) <= (ops(i) and not pipeline(i)) 
                or (yadd_c(i) and pipeline(i));
                
    z_inputx(22*i+21 downto 22*i) <= (z_sum(22*i+21 downto 22*i) and not pipeline_ext(22*i+21 downto 22*i))
                                  or (zadd_x(22*i+21 downto 22*i) and pipeline_ext(22*i+21 downto 22*i)); 
    z_inputy(22*i+21 downto 22*i) <= (y_sum_ang(22*i+21 downto 22*i) and not pipeline_ext(22*i+21 downto 22*i))
                                  or (zadd_y(22*i+21 downto 22*i) and pipeline_ext(22*i+21 downto 22*i));
    z_inputc(i) <= (not ops(i) and not pipeline(i)) 
                or (zadd_c(i) and pipeline(i));
                
       
    -- ADDERS --------------------------------
    -- these adders implement the add/subtraction portion of each slice for the CORDIC
    X_Adders: Adder port map (
            X =>   x_inputx(22*i+21 downto 22*i), 
            Y =>   x_inputy(22*i+21 downto 22*i),
            Ci =>  x_inputc(i),
            S =>   x_sum(22*(i+1)+21 downto 22*(i+1))
            );
            
    Y_Adders: Adder port map (
            X =>   y_inputx(22*i+21 downto 22*i),
            Y =>   y_inputy(22*i+21 downto 22*i),
            Ci =>  y_inputc(i),
            S =>   y_sum(22*(i+1)+21 downto 22*(i+1))
            );
          
    Z_Adders: Adder port map (
            X =>   z_inputx(22*i+21 downto 22*i),
            Y =>   z_inputy(22*i+21 downto 22*i),
            Ci =>  z_inputc(i),
            S =>   z_sum(22*(i+1)+21 downto 22*(i+1))
            );
    --------------------------------
    -- UPDATE DECISION VARIABLE (0=Addition, 1=Subtraction)
    ops(i+1) <= '1' when (z_sum(22*(i+1)+21) = '1') and modetype(i) = rotation else 
                '1' when (y_sum(22*(i+1)+21) = '0') and modetype(i) = vectoring else
                '0';
    -- extend decision variable to perform operations with arrays
    ops_ext(22*(i+1)+21 downto 22*(i+1)) <= (others => ops(i+1));
end generate;
--------------------------------------------------------

-- this process outputs the cordic result to r on the rising edge of clk. 
-- the result is taken from the last 22 calculated bits in the respective 
-- array. 
process(CLK) begin
    if rising_edge(CLK) then 
        case(f_pipe(5*iter-1 downto 5*iter-5)) is 
            when cos => -- cos outputs result from x_sum
                r <= x_sum(c_size*iter-1 downto c_size*iter-16);
            when sin => -- sin outputs result from y_sum
                r <= y_sum(c_size*iter-1 downto c_size*iter-16);
            when mul => -- multiply outputs result from y_sum 
                r <= y_sum(c_size*iter-1 downto c_size*iter-16);
            when cosh => -- cosh outputs result from x_sum
                r <= x_sum(c_size*iter-1 downto c_size*iter-16);
            when sinh => -- sinh outputs result from y_sum
                r <= y_sum(c_size*iter-1 downto c_size*iter-16);
            when div => -- division outputs result from z_sum
                r <= z_sum(c_size*iter-1 downto c_size*iter-16);
            when atan => -- arctan outputs result from z_sum
                r <= z_sum(c_size*iter-1 downto c_size*iter-16);
            when atanh => -- arctanh outputs result from z_sum
                r <= z_sum(c_size*iter-1 downto c_size*iter-16);
            when others => 
        end case;
    end if;
end process;

end Behavioral;
