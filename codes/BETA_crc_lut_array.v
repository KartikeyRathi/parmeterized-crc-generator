`include "crc_pkg.vh"

module crc_lut_array #(
  
  parameter integer CRC_WIDTH = 32,
  parameter [CRC_WIDTH-1 : 0] POLY = `POLY_CRC32,
  parameter integer NUM_SLICES  = 4
)(
  input wire [8*NUM_SLICES-1 : 0] addr_i, // data can be given in multiples of 8 i.e 8, 16,32,64,128...... //
  
  output wire [NUM_SLICES*CRC_WIDTH-1:0]  crc_o // this will be compressed furthur in crc_core.v to CRC_WIDTH bits by XOR-ing//
);
  
  localparam integer BYTE_WIDTH   = 8;
  localparam integer LUT_DEPTH    = 1 << BYTE_WIDTH;   // 256 — number of table entries
  localparam integer LUT_MAX_ADDR = LUT_DEPTH - 1;     // 255 — max index
  

  // ---------------------------------------------------------------------------
  // FIX 1 — Race condition: replaced `reg tables` + `initial` block with
  //          `wire tables` driven by continuous assigns calling pure functions.
  //
  //          The original `initial` block raced with the testbench's own
  //          `initial` block at time-0.  If the TB drove valid before the
  //          loop completed, every LUT output was X.  Wire assigns + functions
  //          are resolved at elaboration time — values are present from time-0
  //          with no race possible.
  //
  // FIX 2 — Off-by-one: original loops used `i <= LUT_DEPTH` (257 iters),
  //          writing to tables[k][256] which is outside [0:LUT_MAX_ADDR=255].
  //          Corrected to `i < LUT_DEPTH` (256 iters).
  // ---------------------------------------------------------------------------

  // ---- Function: base table T0[byte_idx] ------------------------------------
  function automatic [CRC_WIDTH-1:0] lut_t0_entry;
    input integer byte_idx;
    integer       bit_i;
    reg    [31:0] tmp32;   // fixed 32-bit — no variable-width ranges
  begin
    tmp32 = {24'b0, byte_idx[7:0]};
    for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
      if (tmp32[0])
        tmp32 = (tmp32 >> 1) ^ {{(32-CRC_WIDTH){1'b0}}, POLY};
      else
        tmp32 = tmp32 >> 1;
    end
    lut_t0_entry = tmp32[CRC_WIDTH-1:0];
  end
  endfunction

  // ---- Function: sliced table Tk[byte_idx], k >= 1 -------------------------
  // Recurrence: Tk[i] = (T(k-1)[i] >> 8) ^ T0[ T(k-1)[i][7:0] ]
  function automatic [CRC_WIDTH-1:0] lut_tk_entry;
    input integer slice;
    input integer byte_idx;
    integer       s;
    reg [CRC_WIDTH-1:0] prev;
  begin
    prev = lut_t0_entry(byte_idx);
    for (s = 1; s <= slice; s = s + 1)
      prev = (prev >> 8) ^ lut_t0_entry(prev[7:0]);
    lut_tk_entry = prev;
  end
  endfunction

  // ---- Wire array replaces the original reg array --------------------------
  wire [CRC_WIDTH-1:0] tables [0:NUM_SLICES-1][0:LUT_MAX_ADDR];

  genvar gi, gsl;
  generate
    // Slice 0 — base table T0
    for (gi = 0; gi < LUT_DEPTH; gi = gi + 1) begin : T0
      assign tables[0][gi] = lut_t0_entry(gi);
    end

    // Slices 1 .. NUM_SLICES-1
    for (gsl = 1; gsl < NUM_SLICES; gsl = gsl + 1) begin : TK
      for (gi = 0; gi < LUT_DEPTH; gi = gi + 1) begin : ENTRY
        assign tables[gsl][gi] = lut_tk_entry(gsl, gi);
      end
    end
  endgenerate
  
  // OUTPUt MAPPING of TABLES TO THE output port
  genvar gk;
  generate
    for (gk = 0; gk < NUM_SLICES; gk = gk + 1) begin : LANE
      assign crc_o[gk*CRC_WIDTH +: CRC_WIDTH] =
        tables[NUM_SLICES-1-gk][ addr_i[gk*8 +: 8] ];
      end
  endgenerate
  
endmodule