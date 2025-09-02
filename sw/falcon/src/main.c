/******************************************************************************
 *
 * Copyright (C) 2009 - 2014 Xilinx, Inc.  All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * Use of the Software is limited solely to applications:
 * (a) running on a Xilinx device, or
 * (b) that interact with a Xilinx device through a bus or interconnect.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * XILINX  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
 * OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * Except as contained in this notice, the name of the Xilinx shall not be used
 * in advertising or otherwise to promote the sale, use or other dealings in
 * this Software without prior written authorization from Xilinx.
 *
 ******************************************************************************/

#include "main.h"
#include "constants.h"
#include "platform.h"
#include "utilities.h"
#include "xil_io.h"
#include "xil_printf.h"
#include <stdio.h>

uint128_t signature128[SIGNATURE_BLOCK_COUNT / 2];
uint8_t *signature8 = (uint8_t *)signature128;

void load_public_key(unsigned int bram_id) {
    for (unsigned int i = 0; i < N / 2; i++) {
        uint128_t temp = createUint128_t(public_key[i], public_key[i + N / 2]);
        bram_write(&temp, bram_id, i, 1);
    }
}

void load_message(unsigned int bram_id) {
    for (unsigned int i = 0; i < MESSAGE_BLOCK_COUNT; i++) {
        uint128_t temp = createUint128_t(0, message_blocks[i]);
        bram_write(&temp, bram_id, i, 1);
    }
}

void load_signature_const(unsigned int bram_id) {
    for (unsigned int i = 0; i < SIGNATURE_BLOCK_COUNT / 2; i++) {
        uint128_t temp = createUint128_t(signature_blocks[i * 2], signature_blocks[i * 2 + 1]);
        bram_write(&temp, bram_id, i, 1);
    }
}

void load_signature(unsigned int bram_id, uint128_t *signature, unsigned int count) { bram_write(signature, bram_id, 0, count); }

// Loads seed into BRAM. Seed is 4x128 bit, loaded to bram_addr, bram_addr+1, +2, +3
void load_seed(uint128_t *seed) { bram_write(seed, BRAM2, SEED_BASE_ADDR, 4); }

void load_into_bram(uint64_t *src, unsigned int bram_id, unsigned int start_addr, unsigned int count) {
    for (unsigned int i = 0; i < count / 2; i++) {
        uint128_t temp = createUint128_t(src[i * 2], src[i * 2 + 1]);
        bram_write(&temp, bram_id, start_addr + i, 1);
    }
}

void verify() {
    print("Preparing for verification...\n");
    print("Loading keys, signature, and message...\n");
    load_public_key(BRAM0);
    load_signature_const(BRAM1);
    // load_signature(BRAM1, signature128, SIGNATURE_BLOCK_COUNT/2);
    load_message(BRAM6);
    print("Keys, signature, and message loaded.\n");

    enable_bram_access();

    start_algorithm(VERIFY);
    wait_until_done();

    int status = get_status();
    if (status == 0)
        print("Signature accepted\n");
    else if (status == 1)
        print("Signature rejected\n");
    else
        print("Not accepted, not rejected (did the algorithm even run?)\n");
}

void sign() {
    print("Preparing for signing...\n");
    print("Loading b00, b01, b10, b11, tree and seed...\n");
    load_into_bram(b00, BRAM0, 0, N);
    load_into_bram(b01, BRAM1, 0, N);
    load_into_bram(b10, BRAM2, 0, N);
    load_into_bram(b11, BRAM3, 0, N);
    load_message(BRAM4);
    load_into_bram(tree, BRAM6, 0, TREE_SIZE);

    uint128_t seed[4] = {createUint128_t(0x1111111111111111, 0x1111111111111111), createUint128_t(0x1111111111111111, 0x1111111111111111),
                         createUint128_t(0x1111111111111111, 0x1111111111111111), createUint128_t(0x1111111111111111, 0x1111111111111111)};
    load_seed(seed);

    print("b00, b01, b10, b11, tree and seed loaded.\n");

    start_algorithm(SIGN);
    wait_until_done();

    bram_read(BRAM0, 256, signature128, SIGNATURE_BLOCK_COUNT / 2);

    int status = get_status();
    if (status == 0) {

        print("Generated signature accepted. Signature is hex ");
        for (int block = 0; block < SIGNATURE_BLOCK_COUNT / 2; block++)
            for (int byte = 0; byte < 16; byte++)
                xil_printf("%02x", signature8[block * 16 + byte]);
        print("\n");
    } else if (status == 1)
        print("Signature rejected\n");
    else
        print("Not accepted, not rejected (did the algorithm even run?)\n");
}

int main() {
    init_platform();

    print("Starting Falcon\n");

    sign();
    reset_algorithm();
    verify();

    print("Done\n");

    cleanup_platform();
    return 0;
}
