// LUT for the stadard generator polynomials used



// Any CRC width that is a positive multiple of 8 is supported by the design;
// for non-standard widths supply the reflected polynomial directly via the
// POLY parameter.

// All arithmetic uses the *reflected* (LSB-first) polynomial so that the
// shift-register implementation shifts right.

`ifndef CRC_PKG_VH
`define CRC_PKG_VH

`define POLY_CRC8   8'h8C  // reflected form of poly = 0x31
`define POLY_CRC16  16'hA001 // reflected form of poly = 0x8005
`define POLY_CRC32  32'hEDB88320 // reflected form of poly = 0x04C11DB7

`endif // CRC_PKG_VH