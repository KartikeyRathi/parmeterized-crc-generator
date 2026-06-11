// =============================================================================
//  crc_tb.v  —  Self-checking testbench for crc_top
//
//  Fixes vs previous version
//  ─────────────────────────
//  1. Reset held for 10 cycles (not 4) so LUT initial blocks fully settle
//     before any valid traffic is sent.
//  2. Valid/data driven AFTER posedge (non-blocking #1 delay) so they are
//     never coincident with the clock edge — avoids setup-race on fire.
//  3. `while (!x_crc_valid)` replaced with `while (x_crc_valid !== 1'b1)`
//     so an X value does not cause an infinite hang.
//  4. All local reg declarations moved to the top of the initial block
//     (Verilog-2001 requirement — no declarations after statements).
//
//  Test cases
//  ──────────
//  TC1 :  32-bit data  (NUM_SLICES=4 ), CRC-32  — single beat
//  TC2 : 128-bit data  (NUM_SLICES=16), CRC-32  — single beat
//  TC3 :  32-bit data  (NUM_SLICES=4 ), CRC-16  — single beat
//  TC4 :  16-bit data  (NUM_SLICES=2 ), CRC-16  — single beat
//  TC5 :  32-bit x2    (NUM_SLICES=4 ), CRC-32  — 2-beat stream
// =============================================================================

`timescale 1ns/1ps
`include "crc_pkg.vh"

module crc_tb;

// ---------------------------------------------------------------------------
// Clock — 100 MHz
// ---------------------------------------------------------------------------
reg clk;
initial clk = 0;
always #5 clk = ~clk;

// ---------------------------------------------------------------------------
// Score-keeping
// ---------------------------------------------------------------------------
integer pass_count;
integer fail_count;

// ---------------------------------------------------------------------------
// Shared result latches
// ---------------------------------------------------------------------------
reg [31:0] dut_result;
reg [31:0] ref_result;

// ===========================================================================
// DUT INSTANCES — one per unique (CRC_WIDTH, NUM_SLICES) pair
// ===========================================================================

// Instance A — CRC_WIDTH=32, NUM_SLICES=4   used by TC1, TC5
localparam A_CW = 32; localparam A_NS = 4; localparam A_DW = A_NS*8;
reg              a_rst_n, a_valid, a_last;
reg  [A_DW-1:0] a_data;
wire             a_ready, a_crc_valid;
wire [A_CW-1:0] a_crc;

crc_top #(.CRC_WIDTH(A_CW),.POLY(`POLY_CRC32),.NUM_SLICES(A_NS),
          .INIT_VALUE({A_CW{1'b1}}),.FINAL_XOR({A_CW{1'b1}})) u_A (
    .clk_i(clk),.rst_ni(a_rst_n),
    .valid_i(a_valid),.last_i(a_last),.data_i(a_data),
    .ready_o(a_ready),.crc_valid_o(a_crc_valid),.crc_o(a_crc));

// Instance B — CRC_WIDTH=32, NUM_SLICES=16  used by TC2
localparam B_CW = 32; localparam B_NS = 16; localparam B_DW = B_NS*8;
reg              b_rst_n, b_valid, b_last;
reg  [B_DW-1:0] b_data;
wire             b_ready, b_crc_valid;
wire [B_CW-1:0] b_crc;

crc_top #(.CRC_WIDTH(B_CW),.POLY(`POLY_CRC32),.NUM_SLICES(B_NS),
          .INIT_VALUE({B_CW{1'b1}}),.FINAL_XOR({B_CW{1'b1}})) u_B (
    .clk_i(clk),.rst_ni(b_rst_n),
    .valid_i(b_valid),.last_i(b_last),.data_i(b_data),
    .ready_o(b_ready),.crc_valid_o(b_crc_valid),.crc_o(b_crc));

// Instance C — CRC_WIDTH=16, NUM_SLICES=4   used by TC3
localparam C_CW = 16; localparam C_NS = 4; localparam C_DW = C_NS*8;
reg              c_rst_n, c_valid, c_last;
reg  [C_DW-1:0] c_data;
wire             c_ready, c_crc_valid;
wire [C_CW-1:0] c_crc;

crc_top #(.CRC_WIDTH(C_CW),.POLY(`POLY_CRC16),.NUM_SLICES(C_NS),
          .INIT_VALUE({C_CW{1'b1}}),.FINAL_XOR({C_CW{1'b1}})) u_C (
    .clk_i(clk),.rst_ni(c_rst_n),
    .valid_i(c_valid),.last_i(c_last),.data_i(c_data),
    .ready_o(c_ready),.crc_valid_o(c_crc_valid),.crc_o(c_crc));

// Instance D — CRC_WIDTH=16, NUM_SLICES=2   used by TC4
localparam D_CW = 16; localparam D_NS = 2; localparam D_DW = D_NS*8;
reg              d_rst_n, d_valid, d_last;
reg  [D_DW-1:0] d_data;
wire             d_ready, d_crc_valid;
wire [D_CW-1:0] d_crc;

crc_top #(.CRC_WIDTH(D_CW),.POLY(`POLY_CRC16),.NUM_SLICES(D_NS),
          .INIT_VALUE({D_CW{1'b1}}),.FINAL_XOR({D_CW{1'b1}})) u_D (
    .clk_i(clk),.rst_ni(d_rst_n),
    .valid_i(d_valid),.last_i(d_last),.data_i(d_data),
    .ready_o(d_ready),.crc_valid_o(d_crc_valid),.crc_o(d_crc));

// ===========================================================================
//  Golden reference — all internals fixed 32-bit, no variable-width ranges
// ===========================================================================
function automatic [31:0] calc_crc;
    input [1023:0] data;        // up to 128 bytes, byte 0 in [7:0]
    input integer  num_bytes;
    input [31:0]   poly32;      // reflected poly, zero-extended to 32-bit
    input [31:0]   init32;
    input [31:0]   fxor32;
    reg   [31:0]   crc, bval;
    integer        b, bit_i;
begin
    crc = init32;
    for (b = 0; b < num_bytes; b = b + 1) begin
        bval = {24'b0, data[b*8 +: 8]} ^ {24'b0, crc[7:0]};
        crc  = crc >> 8;
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
            if (bval[0]) bval = (bval >> 1) ^ poly32;
            else         bval =  bval >> 1;
        end
        crc = crc ^ bval;
    end
    calc_crc = crc ^ fxor32;
end
endfunction

// ===========================================================================
//  Print one result row
// ===========================================================================
task print_result;
    input [319:0] label;   // 40 chars
    input [31:0]  expected;
    input [31:0]  got;
    input [31:0]  mask;    // 32'hFFFFFFFF=CRC32  32'h0000FFFF=CRC16
begin
    if ((expected & mask) === (got & mask)) begin
        $display("  [PASS]  %-40s | Expected: %h | Got: %h",
                 label, expected & mask, got & mask);
        pass_count = pass_count + 1;
    end else begin
        $display("  [FAIL]  %-40s | Expected: %h | Got: %h  <-- MISMATCH",
                 label, expected & mask, got & mask);
        fail_count = fail_count + 1;
    end
end
endtask

// ===========================================================================
//  MAIN STIMULUS
// ===========================================================================
initial begin : STIM

    // --- All local regs declared first (Verilog-2001) ---
    reg [A_DW-1:0] tc1_din;
    reg [B_DW-1:0] tc2_din;
    reg [C_DW-1:0] tc3_din;
    reg [D_DW-1:0] tc4_din;
    reg [A_DW-1:0] tc5_b0, tc5_b1;
    reg [63:0]     tc5_full;

    pass_count = 0;
    fail_count = 0;

    // ------------------------------------------------------------------
    // 1. Assert all resets, idle all controls
    // ------------------------------------------------------------------
    a_rst_n=0; a_valid=0; a_last=0; a_data=0;
    b_rst_n=0; b_valid=0; b_last=0; b_data=0;
    c_rst_n=0; c_valid=0; c_last=0; c_data=0;
    d_rst_n=0; d_valid=0; d_last=0; d_data=0;

    // ------------------------------------------------------------------
    // 2. Hold reset for 10 cycles so LUT initial blocks fully settle
    //    (the LUT tables[] are filled at time-0 in their own initial
    //    block; 10 cycles of margin guarantees no race with the TB)
    // ------------------------------------------------------------------
    repeat(10) @(posedge clk);

    // ------------------------------------------------------------------
    // 3. Release resets — drive AFTER the clock edge (#1 skew) so
    //    rst_ni is stable well before the next posedge samples it
    // ------------------------------------------------------------------
    #1;
    a_rst_n = 1;
    b_rst_n = 1;
    c_rst_n = 1;
    d_rst_n = 1;

    // One full clean cycle with reset high before any traffic
    @(posedge clk); #1;

    $display("");
    $display("=================================================================");
    $display("          CRC TOP  —  Self-Checking Testbench");
    $display("=================================================================");
    $display("  %-40s   %-10s   %-10s", "Test Case", "Expected", "Got");
    $display("-----------------------------------------------------------------");

    // ================================================================
    // TC1 — 32-bit data, CRC-32, single beat
    //        Bytes (LSB-first): DE AD BE EF
    // ================================================================
    tc1_din = 32'hEF_BE_AD_DE;

    // Drive AFTER clock edge — signals are stable for the full period
    a_data  = tc1_din;
    a_valid = 1'b1;
    a_last  = 1'b1;

    @(posedge clk); #1;   // beat is registered on this edge
    a_valid = 1'b0;
    a_last  = 1'b0;

    // crc_valid_o is a registered output — arrives one cycle later.
    // Poll with === 1'b1 so an X value does not cause infinite loop.
    @(posedge clk);
    while (a_crc_valid !== 1'b1) @(posedge clk);
    dut_result = a_crc;

    ref_result = calc_crc({992'b0, tc1_din}, 4,
                          32'hEDB88320, 32'hFFFFFFFF, 32'hFFFFFFFF);
    print_result("TC1: 32-bit data, CRC-32",
                 ref_result, dut_result, 32'hFFFFFFFF);

    // Wait for instance A to return to idle before TC5 reuses it
    @(posedge clk); #1;

    // ================================================================
    // TC2 — 128-bit data, CRC-32, single beat
    //        Bytes: 00 01 02 ... 0F
    // ================================================================
    tc2_din = 128'h0F0E0D0C_0B0A0908_07060504_03020100;

    b_data  = tc2_din;
    b_valid = 1'b1;
    b_last  = 1'b1;

    @(posedge clk); #1;
    b_valid = 1'b0;
    b_last  = 1'b0;

    @(posedge clk);
    while (b_crc_valid !== 1'b1) @(posedge clk);
    dut_result = b_crc;

    ref_result = calc_crc({896'b0, tc2_din}, 16,
                          32'hEDB88320, 32'hFFFFFFFF, 32'hFFFFFFFF);
    print_result("TC2: 128-bit data, CRC-32",
                 ref_result, dut_result, 32'hFFFFFFFF);

    @(posedge clk); #1;

    // ================================================================
    // TC3 — 32-bit data, CRC-16, single beat
    //        Bytes: CA FE BA BE
    // ================================================================
    tc3_din = 32'hBE_BA_FE_CA;

    c_data  = tc3_din;
    c_valid = 1'b1;
    c_last  = 1'b1;

    @(posedge clk); #1;
    c_valid = 1'b0;
    c_last  = 1'b0;

    @(posedge clk);
    while (c_crc_valid !== 1'b1) @(posedge clk);
    dut_result = {16'b0, c_crc};

    ref_result = calc_crc({992'b0, tc3_din}, 4,
                          32'h0000A001, 32'h0000FFFF, 32'h0000FFFF);
    print_result("TC3: 32-bit data, CRC-16",
                 ref_result, dut_result, 32'h0000FFFF);

    @(posedge clk); #1;

    // ================================================================
    // TC4 — 16-bit data, CRC-16, single beat
    //        Bytes: 12 34
    // ================================================================
    tc4_din = 16'h34_12;

    d_data  = tc4_din;
    d_valid = 1'b1;
    d_last  = 1'b1;

    @(posedge clk); #1;
    d_valid = 1'b0;
    d_last  = 1'b0;

    @(posedge clk);
    while (d_crc_valid !== 1'b1) @(posedge clk);
    dut_result = {16'b0, d_crc};

    ref_result = calc_crc({1008'b0, tc4_din}, 2,
                          32'h0000A001, 32'h0000FFFF, 32'h0000FFFF);
    print_result("TC4: 16-bit data, CRC-16",
                 ref_result, dut_result, 32'h0000FFFF);

    @(posedge clk); #1;

    // ================================================================
    // TC5 — 32-bit x 2 beats, CRC-32, multi-beat stream
    //        Beat-0 bytes : 11 22 33 44
    //        Beat-1 bytes : 55 66 77 88
    //        Reference    : CRC-32 over bytes 11 22 33 44 55 66 77 88
    //
    // Instance A is reused (crc_state was reset to INIT_VALUE after TC1)
    // ================================================================
    tc5_b0   = 32'h44_33_22_11;
    tc5_b1   = 32'h88_77_66_55;
    tc5_full = {tc5_b1, tc5_b0};   // [7:0]=0x11 ... [63:56]=0x88

    // Beat 0 — valid, NOT last
    a_data  = tc5_b0;
    a_valid = 1'b1;
    a_last  = 1'b0;

    @(posedge clk); #1;   // beat 0 registered

    // Beat 1 — valid, last
    a_data  = tc5_b1;
    a_last  = 1'b1;

    @(posedge clk); #1;   // beat 1 registered, crc_valid will fire next cycle
    a_valid = 1'b0;
    a_last  = 1'b0;

    @(posedge clk);
    while (a_crc_valid !== 1'b1) @(posedge clk);
    dut_result = a_crc;

    ref_result = calc_crc({960'b0, tc5_full}, 8,
                          32'hEDB88320, 32'hFFFFFFFF, 32'hFFFFFFFF);
    print_result("TC5: 2-beat 32-bit stream, CRC-32",
                 ref_result, dut_result, 32'hFFFFFFFF);

    // ================================================================
    // Summary
    // ================================================================
    $display("-----------------------------------------------------------------");
    $display("  Result : %0d PASSED,  %0d FAILED  (out of 5 tests)",
             pass_count, fail_count);
    $display("=================================================================");
    if (fail_count == 0)
        $display("  ALL TESTS PASSED");
    else
        $display("  *** FAILURES DETECTED — check MISMATCH lines above ***");
    $display("");
    $finish;
end

// ---------------------------------------------------------------------------
// Watchdog — abort after 20 000 ns
// ---------------------------------------------------------------------------
initial begin
    #20000;
    $display("[WATCHDOG] Simulation timed out — crc_valid never arrived!");
    $finish;
end

endmodule