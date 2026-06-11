
// `include "crc_lut_array.v"
`include "crc_pkg.vh"

module crc_core #(
    parameter integer          CRC_WIDTH  = 32,
    parameter [CRC_WIDTH-1:0]  POLY       = `POLY_CRC32,
    parameter integer          NUM_SLICES = 16
)(
  input  wire [NUM_SLICES*8-1:0]  data_i,
    input  wire [CRC_WIDTH-1:0]              crc_i,
    output wire [CRC_WIDTH-1:0]              crc_o
);

    localparam integer BYTE_WIDTH = 8;
    localparam integer LUT_DEPTH  = 1 << BYTE_WIDTH;   // 256
    localparam integer DATA_WIDTH = NUM_SLICES * BYTE_WIDTH;
    localparam integer CRC_BYTES  = CRC_WIDTH  / BYTE_WIDTH;

    // -------------------------------------------------------------------------
    // Step 1: Fold crc_i into the low CRC_BYTES bytes of data
    // -------------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] data_xored;

    genvar gj;
    generate
        for (gj = 0; gj < NUM_SLICES; gj = gj + 1) begin : XOR_IN
            if (gj < CRC_BYTES) begin
                assign data_xored[gj*BYTE_WIDTH +: BYTE_WIDTH] =
                    data_i[gj*BYTE_WIDTH +: BYTE_WIDTH] ^
                    crc_i [gj*BYTE_WIDTH +: BYTE_WIDTH];
            end else begin
                assign data_xored[gj*BYTE_WIDTH +: BYTE_WIDTH] =
                    data_i[gj*BYTE_WIDTH +: BYTE_WIDTH];
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Step 2: LUT array lookup
    // data_xored connects directly — table reversal handled inside crc_lut_array
    // -------------------------------------------------------------------------
    wire [NUM_SLICES*CRC_WIDTH-1:0] lut_out;

    crc_lut_array #(
        .CRC_WIDTH  (CRC_WIDTH),
        .POLY       (POLY),
        .NUM_SLICES (NUM_SLICES)
    ) u_lut_array (
        .addr_i (data_xored),   // direct — no byte swap needed here
        .crc_o  (lut_out)
    );

    // -------------------------------------------------------------------------
    // Step 3: XOR reduction across all NUM_SLICES partial results
    // -------------------------------------------------------------------------
    wire [CRC_WIDTH-1:0] partial [0:NUM_SLICES-1];
    wire [CRC_WIDTH-1:0] xor_acc [0:NUM_SLICES];

    genvar gp;
    generate
        for (gp = 0; gp < NUM_SLICES; gp = gp + 1) begin : PARTIAL
            assign partial[gp] = lut_out[gp*CRC_WIDTH +: CRC_WIDTH];
        end
    endgenerate

    assign xor_acc[0] = {CRC_WIDTH{1'b0}};

    genvar gx;
    generate
        for (gx = 0; gx < NUM_SLICES; gx = gx + 1) begin : XOR_TREE
            assign xor_acc[gx+1] = xor_acc[gx] ^ partial[gx];
        end
    endgenerate

    assign crc_o = xor_acc[NUM_SLICES];

endmodule