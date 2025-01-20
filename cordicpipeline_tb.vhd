----------------------------------------------------------------------------
--
--  16-bit PIPELINED CORDIC CALCULATOR TESTBENCH
--
--  This file contains the testbench for a 16-bit parallel CORDIC calculator. 
--  For each CORDIC function, the file randomly generates 100 inputs on the 
--  scale of (0,2). Every clock cycle (1 us) the testbench sends in a new 
--  input(s) and reads out an output from CORDIC. Since the latency of the 
--  pipelined CORDIC design is 7 clock cycles. We wait a delay before beginning 
--  to test the response since the first output (from the first input) shows up 
--  after 7 us. The testbench has a test array that acts as a FIFO which saves 
--  the correct answer for 7 clocks. Throughput is one 16 bit Q1.14 input every 
--  clock cycle (1 us) and one 16-bit Q1.14 output every clock cycle (1 us).

--  Each of the functions that is tested for a set of x_test,y_test 
--  makes sure that these inputs will not overflow the function before testing 
--  it. For example, we wont check multiplication if x_test*y_test > 2 since 
--  the can only output values in the range (-2,2). Assuming the test values 
--  are in range, the function then checks the absolute value of the difference 
--  between the output (r) and the answer. For hyperbolic functions as well as 
--  arctanh and arctan, if this error is less than 0.2 then it passes the test.
--  For the other functions: (sin,cos,multiply,divide) the error bound is 0.1 so 
--  if the error for these function is less than 0.1 then it passes the test. 
--
--  Lastly, we check a few edge cases for each function that are primarily used 
--  to check the bounds explained in the paragraph above. 
--  For example, we only test values of x for arctanh(x) such that x < 0.8. 
--  Therefore, an edge case that is tested below is x=0.8 for arctanh. 
--
--  Revision History:
--     01 Jan 12  Hector Wilson     Initial revision
--     01 Jan 14  Hector Wilson     Edited error checking for checking certain 
--                                  functions. 
--     01 Jan 15  Hector Wilson     Updated comments. Added arctan and 
--                                  arctanh function testing and update error 
--                                  bound to 0.2 to accomodate. 
--     01 Jan 16  Hector Wilson     Updated comments.  
--     01 Jan 22  Hector Wilson     Updated testbench to test for pipelining.
--     01 Jan 22  Hector Wilson     Added comments. 
--
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;    -- for uniform & trunc functions
use ieee.numeric_std.all;  -- for to_unsigned function

entity cordic_tb is
end cordic_tb;

architecture Behavioral of cordic_tb is
    component cordic 
        port ( 
            x           :   in  std_logic_vector(15 downto 0);
            y           :   in  std_logic_vector(15 downto 0);
            f           :   in  std_logic_vector(4 downto 0);
            CLK         :   in  std_logic;
            r           :   out  std_logic_vector(15 downto 0)
        );
    end component;

-- test signals --------------------
signal x,y,r    :   std_logic_vector(15 downto 0) := (others => '0');
signal f        :   std_logic_vector(4 downto 0) := (others => '0');
signal CLK      :   std_logic := '0';

------------------------------------
-- FUNCTION CODES
------------------------------------
-- slightly different naming scheme used here from the cordic module 
-- so theres no overlapping definitions from the math_real package. 
constant cosine  :   std_logic_vector(4 downto 0) := "00001"; -- cos(x)
constant sine    :   std_logic_vector(4 downto 0) := "00101"; -- sin(x)
constant mul     :   std_logic_vector(4 downto 0) := "00100"; -- x*y
constant coshine :   std_logic_vector(4 downto 0) := "00010"; -- cosh(x)
constant shine   :   std_logic_vector(4 downto 0) := "00110"; -- sinh(x)
constant div     :   std_logic_vector(4 downto 0) := "01100"; -- y/x
constant atan    :   std_logic_vector(4 downto 0) := "01101"; -- tan^-1(x)
constant atanh   :   std_logic_vector(4 downto 0) := "01110"; -- tanh^-1(x)

------------------------------------
-- error bound
-- we use 2 error bounds:
-- 0.1 for multiply, division, cos, and sin
-- 0.2 for cosh, sinh, arctan, arctanh
constant bound1 : std_logic_vector(15 downto 0) := "0000011001100110"; -- 0.1
constant bound2  : std_logic_vector(15 downto 0) := "0000110011001100"; -- 0.2

------------------------------------
-- pipeline delay 
constant delay : time := 7 us;
constant latency : integer := 7;
------------------------------------
-- number of edge cases to check for each function 
constant c_edge : integer := 3;
-- here we create an array of test cases
-- for the edge cases we primarily test the overflow bounds to ensure we aren't
-- testing cases that will cause overflow. We also test an intermediate value for 
-- each function between the bounds. 
type edge_tst is array (0 to c_edge-1) of real;
-- circular edge cases
constant circs   : edge_tst := (real(0.10), real(0.78), real(1.45));
-- linear edge cases
constant lins_x  : edge_tst := (real(0.99), real(1.50), real(1.00));
constant lins_y  : edge_tst := (real(0.99), real(0.74), real(1.99));
-- hyperbolic edge cases 
constant hypers  : edge_tst := (real(0.01), real(0.10), real(1.05));
-- arctan edge cases
constant arctans : edge_tst := (real(1.05), real(1.06), real(1.99));
-- arctanh edge cases 
constant arctanhs: edge_tst := (real(0.01), real(0.10), real(0.80));
------------------------------------
type tst is array(5 downto 0) of signed(15 downto 0);
type tst_r is array(5 downto 0) of real;
signal test : tst;
signal boundary: tst_r;


begin
CLK <= not CLK after 1 us /2; -- set up clock with frequency of 0.5MHz
UUT : cordic 
    port map ( 
        x => x,
        y => y,
        f => f,
        r => r,
        CLK => CLK
    );
process 
    -- set up seed variables for generating random test cases
    variable seedx1, seedx2: integer := 1;  -- seed values for random generator
    variable seedy1, seedy2: integer := 10;
    variable randx: real;              -- random real-number value in range 0 to 2.0
    variable randy: real;
    variable realx: real;
    variable realy: real;
    variable x_test: std_logic_vector(15 downto 0);  -- random 15-bit stimulus on (-2,2)
    variable y_test: std_logic_vector(15 downto 0);
    -- temporary answer will be stored here 
    variable answer: signed(15 downto 0);
    variable answer_r: real;

begin
-- This first loop will check 1000 randomly generate test cases against the CORDIC. If the 
-- randomly generate test case(s) will overflow a specific function then the testing of 
-- that function is skipped for that iteration.
    test <= (others => to_signed(0, 16));
    ----------------------------------------
    -- TEST MULTIPLY FUNCTION
    ---------------------------------------- 
    report "starting multiplication test";
    for i in 0 to 100  loop 
    -- generate random x_test value
    uniform(seedx1,seedx2,randx);
    realx := randx*2; -- go from range (0,1) to (0,2)
    -- convert to 16 bit value for CORDIC
    x_test := std_logic_vector(to_unsigned(integer(trunc(randx*32767)), x_test'length));
    -- generate random y_test value
    uniform(seedy1,seedy2,randy); 
    realy := randy*2; -- go from range (0,1) to (0,2)
    
    -- convert to 16 bit value for CORDIC
    y_test := std_logic_vector(to_unsigned(integer(trunc(randy*32767)), y_test'length));

    answer := to_signed(integer(trunc(realy*realx*16384.0)), answer'length);
    answer_r := realy*realx;
    
    -- input this iteration's generated x_test,y_test into the CORDIC
    x <= x_test;
    y <= y_test;
    f <= mul; -- perform multiplication
    wait for 1 us;
    if boundary(5) < 2.0 and i > latency then -- only want to check if no overflow and 
                                        -- we've past 7 clocks
        assert (abs(signed(r)- test(5)) < signed(bound1))
            report "Test Failure Multiplication Incorrect (Error over 0.1)"
            severity ERROR;
    end if;
    test <= test(4 downto 0) & answer; -- store answer
    boundary <= boundary(4 downto 0) & answer_r; -- boundary for multiplication depends on x*y>2
    end loop;
    
    test <= (others => to_signed(0, 16));
    ----------------------------------------
    -- TEST DIVISION FUNCTION
    ----------------------------------------
    report "starting division test";
    for i in 0 to 100 loop 
    -- generate random x_test value
    uniform(seedx1,seedx2,randx);
    realx := randx*2; -- go from range (0,1) to (0,2)
    -- convert to 16 bit value for CORDIC
    x_test := std_logic_vector(to_unsigned(integer(trunc(randx*32767)), x_test'length));
    -- generate random y_test value
    uniform(seedy1,seedy2,randy); 
    realy := randy*2; -- go from range (0,1) to (0,2)
    
    -- convert to 16 bit value for CORDIC
    y_test := std_logic_vector(to_unsigned(integer(trunc(randy*32767)), y_test'length));


    answer := to_signed(integer(trunc(realy/realx*16384.0)),answer'length);
    answer_r := realy/realx;
    -- input this iteration's generated x_test,y_test into the CORDIC
    x <= x_test;
    y <= y_test;
    f <= div; -- perform division
    wait for 1 us;
    if boundary(5) < 2.0 and i > latency then -- only want to check if no overflow and 
                                         -- we've past 7 clocks
        assert (abs(signed(r)- test(5)) < signed(bound1))
            report "Test Failure Division Incorrect (Error over 0.1)"
            severity ERROR;
    end if;
    test <= test(4 downto 0) & answer; -- store answer
    boundary <= boundary(4 downto 0) & answer_r; -- boundary for division depends on y/x>2
    end loop;

    ----------------------------------------
    -- TEST COSINE FUNCTION
    ----------------------------------------
    report "starting cos test";
    for i in 0 to 100 loop 
    -- generate random x_test value
    uniform(seedx1,seedx2,randx);
    realx := randx*2; -- go from range (0,1) to (0,2)
    -- convert to 16 bit value for CORDIC
    x_test := std_logic_vector(to_unsigned(integer(trunc(randx*32767)), x_test'length));
    
    answer := to_signed(integer(trunc(cos(realx)*16384.0)),answer'length);
    
    -- input this iteration's generated x_test into the CORDIC
    x <= x_test;
    
    f <= cosine; -- perform cos
    wait for 1 us;
    
    -- only want to check if no overflow and we've past 7 clocks
    if boundary(5) < 1.45 and boundary(5) > 0.1 and i > latency then
        assert (abs(signed(r)- test(5)) < signed(bound1))
            report "Test Failure Cos Incorrect (Error over 0.1)"
            severity ERROR;
    end if;
    test <= test(4 downto 0) & answer; -- store answer
    boundary <= boundary(4 downto 0) & realx; -- boundary for cos depends on input x
    end loop;
    
    ----------------------------------------
    -- TEST SINE FUNCTION
    ----------------------------------------
    report "starting sin test";
    for i in 0 to 100 loop 
    -- generate random x_test value
    uniform(seedx1,seedx2,randx);
    realx := randx*2; -- go from range (0,1) to (0,2)
    -- convert to 16 bit value for CORDIC
    x_test := std_logic_vector(to_unsigned(integer(trunc(randx*32767)), x_test'length));

    answer := to_signed(integer(trunc(sin(realx)*16384.0)),answer'length);
    
    -- input this iteration's generated x_test into the CORDIC
    x <= x_test;

    f <= sine; -- perform sine
    wait for 1 us;
    
    -- only want to check if no overflow and we've past 7 clocks
    if boundary(5) < 1.40 and boundary(5) > 0.1 and i > latency then 
        assert (abs(signed(r)- test(5)) < signed(bound1))
            report "Test Failure Sin Incorrect (Error over 0.1)"
            severity ERROR;
    end if;
    test <= test(4 downto 0) & answer; -- store x
    boundary <= boundary(4 downto 0) & realx; -- boundary for sin depends on input x
    end loop;
    
    ----------------------------------------
    -- TEST ARCTAN FUNCTION
    ----------------------------------------
    report "starting arctan test";
    for i in 0 to 100 loop 
    -- generate random x_test value
    uniform(seedx1,seedx2,randx);
    realx := randx*2; -- go from range (0,1) to (0,2)
    -- convert to 16 bit value for CORDIC
    x_test := std_logic_vector(to_unsigned(integer(trunc(randx*32767)), x_test'length));
    
    answer := to_signed(integer(trunc(arctan(realx)*16384.0)),answer'length);
    
    -- input this iteration's generated x_test into the CORDIC
    x <= x_test;

    f <= atan; -- perform arctan
    wait for 1 us;
    if boundary(5) > 1.10 and i > latency then -- only want to check if no overflow and 
                                               -- we've past 7 clocks
        assert (abs(signed(r)- test(5)) < signed(bound2))
            report "Test Failure Arctan Incorrect (Error over 0.2)"
            severity ERROR;
    end if;
    test <= test(4 downto 0) & answer; -- store answer
    boundary <= boundary(4 downto 0) & realx; -- boundary for arctan depends on input x
    end loop;
    
    ----------------------------------------
    -- TEST COSH FUNCTION  
    ---------------------------------------- 
    report "starting cosh test";
    for i in 0 to 100 loop 
    -- generate random x_test value
    uniform(seedx1,seedx2,randx);
    realx := randx*2; -- go from range (0,1) to (0,2)
    -- convert to 16 bit value for CORDIC
    x_test := std_logic_vector(to_unsigned(integer(trunc(randx*32767)), x_test'length));

    answer := to_signed(integer(trunc(cosh(realx)*16384.0)),answer'length);
    
    -- input this iteration's generated x_test into the CORDIC
    x <= x_test;

    f <= coshine; -- perform cosh
    wait for 1 us;
    if boundary(5) < 1.05 and i > latency then -- only want to check if no overflow and 
                                               -- we've past 7 clocks
        assert (abs(signed(r)- test(5)) < signed(bound2))
            report "Test Failure Cosh Incorrect (Error over 0.2)"
            severity ERROR;
    end if;
    test <= test(4 downto 0) & answer; -- store answer
    boundary <= boundary(4 downto 0) & realx; -- boundary for cosh depends on input x
    end loop;

    ----------------------------------------
    -- TEST SINH FUNCTION  
    ---------------------------------------- 
    report "starting sinh test";
    for i in 0 to 100 loop 
    -- generate random x_test value
    uniform(seedx1,seedx2,randx);
    realx := randx*2; -- go from range (0,1) to (0,2)
    -- convert to 16 bit value for CORDIC
    x_test := std_logic_vector(to_unsigned(integer(trunc(randx*32767)), x_test'length));

    answer := to_signed(integer(trunc(sinh(realx)*16384.0)),answer'length);
    
    -- input this iteration's generated x_test into the CORDIC
    x <= x_test;

    f <= shine; --perform sinh
    wait for 1 us;
    if boundary(5) < 1.05 and i > latency then -- only want to check if no overflow and 
                                               -- we've past 7 clocks
        assert (abs(signed(r)- test(5)) < signed(bound2))
            report "Test Failure Sinh Incorrect (Error over 0.2"
            severity ERROR;
    end if;
    test <= test(4 downto 0) & answer; -- store answer
    boundary <= boundary(4 downto 0) & realx; --boundary for sinh depends on input x
    end loop;
    
    ----------------------------------------
    -- TEST ARCTANH FUNCTION  
    ---------------------------------------- 
    report "starting arctanh test";
    for i in 0 to 100 loop 
    -- generate random x_test value
    uniform(seedx1,seedx2,randx);
    realx := randx*2; -- go from range (0,1) to (0,2)
    -- convert to 16 bit value for CORDIC
    x_test := std_logic_vector(to_unsigned(integer(trunc(randx*32767)), x_test'length));
    if realx < 1.0 then -- dont want to compute arctanh(x) if x > 1
        answer := to_signed(integer(trunc(arctanh(realx)*16384.0)),answer'length);
    else 
        answer := to_signed(0,16);
    end if;
    -- input this iteration's generated x_test into the CORDIC
    x <= x_test;

    f <= atanh; -- perform arctanh
    wait for 1 us;
    if boundary(5) < 0.8 and i > latency then  -- only want to check if no overflow and 
                                               -- we've past 7 clocks
        assert (abs(signed(r)- test(5)) < signed(bound2))
            report "Test Failure Arctanh Incorrect (Error over 0.2)"
            severity ERROR;
    end if;
    test <= test(4 downto 0) & answer; -- store answer
    boundary <= boundary(4 downto 0) & realx; -- boundary for arctanh depends on input x
    end loop;
    
    
    
-- This next loop will check a couple of edge cases for each function in 
-- order to ensure proper operation. Most importantly, we check regions 
-- surrounding the overflow bounds listed above. 
    ---------------------------------------- 
    -- TEST EDGE CASES
    ---------------------------------------- 
    -- we will now test a few edge cases for the functions
    report "starting edge cases";
    for i in 0 to c_edge-1 loop 
        -----------------------
        -- CIRCULAR EDGE CASES
        -----------------------
        -- COS EDGE TEST
        answer := to_signed(integer(trunc(cos(circs(i))*16384.0)),answer'length);
        x <= std_logic_vector(to_unsigned(integer(trunc(real(circs(i))*16384)),16));
        f <= cosine;
        wait for delay;
        assert (abs(signed(r) - answer) < signed(bound1))
            report "Test Failure Cos Edge Case Incorrect (Error over 0.1)"
            severity ERROR;
        -- SIN EDGE TEST
        f <= sine;
        wait for 8 us;
        answer := to_signed(integer(trunc(sin(circs(i))*16384.0)),answer'length);
        assert (abs(signed(r) - answer) < signed(bound1))
            report "Test Failure Sin Edge Case Incorrect (Error over 0.1)"
            severity ERROR;
        -----------------------
        -- ARCTAN EDGE TEST
        -----------------------
        answer := to_signed(integer(trunc(arctan(arctans(i))*16384.0)),answer'length);
        x <= std_logic_vector(to_unsigned(integer(trunc(real(arctans(i))*16384)),16));
        f <= atan;
        wait for delay;
        assert (abs(signed(r) - answer) < signed(bound2))
            report "Test Failure Arctan Edge Case Incorrect (Error over 0.2)"
            severity ERROR;
        -----------------------
        -- LINEAR EDGE CASES
        -----------------------
        -- X*Y EDGE TEST
        answer := to_signed(integer(trunc((lins_x(i)*lins_y(i))*16384.0)),answer'length);
        x <= std_logic_vector(to_unsigned(integer(trunc(real(lins_x(i))*16384)),16));
        y <= std_logic_vector(to_unsigned(integer(trunc(real(lins_y(i))*16384)),16));
        f <= mul;
        wait for delay;
        assert (abs(signed(r) - answer) < signed(bound1))
            report "Test Failure Multiplication Edge Case Incorrect (Error over 0.1)"
            severity ERROR;
        -- Y/X EDGE TEST
        f <= div;
        wait for delay;
        answer := to_signed(integer(trunc((lins_y(i)/lins_x(i))*16384.0)),answer'length);
        assert (abs(signed(r) - answer) < signed(bound1))
            report "Test Failure Division Edge Case Incorrect (Error over 0.1)"
            severity ERROR;
        -----------------------
        -- HYPERBOLIC EDGE CASES
        -----------------------
        -- COSH EDGE TEST
        answer := to_signed(integer(trunc(cosh(hypers(i))*16384.0)),answer'length);
        x <= std_logic_vector(to_unsigned(integer(trunc(real(hypers(i))*16384)),16));
        f <= coshine;
        wait for delay;
        assert (abs(signed(r) - answer) < signed(bound2))
            report "Test Failure Cosh Edge Case Incorrect (Error over 0.2)"
            severity ERROR;
        -- SINH EDGE TEST
        f <= shine;
        wait for delay;
        answer := to_signed(integer(trunc(sinh(hypers(i))*16384.0)),answer'length);
        assert (abs(signed(r) - answer) < signed(bound2))
            report "Test Failure Sinh Edge Case Incorrect (Error over 0.2)"
            severity ERROR;
        -----------------------
        -- ARCTANH EDGE TEST
        -----------------------
        answer := to_signed(integer(trunc(arctanh(arctanhs(i))*16384.0)),answer'length);
        x <= std_logic_vector(to_unsigned(integer(trunc(real(arctanhs(i))*16384)),16));
        f <= atanh;
        wait for delay;
        assert (abs(signed(r) - answer) < signed(bound2))
            report "Test Failure Arctanh Edge Case Incorrect (Error over 0.2)"
            severity ERROR;
        
        
    end loop;
    
end process;

end Behavioral;
