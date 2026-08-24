//============================================================================//
// File: Welch.v
// Author: Ayoub el idrissi Achraf
// Description: Parametrizable Welch-window FIR convolution filter.
//============================================================================//

`timescale 1ns/1ps

module Welch #(
    parameter integer INPUT_SIZE  = 16,
    parameter integer WINDOW_LEN  = 256,
    parameter integer OUTPUT_SIZE = 16
)(
    input                         i_clk,
    input                         i_rst_n,
    input      [INPUT_SIZE-1:0]   i_data,
    input                         i_valid,
    output reg [OUTPUT_SIZE-1:0]  o_data,
    output reg                    o_valid
);

localparam integer ADDR_WIDTH    = (WINDOW_LEN <= 1) ? 1 : $clog2(WINDOW_LEN);
localparam integer PRECISION     = (OUTPUT_SIZE + 1 > ADDR_WIDTH - 1) ? OUTPUT_SIZE + 1 : ADDR_WIDTH - 1;
localparam integer COEFF_WIDTH   = PRECISION + 1;
localparam integer PRODUCT_WIDTH = INPUT_SIZE + COEFF_WIDTH;
localparam integer ACC_WIDTH     = PRODUCT_WIDTH + ADDR_WIDTH;
localparam integer COEFF_SUM_WIDTH = COEFF_WIDTH + ADDR_WIDTH;

// delay_line[0] is x[n-1]; i_data is x[n].  Clearing it implements the
// usual zero-padded FIR response during the first WINDOW_LEN-1 valid samples.
reg [INPUT_SIZE-1:0] delay_line [0:WINDOW_LEN-2];
reg [ACC_WIDTH-1:0]  convolution_sum;
integer convolution_tap;
integer shift_tap;

// Returns the unnormalised Welch coefficient for a fixed FIR tap, in Q(PRECISION).
// w[k] = 1 - (2*k/WINDOW_LEN - 1)^2 = 2*x - x^2, x = 2*k/WINDOW_LEN.
function [COEFF_WIDTH-1:0] welch_raw_coefficient;
    input [ADDR_WIDTH-1:0] tap_index;
    reg [PRECISION:0]     x_int;
    reg [PRECISION+1:0]   term1;
    reg [2*PRECISION+1:0] square_with_rounding;
    reg [PRECISION+1:0]   term2;
    reg [PRECISION+1:0]   coefficient_ext;
    begin
        x_int = tap_index << (PRECISION + 1 - ADDR_WIDTH);
        term1 = {1'b0, x_int} << 1;
        square_with_rounding = x_int * x_int + (1 << (PRECISION - 1));
        term2 = square_with_rounding >> PRECISION;
        coefficient_ext = term1 - term2;
        welch_raw_coefficient = coefficient_ext[COEFF_WIDTH-1:0];
    end
endfunction

// The normalisation denominator is evaluated at elaboration time from the
// same quantised coefficients used by the FIR taps.
function [COEFF_SUM_WIDTH-1:0] welch_coefficient_sum;
    input unused;
    reg [COEFF_SUM_WIDTH-1:0] sum;
    integer index;
    begin
        sum = {COEFF_SUM_WIDTH{1'b0}};
        for (index = 0; index < WINDOW_LEN; index = index + 1)
            sum = sum + welch_raw_coefficient(index[ADDR_WIDTH-1:0]);
        welch_coefficient_sum = sum;
    end
endfunction

localparam [COEFF_SUM_WIDTH-1:0] COEFFICIENT_SUM = welch_coefficient_sum(1'b0);

// Normalised Q(PRECISION) coefficient.  Rounding is applied before division,
// making the coefficient sum approximately one (unity DC gain).
function [COEFF_WIDTH-1:0] welch_coefficient;
    input [ADDR_WIDTH-1:0] tap_index;
    reg [2*PRECISION+1:0] numerator;
    begin
        numerator = welch_raw_coefficient(tap_index);
        numerator = (numerator << PRECISION) + (COEFFICIENT_SUM >> 1);
        welch_coefficient = numerator / COEFFICIENT_SUM;
    end
endfunction

initial begin
    if (WINDOW_LEN < 2 || (WINDOW_LEN & (WINDOW_LEN - 1)) != 0)
        $error("WINDOW_LEN must be a power of two and at least 2");
    if (OUTPUT_SIZE > INPUT_SIZE)
        $error("OUTPUT_SIZE must not exceed INPUT_SIZE");
end

// Combinational sum of the current sample and the retained sample history.
// The coefficient is associated with the tap, never with a frame counter.
always @* begin
    convolution_sum = welch_coefficient({ADDR_WIDTH{1'b0}}) * i_data;
    for (convolution_tap = 1; convolution_tap < WINDOW_LEN; convolution_tap = convolution_tap + 1)
        convolution_sum = convolution_sum +
                          (welch_coefficient(convolution_tap[ADDR_WIDTH-1:0]) * delay_line[convolution_tap-1]);
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_data  <= {OUTPUT_SIZE{1'b0}};
        o_valid <= 1'b0;
        for (shift_tap = 0; shift_tap < WINDOW_LEN-1; shift_tap = shift_tap + 1)
            delay_line[shift_tap] <= {INPUT_SIZE{1'b0}};
    end else begin
        o_valid <= i_valid;
        if (i_valid) begin
            // Divide the Q(PRECISION) sum and saturate rather than wrap.
            if (|convolution_sum[ACC_WIDTH-1:PRECISION+OUTPUT_SIZE])
                o_data <= {OUTPUT_SIZE{1'b1}};
            else
                o_data <= convolution_sum[PRECISION +: OUTPUT_SIZE];
            for (shift_tap = WINDOW_LEN-2; shift_tap > 0; shift_tap = shift_tap - 1)
                delay_line[shift_tap] <= delay_line[shift_tap-1];
            delay_line[0] <= i_data;
        end
    end
end

endmodule
