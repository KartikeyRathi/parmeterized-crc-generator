`include "crc_pkg.vh"

module crc_lut_array #(
  
  parameter integer CRC_WIDTH = 32,
  parameter [CRC_WIDTH-1 : 0] POLY = `POLY_CRC32,
  parameter integer NUM_SLICES  = 4  // BYTE wise input data value 
)(
  input wire [8*NUM_SLICES-1 : 0] addr_i, // data can be given in multiples of 8 i.e 8, 16,32,64,128...... //
  
  output wire [NUM_SLICES*CRC_WIDTH-1:0]  crc_o // this will be compressed furthur in crc_core.v to CRC_WIDTH bits by XOR-ing//
);
  
  localparam integer BYTE_WIDTH   = 8;
  localparam integer LUT_DEPTH    = 1 << BYTE_WIDTH;   // 256 — number of table entries
  localparam integer LUT_MAX_ADDR = LUT_DEPTH - 1;     // 255 — max index
  

  reg [CRC_WIDTH-1:0] tables [0:NUM_SLICES-1][0:LUT_MAX_ADDR];
  
  integer k,i,bit_idx;
  reg [CRC_WIDTH-1:0] tmp ;
  
  initial begin : GEN_ALL_TABLES
    
    for (i=0; i <= LUT_DEPTH; i=i+1) begin 
      // CRC CALCULATION LOGIC 
      tmp = {{(CRC_WIDTH-8){1'b0}}, i[7:0]};
      for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
        if (tmp[0])
          tmp = (tmp >> 1) ^ POLY;
        else
          tmp = tmp >> 1;
      end
      tables[0][i] = tmp;
    end
    
    // SLICIING THE TABLES 
    // Slicing recurrence: Tk[i] = (T(k-1)[i] >> 8) ^ T0[ T(k-1)[i][7:0] ]
    
    
    for (k = 1; k < NUM_SLICES; k = k + 1) begin
      for (i = 0; i <= LUT_DEPTH; i = i + 1) begin
        tables[k][i] = (tables[k-1][i] >> 8)
        ^ tables[0][ tables[k-1][i][7:0] ];
      end
    end
    
  end 
  
  // OUTPUt MAPPING of TABLES TO THE output port
  genvar gk;
  generate
    for (gk = 0; gk < NUM_SLICES; gk = gk + 1) begin : LANE
      assign crc_o[gk*CRC_WIDTH +: CRC_WIDTH] = tables[NUM_SLICES-1-gk][ addr_i[gk*8 +: 8] ];
      end
  endgenerate
  
endmodule 
  
  
  
  
  
  