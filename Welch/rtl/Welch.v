//============================================================================//
// File:	Welch.v
// Author:	Ayoub el idrissi Achraf
// Description:	Implements a parametrizable Welch FIR filter.
//===========================================================================//

// Defining timescale
`timescale 1ns/1ps

  ////////////////////////
 // MODULE DECLARATION //
////////////////////////

module Welch #(
	parameter integer INPUT_SIZE  = 16,			// Input data width
	parameter integer WINDOW_LEN  = 256,		// Samples per window frame (only powers of 2 !)
	parameter integer OUTPUT_SIZE = 16 			// Output data width
)(
    input                          i_clk,      	// Input clock
    input                          i_rst_n,    	// Asynchronous active low reset
    input      [INPUT_SIZE-1:0]    i_data,     	// Unsigned input data
    input                          i_valid,    	// Valid flag for input data
    output reg [OUTPUT_SIZE-1:0]   o_data,     	// Unsigned windowed output data
    output reg                     o_valid     	// Valid flag for output data
);


  //////////////////
 // LOCALPARAMS  //
//////////////////

localparam integer PRECISION = (OUTPUT_SIZE + 1 > $clog2(WINDOW_LEN) - 1) ? OUTPUT_SIZE + 1 : $clog2(WINDOW_LEN) - 1;
localparam integer ADDR_WIDTH = (WINDOW_LEN <= 1) ? 1 : $clog2(WINDOW_LEN);
localparam integer COEFF_WIDTH = PRECISION + 1;
localparam integer PRODUCT_WIDTH = INPUT_SIZE + COEFF_WIDTH;


  ////////////////////
 // WIRES AND REGS //
////////////////////

reg  [ADDR_WIDTH-1:0] samples_counter;
wire [PRECISION:0] x_int;
wire [PRECISION:0] term1;
wire [2*PRECISION+1:0] square_with_rounding;
wire [PRECISION:0] term2;
wire [PRECISION:0] coefficient;
wire [PRODUCT_WIDTH-1:0] product;


//===========================================================================//
// Code
//===========================================================================//

	initial begin
		if (WINDOW_LEN < 2 || (WINDOW_LEN & (WINDOW_LEN - 1)) != 0)
			$error("WINDOW_LEN must be a power of two and at least 2");
		if (OUTPUT_SIZE > INPUT_SIZE)
			$error("OUTPUT_SIZE must not exceed INPUT_SIZE");
	end

	always @(posedge i_clk or negedge i_rst_n) begin
		if (~i_rst_n)
			samples_counter <= {ADDR_WIDTH{1'b0}};
		else if (i_valid)
			samples_counter <= samples_counter + 1'b1;
	end
	

	//////////////////
	// COEFFICIENTS //
	//////////////////

	assign x_int = samples_counter << (PRECISION + 1 - $clog2(WINDOW_LEN));
	assign term1 = x_int << 1;
	assign square_with_rounding = x_int * x_int + (1 << (PRECISION - 1));
	assign term2 = square_with_rounding >> PRECISION;
	assign coefficient = term1 - term2;
	assign product = coefficient * i_data;


	  /////////////
	 // Outputs //
	/////////////

	always @(posedge i_clk or negedge i_rst_n) begin
		if (~i_rst_n)
			o_data <= {OUTPUT_SIZE{1'b0}};
		else if (i_valid)
			o_data <= product[PRODUCT_WIDTH-2 -: OUTPUT_SIZE];
	end

	always @(posedge i_clk or negedge i_rst_n) begin
		if (~i_rst_n)
			o_valid <= 1'b0;
		else
			o_valid <= i_valid;
	end


endmodule
