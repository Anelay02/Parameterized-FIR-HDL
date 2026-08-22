--============================================================================--
-- File:        tb_Welch.vhd
-- Author:      Ayoub el idrissi Achraf
-- Description: Testbench for Welch.vhd
-- (Optionally logs input/outputs to a CSV).
--============================================================================--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

  ------------------------
 -- ENTITY DECLARATION --
------------------------

entity tb_Welch is
--  Port ( );
end entity tb_Welch;

  ------------------
 -- ARCHITECTURE --
------------------

architecture tb of tb_Welch is

	component Welch
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
	end component;


	--======================================================================
	-- CSV control
	--======================================================================
	constant CSV_ENABLE     : boolean := true;                -- true = write tb_Welch.csv
	constant CSV_FILE       : string  := "tb_Welch.csv";       -- Name of the CSV

	--======================================================================
	-- Welch parameters
	--======================================================================
	constant WINDOW_LEN     : integer := 256;                  -- Samples per window frame (power of 2 !)
	constant INPUT_SIZE     : integer := 16;
	constant OUTPUT_SIZE    : integer := 16;
	constant CLK_PERIOD_NS  : real    := 10.0;                 -- 100 MHz clock

	--======================================================================
	-- Input stimulus parameters
	--======================================================================
	constant SIGNAL_STEP    : integer := 257;                  -- input = (sample_index * SIGNAL_STEP) mod 2^INPUT_SIZE
	constant RUN_SAMPLES    : integer := 4*WINDOW_LEN;         -- samples to push through (several full windows)

	--======================================================================
	-- Derived parameters (localparam-equivalent)
	--======================================================================
	constant CLK_PERIOD     : time    := CLK_PERIOD_NS * 1 ns;
	constant INPUT_MOD      : integer := 2**INPUT_SIZE;

	--======================================================================
	-- DUT signals
	--======================================================================
	signal clk   : std_logic;
	signal rst_n : std_logic;

	signal i_data  : std_logic_vector(INPUT_SIZE - 1 downto 0);
	signal i_valid : std_logic;

	signal o_data  : std_logic_vector(OUTPUT_SIZE - 1 downto 0);
	signal o_valid : std_logic;

	--======================================================================
	-- Bookkeeping
	--======================================================================
	signal sample_index : integer;   -- index of the next sample to push in

	signal logged_i_data  : std_logic_vector(INPUT_SIZE - 1 downto 0);  -- i_data/i_valid as they
	signal logged_i_valid : std_logic;                                  -- stood on the edge that
	                                                                     -- produced (o_data, o_valid)

	-- File handle for CSV logging (opened/closed conditionally on CSV_ENABLE)
	file csv_fh : text;

begin

	--======================================================================
	-- Main code
	--======================================================================

	  ------------------
	 -- DUT instance  --
	------------------

	dut : Welch
		generic map (
			INPUT_SIZE  => INPUT_SIZE,
			WINDOW_LEN  => WINDOW_LEN,
			OUTPUT_SIZE => OUTPUT_SIZE
		)
		port map (
			i_clk   => clk,
			i_rst_n => rst_n,
			i_data  => i_data,
			i_valid => i_valid,
			o_data  => o_data,
			o_valid => o_valid
		);

	  --------------------
	 -- Clock & reset  --
	--------------------

	clk_gen : process
	begin
		clk <= '0';
		wait for CLK_PERIOD/2.0;
		clk <= '1';
		wait for CLK_PERIOD/2.0;
	end process clk_gen;

	reset_gen : process
	begin
		rst_n <= '0';
		wait for 1.5*CLK_PERIOD;
		rst_n <= '1';
		wait;   -- run once, like Verilog's initial block
	end process reset_gen;

	  ----------------------
	 -- Input driver     --
	-- (deterministic known signal, mirrors welch_model.py)
	----------------------

	driver : process(clk, rst_n)
	begin
		if rst_n = '0' then
			sample_index <= 0;
			i_valid      <= '0';
			i_data       <= (others => '0');
		elsif rising_edge(clk) then
			if sample_index < RUN_SAMPLES then
				i_valid      <= '1';
				i_data       <= std_logic_vector(to_unsigned((sample_index * SIGNAL_STEP) mod INPUT_MOD, INPUT_SIZE));
				sample_index <= sample_index + 1;
			else
				i_valid      <= '0';   -- drop valid once every sample has been pushed
			end if;
		end if;
	end process driver;

	capture : process(clk)
	begin
		if rising_edge(clk) then
			logged_i_data  <= i_data;
			logged_i_valid <= i_valid;
		end if;
	end process capture;


	  ------------------
	 -- CSV logging  --
	------------------

	gen_csv : if CSV_ENABLE generate

		-- Open the file and write the header once
		csv_open : process
			variable l : line;
		begin
			file_open(csv_fh, CSV_FILE, write_mode);
			write(l, string'("time_ns,i_data,i_valid,o_valid,o_data"));
			writeline(csv_fh, l);
			wait;
		end process csv_open;

		-- Log one row per clock, once real data is flowing
		csv_log : process
			variable l : line;
		begin
			wait until rising_edge(clk);
			wait for 1 ns;
			if rst_n = '1' and (logged_i_valid = '1' or sample_index >= RUN_SAMPLES) then
				write(l, integer(now / 1 ns));
				write(l, string'(","));
				write(l, to_integer(unsigned(logged_i_data)));
				write(l, string'(","));
				write(l, to_integer(unsigned'(0 => logged_i_valid)));
				write(l, string'(","));
				write(l, to_integer(unsigned'(0 => o_valid)));
				write(l, string'(","));
				write(l, to_integer(unsigned(o_data)));
				writeline(csv_fh, l);
			end if;
		end process csv_log;

	end generate gen_csv;


	--======================================================================
	-- Run sequence
	--======================================================================

	run_seq : process
	begin
		wait until rst_n = '1';
		for k in 1 to RUN_SAMPLES + 1 loop
			wait until rising_edge(clk);
		end loop;
		wait for 2 ns;

		if CSV_ENABLE then
			file_close(csv_fh);
		end if;
		report "[tb_Welch] simulation done.";
		std.env.finish;
	end process run_seq;

end architecture tb;
