// set this to "true" for gathering area utilization results
`define KEEP_HIERARCHY  "false"

// BRAM
`define BRAM_DATA_WIDTH 128
`define BRAM_ADDR_WIDTH 13
`define SAMPLERZ_READ_DELAY 2

`define BRAM1024_ADDR_WIDTH $clog2(1024)
`define BRAM2048_ADDR_WIDTH $clog2(2048)
`define BRAM3072_ADDR_WIDTH $clog2(3072)
`define BRAM6144_ADDR_WIDTH $clog2(6144)

// IEEE 754 double precision:
`define SIGNIFICANT_BITS 52
`define EXPONENT_BITS 11

// Memory locations
`define SEED_BASE_ADDR (N == 512) ? 802 : 1604

// Constants
// Expected (max) signature length in bytes, sbytelen(depends on N) - HEAD_LEN(1) - SALT_LEN(40)
`define SLEN ((N == 8 ? 52 : N == 512 ? 666 : N == 1024 ? 1280 : 0) - 1 - 40)

// Debugging
// Uncomment this to use empty BRAMs but ones that can be filled with desired debug data (bram0 to bram6)
`define DEBUG_BRAMS
