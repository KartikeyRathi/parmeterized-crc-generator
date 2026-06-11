`include "crc_pkg.vh"

module crc_top #(
    parameter integer          CRC_WIDTH   = 32,
    parameter [CRC_WIDTH-1:0]  POLY        = `POLY_CRC32,
    parameter integer          NUM_SLICES  = 16,
    parameter [CRC_WIDTH-1:0]  INIT_VALUE  = {CRC_WIDTH{1'b1}},
    parameter [CRC_WIDTH-1:0]  FINAL_XOR   = {CRC_WIDTH{1'b1}}
)(
    input  wire                      clk_i,
    input  wire                      rst_ni,

    input  wire                      valid_i,
    input  wire                      last_i,
    input  wire [NUM_SLICES*8-1:0]   data_i,   // 8 stays — localparam limitation
    output wire                      ready_o,

    output reg                       crc_valid_o,
    output reg  [CRC_WIDTH-1:0]      crc_o
);

    localparam integer BYTE_WIDTH = 8;
    localparam integer DATA_WIDTH = NUM_SLICES * BYTE_WIDTH;   // only change

    reg  [CRC_WIDTH-1:0] crc_state;
    wire [CRC_WIDTH-1:0] crc_next;
    wire                 fire;

    assign ready_o = 1'b1;
    assign fire    = valid_i & ready_o;

    crc_core #(
        .CRC_WIDTH  (CRC_WIDTH),
        .POLY       (POLY),
        .NUM_SLICES (NUM_SLICES)
    ) u_core (
        .data_i (data_i),
        .crc_i  (crc_state),
        .crc_o  (crc_next)
    );

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            crc_state   <= INIT_VALUE;
            crc_o       <= {CRC_WIDTH{1'b0}};
            crc_valid_o <= 1'b0;
        end else begin
            crc_valid_o <= 1'b0;

            if (fire) begin
                if (last_i) begin
                    crc_o       <= crc_next ^ FINAL_XOR;
                    crc_valid_o <= 1'b1;
                    crc_state   <= INIT_VALUE;
                end else begin
                    crc_state <= crc_next;
                end
            end
        end
    end

endmodule