#include "xil_io.h"
#include "main.h"

typedef enum { SIGN = 0b00, VERIFY = 0b01 } algorithm_t;

// Creates an uint128_t from 2 uint64_t values
uint128_t createUint128_t(uint64_t high, uint64_t low) { return ((uint128_t)high << 64) | low; }

// Enables BRAM access, this allows software to access (read/write) BRAM instead of hardware
void enable_bram_access() {
    // CONTROL_REG[31] controls BRAM access
    *((int *)CONTROL_REG) |= (1 << 31);
}

// Disables BRAM access, this allows hardware to access BRAM instead of software
void disable_bram_access() {
    // CONTROL_REG[31] controls BRAM access
    *((int *)CONTROL_REG) &= ~(1 << 31);
}

// Writes count*128bit of data from src to BRAM bram_id at address bram_addr
void bram_write(uint128_t *src, unsigned int bram_id, unsigned int bram_addr, unsigned int count) {
    volatile uint128_t *bram_ptr = (volatile uint128_t *)BRAM_BASE;
    unsigned int bank_offset = bram_id << 13; // Top 3 bits are BRAM id

    for (unsigned int i = 0; i < count; i++) {
        enable_bram_access();
        bram_ptr[bank_offset + bram_addr + i] = src[i];
        disable_bram_access();
    }
}

// Reads count*128 bit of data from BRAM bram_id at address bram_addr to dest
void bram_read(unsigned int bram_id, unsigned int bram_addr, uint128_t *dest, unsigned int count) {
    volatile uint128_t *bram_ptr = (volatile uint128_t *)BRAM_BASE;
    unsigned int bank_offset = bram_id << 13; // Top 3 bits are BRAM id

    for (unsigned int i = 0; i < count; i++) {
        enable_bram_access();
        dest[i] = bram_ptr[bank_offset + bram_addr + i];
        disable_bram_access();
    }
}

// Starts selected algorithm
void start_algorithm(algorithm_t algorithm) {

    if (algorithm == SIGN)
        print("Starting signing...\n");
    else if (algorithm == VERIFY)
        print("Starting verification...\n");

    // CONTROL_REG[2:1] controls algorithm selection
    *((int *)CONTROL_REG) &= ~(0b11 << 1);     // Clear bits 2:1
    *((int *)CONTROL_REG) |= (algorithm << 1); // Set algorithm

    // CONTROL_REG[0] controls algorithm start
    // Write 1 into it to start the algorithm and then immediately clear it
    *((int *)CONTROL_REG) |= (1 << 0);
    *((int *)CONTROL_REG) &= ~(1 << 0);
}

// Resets hardware
void reset_algorithm() {
    print("Resetting algorithm...\n");
    // CONTROL_REG[3] controls algorithm reset
    // Write 1 into it to reset the algorithm and then immediately clear it
    *((int *)CONTROL_REG) |= (1 << 3);
    *((int *)CONTROL_REG) &= ~(1 << 3);
}

// Waits until algorithm execution is done
void wait_until_done() {
    // OUTPUT_REG[0] will be 1 when the algorithm is done
    while ((*((volatile int *)OUTPUT_REG) & ALGORITHM_DONE_MASK) == 0) {
    }
}

// Returns the status of signing/verification.
// 0 = signature accepted
// 1 = signature rejected
// -1 = not accepted, not rejected (did the algorithm even run?)
int get_status() {
    // OUTPUT_REG[1] == 1 ... signature accepted
    // OUTPUT_REG[2] == 1 ... signature rejected
    int accepted = *((volatile int *)OUTPUT_REG) & SIGNATURE_ACCEPTED_MASK;
    int rejected = *((volatile int *)OUTPUT_REG) & SIGNATURE_REJECTED_MASK;

    if (accepted && !rejected)
        return 0;

    else if (rejected && !accepted)
        return 1;

    return -1;
}