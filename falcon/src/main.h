// Base address for AXI-lite control
#define AXI_LITE_BASE 0xA0000000
#define CONTROL_REG AXI_LITE_BASE
#define OUTPUT_REG (AXI_LITE_BASE + 4)
#define DEBUG_REG (AXI_LITE_BASE + 8)
#define DEBUG_OUTPUT_REG (AXI_LITE_BASE + 12)

// Base address for accessing device BRAM
#define BRAM_BASE 0xB0000000

#define N 512
#define MESSAGE_BLOCK_COUNT (1 + 7)
#define SIGNATURE_BLOCK_COUNT (2 + 79)
#define TREE_SIZE 5120

#define BRAM0 0
#define BRAM1 1
#define BRAM2 2
#define BRAM3 3
#define BRAM4 4
#define BRAM5 5
#define BRAM6 6

#define ALGORITHM_DONE_MASK 0b1
#define SIGNATURE_ACCEPTED_MASK 0b10
#define SIGNATURE_REJECTED_MASK 0b100

typedef unsigned __int128 uint128_t;

