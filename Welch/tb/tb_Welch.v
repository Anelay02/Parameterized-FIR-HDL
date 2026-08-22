//============================================================================//
// File:    tb_Welch.v
// Author:	Ayoub el idrissi Achraf
// Description: Testbench for Welch.v
// (Optionally logs input/outputs to a CSV).
//============================================================================//

// Defining timescale
`timescale 1ns/1ps

  ////////////////////////
 // MODULE DECLARATION //
////////////////////////

module tb_Welch;

	//======================================================================
	// CSV control
	//======================================================================
	parameter        CSV_ENABLE     = 1;              	// 1 = write tb_Welch.csv
	parameter        CSV_FILE       = "tb_Welch.csv";		// Name of the CSV

	//======================================================================
	// Welch parameters
	//======================================================================
	parameter integer WINDOW_LEN    = 256;             	// Samples per window frame (power of 2 !)
	parameter integer INPUT_SIZE    = 16;
	parameter integer OUTPUT_SIZE   = 16;
	parameter real    CLK_PERIOD_NS = 10.0;             	// 100 MHz clock

	//======================================================================
	// Input stimulus parameters
	//======================================================================
	parameter integer SIGNAL_STEP   = 257;              	// input = (sample_index * SIGNAL_STEP) mod 2^INPUT_SIZE
	parameter integer RUN_SAMPLES   = 4*WINDOW_LEN;     	// samples to push through (several full windows)

	//======================================================================
	// DUT signals
	//======================================================================
	reg                      clk;
	reg                      rst_n;

	reg  [INPUT_SIZE-1:0]    i_data;
	reg                      i_valid;

	wire [OUTPUT_SIZE-1:0]   o_data;
	wire                     o_valid;

	//======================================================================
	// Bookkeeping
	//======================================================================
	integer  sample_index;           // index of the next sample to push in
	integer  csv_file;

	reg [INPUT_SIZE-1:0] logged_i_data;   // i_data/i_valid as they stood on the
	reg                  logged_i_valid;  // edge that produced (o_data, o_valid)

	//======================================================================
	// Main code
	//======================================================================

	  ////////////////////
	 // DUT instance   //
	////////////////////

	Welch #(
		.INPUT_SIZE(INPUT_SIZE),
		.WINDOW_LEN(WINDOW_LEN),
		.OUTPUT_SIZE(OUTPUT_SIZE)
	) dut (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.i_data(i_data),
		.i_valid(i_valid),
		.o_data(o_data),
		.o_valid(o_valid)
	);

	  ////////////////////////
	 // Clock & reset      //
	////////////////////////

	initial clk = 1'b0;
	always #(CLK_PERIOD_NS/2.0) clk = ~clk;

	initial begin
		rst_n   = 1'b0;
		i_valid = 1'b0;
		i_data  = {INPUT_SIZE{1'b0}};
		#(1.5*CLK_PERIOD_NS);
		rst_n = 1'b1;
	end

	  ////////////////////////////////////////
	 // Input driver                       //
	////////////////////////////////////////

	always @(posedge clk or negedge rst_n) begin
		if (~rst_n) begin
			sample_index <= 0;
			i_valid      <= 1'b0;
			i_data       <= {INPUT_SIZE{1'b0}};
		end else if (sample_index < RUN_SAMPLES) begin
			i_valid      <= 1'b1;
			i_data       <= (sample_index * SIGNAL_STEP) & {INPUT_SIZE{1'b1}};
			sample_index <= sample_index + 1;
		end else begin
			i_valid      <= 1'b0;    // drop valid once every sample has been pushed
		end
	end

	always @(posedge clk) begin
		logged_i_data  <= i_data;
		logged_i_valid <= i_valid;
	end


	  ////////////////////
	 // CSV logging    //
	////////////////////

	generate
		if (CSV_ENABLE) begin : gen_csv
			initial begin
				csv_file = $fopen(CSV_FILE, "w");
				$fdisplay(csv_file, "time_ns,i_data,i_valid,o_valid,o_data");
			end

			always @(posedge clk) begin
				#1;
				if (rst_n && (logged_i_valid || sample_index >= RUN_SAMPLES))
					$fdisplay(csv_file, "%0.1f,%0d,%0b,%0b,%0d",
						$realtime, logged_i_data, logged_i_valid, o_valid, o_data);
			end
		end
	endgenerate

	initial begin
		$dumpfile("tb_Welch.vcd");
		$dumpvars(0, tb_Welch);
	end

	//======================================================================
	// Run sequence
	//======================================================================

	initial begin
		@(posedge rst_n);
		repeat (RUN_SAMPLES + 1) @(posedge clk);
		#2; // let the CSV logger (woken by this same edge) finish its row first

		if (CSV_ENABLE) $fclose(csv_file);
		$display("[tb_Welch] simulation done.");
		$finish;
	end


endmodule
