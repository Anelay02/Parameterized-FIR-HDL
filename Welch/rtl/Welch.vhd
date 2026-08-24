--============================================================================
-- File: Welch.vhd
-- Author: Ayoub el idrissi Achraf
-- Description: Parametrizable Welch-window FIR convolution filter.
--============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
        if left_value > right_value then return left_value; end if;
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

    constant ADDR_WIDTH    : integer := max_int(1, clog2(WINDOW_LEN));
    constant PRECISION     : integer := max_int(OUTPUT_SIZE + 1, ADDR_WIDTH - 1);
    constant COEFF_WIDTH   : integer := PRECISION + 1;
    constant PRODUCT_WIDTH : integer := INPUT_SIZE + COEFF_WIDTH;
    constant ACC_WIDTH     : integer := PRODUCT_WIDTH + ADDR_WIDTH;
    constant COEFF_SUM_WIDTH : integer := COEFF_WIDTH + ADDR_WIDTH;

    type delay_line_t is array (0 to WINDOW_LEN - 2) of unsigned(INPUT_SIZE - 1 downto 0);
    signal delay_line : delay_line_t;
    signal convolution_sum : unsigned(ACC_WIDTH - 1 downto 0);

    -- Unnormalised fixed tap coefficient in unsigned Q(PRECISION).
    function welch_raw_coefficient(tap_index : natural) return unsigned is
        variable x_int                : unsigned(PRECISION downto 0);
        variable term1                : unsigned(PRECISION + 1 downto 0);
        variable square_with_rounding : unsigned(2 * PRECISION + 1 downto 0);
        variable term2                : unsigned(PRECISION + 1 downto 0);
        variable coefficient_ext      : unsigned(PRECISION + 1 downto 0);
    begin
        x_int := shift_left(to_unsigned(tap_index, x_int'length), PRECISION + 1 - ADDR_WIDTH);
        term1 := shift_left(resize(x_int, term1'length), 1);
        square_with_rounding := x_int * x_int +
                                to_unsigned(2 ** (PRECISION - 1), square_with_rounding'length);
        term2 := resize(shift_right(square_with_rounding, PRECISION), term2'length);
        coefficient_ext := term1 - term2;
        return coefficient_ext(COEFF_WIDTH - 1 downto 0);
    end function;

    function welch_coefficient_sum return unsigned is
        variable sum : unsigned(COEFF_SUM_WIDTH - 1 downto 0) := (others => '0');
    begin
        for tap in 0 to WINDOW_LEN - 1 loop
            sum := sum + resize(welch_raw_coefficient(tap), sum'length);
        end loop;
        return sum;
    end function;

    constant COEFFICIENT_SUM : unsigned(COEFF_SUM_WIDTH - 1 downto 0) := welch_coefficient_sum;

    -- Normalised Q(PRECISION) coefficient, rounded to give unity DC gain.
    function welch_coefficient(tap_index : natural) return unsigned is
        variable numerator : unsigned(2 * PRECISION + 1 downto 0);
    begin
        numerator := resize(welch_raw_coefficient(tap_index), numerator'length);
        numerator := shift_left(numerator, PRECISION) + resize(shift_right(COEFFICIENT_SUM, 1), numerator'length);
        return resize(numerator / COEFFICIENT_SUM, COEFF_WIDTH);
    end function;

begin

    assert WINDOW_LEN >= 2 and (2 ** clog2(WINDOW_LEN) = WINDOW_LEN)
        report "WINDOW_LEN must be a power of two and at least 2" severity failure;
    assert OUTPUT_SIZE <= INPUT_SIZE
        report "OUTPUT_SIZE must not exceed INPUT_SIZE" severity failure;

    -- Sum y[n] = sum(w[k] * x[n-k]).  i_data is x[n], and delay_line(k-1)
    -- is x[n-k], so no coefficient or history state is restarted per frame.
    process (i_data, delay_line)
        variable sum : unsigned(ACC_WIDTH - 1 downto 0);
    begin
        sum := resize(welch_coefficient(0) * unsigned(i_data), sum'length);
        for tap in 1 to WINDOW_LEN - 1 loop
            sum := sum + resize(welch_coefficient(tap) * delay_line(tap - 1), sum'length);
        end loop;
        convolution_sum <= sum;
    end process;

    process (i_clk, i_rst_n)
    begin
        if i_rst_n = '0' then
            o_data <= (others => '0');
            o_valid <= '0';
            for tap in 0 to WINDOW_LEN - 2 loop
                delay_line(tap) <= (others => '0');
            end loop;
        elsif rising_edge(i_clk) then
            o_valid <= i_valid;
            if i_valid = '1' then
                if convolution_sum(ACC_WIDTH - 1 downto PRECISION + OUTPUT_SIZE) /=
                   to_unsigned(0, ACC_WIDTH - PRECISION - OUTPUT_SIZE) then
                    o_data <= (others => '1');
                else
                    o_data <= std_logic_vector(convolution_sum(PRECISION + OUTPUT_SIZE - 1 downto PRECISION));
                end if;
                for tap in WINDOW_LEN - 2 downto 1 loop
                    delay_line(tap) <= delay_line(tap - 1);
                end loop;
                delay_line(0) <= unsigned(i_data);
            end if;
        end if;
    end process;

end architecture rtl;
