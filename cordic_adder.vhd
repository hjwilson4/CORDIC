----------------------------------------------------------------------------
--
--  n-Bit Carry Lookahead Adder in VHDL
--
--  This is an implementation of an n-bit carry lookahead adder in VHDL.  
--  It uses a dataflow type architecture with a full adder component.  
--  The n-bit carry lookahead adder is a generic model (parameterized on n).
--
--  Entities included are:
--     FullAdder - full adder
--     Adder     - n-bit carry lookahead adder
--
--  Revision History:
--     14 Jan 23  Hector Wilson     Initial revision. Adapted from provided 
--                                  n-bit ripple carry adder.
--     16 Jan 23  Hector Wilson     Updated to carry lookahead adder.
--
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

--
--  FullAdder entity declaration (used in n-bit adder)
--

entity  FullAdder  is

    port (
        A, B  :  in  std_logic;       --  addends
        Cin   :  in  std_logic;       --  carry in input
        Sum   :  out  std_logic;      --  sum output
        Cout  :  out  std_logic       --  carry out output
    );

end  FullAdder;


--
--  FullAdder dataflow architecture
--

architecture  dataflow  of  FullAdder  is
begin

    Sum <= A xor B xor Cin;
    Cout <= (A and B) or (A and Cin) or (B and Cin);

end  dataflow;


--
--  n-Bit Carry lookahead Adder
--      parameter (wordsize) is the number of bits in the adder
--      and is set to 22 to perform addition/subtraction with Q1.20 values. 
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity  Adder  is

    generic (
        wordsize : integer := 22      -- default width is 22-bits
    );

    port (
        X, Y :  in  std_logic_vector((wordsize - 1) downto 0);    -- addends
        Ci   :  in  std_logic;                                    -- carry in
        S    :  out  std_logic_vector((wordsize - 1) downto 0);   -- sum out
        Co   :  out  std_logic                                    -- carry out
    );

end  Adder;


architecture  archAdder  of  Adder  is

    component  FullAdder
        port (
            A, B  :  in  std_logic;       --  inputs
            Cin   :  in  std_logic;       --  carry in input
            Sum   :  out  std_logic;      --  sum output
            Cout  :  out  std_logic       --  carry out output
        );
    end  component;

    signal  sum_i : std_logic_vector(wordsize-1 downto 0); -- sum 
    signal  gen   : std_logic_vector(wordsize-1 downto 0); -- propogate
    signal  prop  : std_logic_vector(wordsize-1 downto 0); -- generate
    signal  c_i   : std_logic_vector(wordsize downto 0);   -- intermediate carries

begin
    -- calculate sum
    Adders:  for i in  X'range  generate    -- generate wordsize full adders
    begin

        FAx: FullAdder  port map  (X(i), Y(i), c_i(i), sum_i(i));

    end generate;

    -- calculate entity work.cordic_tb and generates
    PropGen: for i in prop'range generate 
    begin 
        prop(i) <= X(i) or Y(i);
        gen(i) <= X(i) and Y(i);
    end generate;
    
    -- calculate carries
    c_i(0) <= Ci;       -- put carry-in into our carry vector
    Carries: for i in 1 to c_i'high generate 
    begin 
        c_i(i) <= gen(i-1) or (prop(i-1) and c_i(i-1));
    end generate;

    S <= sum_i;
    Co <= c_i(c_i'high);                 -- carry out is from carry vector

end  archAdder;