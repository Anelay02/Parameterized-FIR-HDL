`timescale 1ns/1ps

// Generates tb_Welch.csv. The input is the deterministic unsigned ramp:
// i_data = (sample_index * SIGNAL_STEP) modulo 2^INPUT_SIZE.
module tb_Welch;
    localparam integer INPUT_SIZE  = 16;
    localparam integer WINDOW_LEN  = 256;
    localparam integer OUTPUT_SIZE = 16;
    localparam integer RUN_SAMPLES = 4 * WINDOW_LEN;
    localparam integer SIGNAL_STEP = 257;

    reg i_clk = 1'b0;
    reg i_rst_n = 1'b0;
    reg [INPUT_SIZE-1:0] i_data = 0;
    reg i_valid = 1'b0;
    wire [OUTPUT_SIZE-1:0] o_data;
    wire o_valid;
    integer sample_index;
    integer csv_file;

    Welch #(
        .INPUT_SIZE(INPUT_SIZE), .WINDOW_LEN(WINDOW_LEN), .OUTPUT_SIZE(OUTPUT_SIZE)
    ) dut (.*);

    always #5 i_clk = ~i_clk;

    initial begin
        csv_file = $fopen("tb_Welch.csv", "w");
        if (csv_file == 0)
            $fatal(1, "Could not open tb_Welch.csv for writing");
        $fdisplay(csv_file, "time_ns,i_data,i_valid,o_valid,o_data");

        repeat (2) @(posedge i_clk);
        i_rst_n <= 1'b1;

        for (sample_index = 0; sample_index < RUN_SAMPLES;
             sample_index = sample_index + 1) begin
            @(negedge i_clk);
            i_data <= (sample_index * SIGNAL_STEP) % (1 << INPUT_SIZE);
            i_valid <= 1'b1;
            @(posedge i_clk);
            #1;
            $fdisplay(csv_file, "%0.3f,%0d,%0d,%0d,%0d",
                      $realtime, i_data, i_valid, o_valid, o_data);
        end

        // One idle cycle records valid deassertion and retained o_data.
        @(negedge i_clk);
        i_valid <= 1'b0;
        @(posedge i_clk);
        #1;
        $fdisplay(csv_file, "%0.3f,%0d,%0d,%0d,%0d",
                  $realtime, i_data, i_valid, o_valid, o_data);
        $fclose(csv_file);
        $display("Wrote tb_Welch.csv with %0d rows", RUN_SAMPLES + 1);
        $finish;
    end
endmodule
