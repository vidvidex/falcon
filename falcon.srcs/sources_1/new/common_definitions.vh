// set this to "true" for gathering area utilization results
`define KEEP_HIERARCHY  "false"

// BRAM
`define BRAM_DATA_WIDTH 128
`define BRAM_ADDR_WIDTH 13

`define BRAM1024_ADDR_WIDTH $clog2(1024)
`define BRAM2048_ADDR_WIDTH $clog2(2048)
`define BRAM5632_ADDR_WIDTH $clog2(5632)

// IEEE 754 double precision:
`define SIGNIFICANT_BITS 52
`define EXPONENT_BITS 11
