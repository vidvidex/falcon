#include <stdio.h>

#define N 1024

// Base address for AXI-lite control
#define AXI_LITE_BASE 0xA0000000
#define CONTROL_REG AXI_LITE_BASE
#define OUTPUT_REG (AXI_LITE_BASE + 4)

// Base address for accessing device BRAM
#define BRAM_BASE 0xB0000000

#define MESSAGE_BLOCK_COUNT (1 + 7)
#define SIGNATURE_BLOCK_COUNT (N == 512 ? 40 : 78)             // ceil((sbytelength-1-40)/16). 16 byte blocks needed to store signature
#define SIGNATURE_HALF_BLOCK_COUNT (SIGNATURE_BLOCK_COUNT * 2) // 8 byte blocks needed to store signature
#define TREE_SIZE (N == 512 ? 5120 : 11264)     // (logn + 1) << logn

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

#define SEED_BASE_ADDR (N == 512) ? 324 : 648
#define GENERATED_SIGNATURE_ADDR (N == 512) ? 256 : 512

typedef unsigned __int128 uint128_t;
