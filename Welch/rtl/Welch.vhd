--============================================================================
-- File: Welch.vhd
-- Author: Ayoub el idrissi Achraf
-- Description: Implements a parametrizable Welch FIR filter.
--===========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

    ------------------------
 -- ENTITY DECLARATION --
------------------------

entity Welch is
    generic (
        INPUT_SIZE  : integer := 16;
        WINDOW_LEN  : integer := 256;
        OUTPUT_SIZE : integer := 16
    );
    port (
        i_clk   : in  std_logic;
        i_rst_n : in  std_logic;
        i_data  : in  std_logic_vector(INPUT_SIZE - 1 downto 0);
        i_valid : in  std_logic;
        o_data  : out std_logic_vector(OUTPUT_SIZE - 1 downto 0);
        o_valid : out std_logic
    );
end entity Welch;


architecture rtl of Welch is

    function max_int(left_value : integer; right_value : integer) return integer is
    begin
        if left_value > right_value then
            return left_value;
        end if;
        return right_value;
    end function;

    function clog2(value : integer) return integer is
        variable result : integer := 0;
        variable power  : integer := 1;
    begin
        while power < value loop
            power := power * 2;
            result := result + 1;
        end loop;
        return result;
    end function;

      ----------------
     -- CONSTANTS  --
    ----------------

    constant PRECISION : integer := max_int(OUTPUT_SIZE + 1,clog2(WINDOW_LEN) - 1);
    constant ADDR_WIDTH : integer := max_int(1, clog2(WINDOW_LEN));
    constant COEFF_WIDTH : integer := PRECISION + 1;
    constant PRODUCT_WIDTH : integer := INPUT_SIZE + COEFF_WIDTH;


      -------------
     -- SIGNALS --
    -------------

    signal samples_counter : unsigned(ADDR_WIDTH - 1 downto 0);
    signal x_int : unsigned(PRECISION downto 0);
    signal term1 : unsigned(PRECISION downto 0);
    signal square_with_rounding : unsigned(2 * PRECISION + 1 downto 0);
    signal term2 : unsigned(PRECISION downto 0);
    signal coefficient : unsigned(PRECISION downto 0);
    signal product : unsigned(PRODUCT_WIDTH - 1 downto 0);


begin
    --============================================================================--
    -- Code
    --============================================================================--
    
    assert WINDOW_LEN >= 2 and (2 ** clog2(WINDOW_LEN) = WINDOW_LEN)
        report "WINDOW_LEN must be a power of two and at least 2"
        severity failure;
    assert OUTPUT_SIZE <= INPUT_SIZE
        report "OUTPUT_SIZE must not exceed INPUT_SIZE"
        severity failure;

    process (i_clk, i_rst_n)
    begin
        if i_rst_n = '0' then
            samples_counter <= (others => '0');
        elsif rising_edge(i_clk) and i_valid = '1' then
            samples_counter <= samples_counter + 1;
        end if;
    end process;


        ----------------
     -- COEFFICIENTS --
    ----------------

    x_int <= shift_left(resize(samples_counter, x_int'length),PRECISION + 1 - clog2(WINDOW_LEN));
    term1 <= shift_left(x_int, 1);
    square_with_rounding <= x_int * x_int + to_unsigned(2 ** (PRECISION - 1),square_with_rounding'length);
    term2 <= shift_right(square_with_rounding, PRECISION)(term2'range);
    coefficient <= term1 - term2;
    product <= coefficient * unsigned(i_data);


        -----------
     -- Outputs --
    -----------

    process (i_clk, i_rst_n)
    begin
        if i_rst_n = '0' then
            o_data <= (others => '0');
        elsif rising_edge(i_clk) and i_valid = '1' then
            o_data <= std_logic_vector(product(PRODUCT_WIDTH - 2 downto PRODUCT_WIDTH - 1 - OUTPUT_SIZE));
        end if;
    end process;

    process (i_clk, i_rst_n)
    begin
        if i_rst_n = '0' then
            o_valid <= '0';
        elsif rising_edge(i_clk) then
            o_valid <= i_valid;
        end if;
    end process;


end architecture rtl;
