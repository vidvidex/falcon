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

#include "platform.h"
#include "xil_io.h"
#include "xil_printf.h"
#include <stdio.h>

// Base address for AXI-lite control
#define AXI_LITE_BASE 0xA0000000
#define START_REG AXI_LITE_BASE
#define ALGORITHM_SELECT_REG (AXI_LITE_BASE + 4)
#define POLL_DONE_REG (AXI_LITE_BASE + 8)
#define BRAM_ENABLE_REG (AXI_LITE_BASE + 12)

// Base address for accessing device BRAM
#define BRAM_BASE 0xB0000000

#define N 512
#define MESSAGE_BLOCK_COUNT (1 + 7)
#define SIGNATURE_BLOCK_COUNT (2 + 79)

#define BRAM0 0
#define BRAM1 1
#define BRAM2 2
#define BRAM3 3
#define BRAM4 4
#define BRAM5 5
#define BRAM6 6

typedef unsigned __int128 uint128_t;

uint128_t createUint128_t(uint64_t high, uint64_t low);
void load_public_key();
void load_message();
void load_signature();
void bram_write(uint128_t *src, unsigned int bram_id, unsigned int bram_addr, unsigned int count);
void bram_read(unsigned int bram_id, unsigned int bram_addr, uint128_t *dest, unsigned int count);
void start_verification(int block);

uint64_t public_key[N] = {
    4162,  5489,  9391,  6649,  9653,  4881,  3686,  191,   134,   209,   164,   7392,  9905,  8495,  7293,  4815,  3294,  839,   8742,  10592, 8248,  3744,
    6163,  1295,  2169,  5157,  11103, 607,   10884, 8861,  3785,  2289,  9241,  7505,  5670,  6103,  4897,  1033,  5286,  1379,  10307, 641,   8319,  9477,
    3892,  1451,  2889,  9928,  12176, 11807, 2460,  8461,  8496,  10919, 7983,  8422,  6967,  6227,  3056,  4623,  6298,  5439,  8560,  8381,  734,   7393,
    3021,  7927,  8717,  3151,  9823,  9422,  6225,  11787, 4442,  1744,  1977,  8793,  11698, 6676,  4991,  11730, 10672, 4332,  1636,  5963,  7370,  11877,
    5902,  7279,  2631,  5393,  10232, 6038,  6327,  11727, 12059, 3780,  5228,  9144,  11746, 5752,  2103,  9384,  8473,  2373,  4415,  9460,  9163,  9091,
    11614, 10776, 389,   4994,  12116, 12166, 10680, 4121,  4627,  9058,  3149,  6623,  1164,  1840,  2914,  8431,  6235,  2963,  528,   10720, 1478,  6478,
    1821,  4654,  12127, 737,   5896,  9191,  10386, 1782,  3535,  5625,  9292,  7681,  9356,  3219,  6170,  5368,  2464,  7362,  1800,  9627,  10561, 9312,
    11010, 691,   11883, 4994,  4376,  8197,  5674,  518,   3926,  11447, 10647, 947,   9298,  2672,  11190, 2054,  7283,  4058,  12081, 100,   8265,  10632,
    1508,  11487, 3465,  6563,  3042,  9701,  7049,  10832, 3938,  454,   7534,  9593,  7653,  6910,  10880, 2253,  3080,  8254,  9522,  10765, 9859,  479,
    7497,  10067, 4580,  280,   2295,  1394,  1710,  3762,  4816,  9975,  9657,  2350,  1091,  5891,  6702,  8428,  5510,  5582,  11639, 6440,  8870,  4272,
    7797,  4430,  12035, 10113, 2792,  2818,  6637,  10100, 1042,  3535,  6803,  1292,  2259,  12283, 1069,  9339,  8339,  4187,  6091,  9152,  11937, 10549,
    6800,  432,   2119,  8545,  8033,  5009,  6898,  6443,  9455,  4308,  4495,  3006,  973,   1311,  2099,  3551,  2920,  5410,  7656,  2551,  10436, 3799,
    9322,  2896,  1384,  6401,  12144, 8529,  8969,  11439, 1767,  4604,  10224, 4718,  3247,  281,   9523,  10400, 8715,  10876, 3220,  11672, 5876,  11110,
    10251, 3712,  9280,  31,    5873,  6541,  10593, 5896,  7465,  3287,  596,   7014,  6688,  9216,  3211,  7541,  3621,  1627,  11211, 8116,  8223,  7645,
    1624,  1086,  1519,  3508,  4864,  4693,  9995,  11160, 5028,  8917,  10670, 11725, 4407,  7684,  3574,  7769,  11217, 3388,  10437, 8595,  6614,  5040,
    560,   12067, 8406,  766,   12051, 3521,  8279,  11342, 11186, 9536,  6448,  7144,  11283, 4471,  7052,  9841,  5876,  4709,  416,   7331,  8688,  270,
    11453, 8917,  11026, 749,   5376,  8800,  11980, 8403,  3112,  6159,  6873,  8818,  10665, 8260,  1857,  5604,  8087,  5490,  7480,  5503,  11255, 8114,
    6356,  1018,  2077,  4388,  7627,  6154,  5256,  8042,  6668,  6749,  3720,  6601,  7170,  3286,  9454,  1698,  8050,  2181,  10272, 9682,  7891,  9685,
    1280,  11146, 12040, 11577, 4561,  9234,  11516, 10454, 8819,  11330, 6188,  2029,  8474,  5279,  3773,  10890, 1504,  8012,  8613,  9968,  6197,  6906,
    11904, 10787, 4280,  7088,  6238,  2380,  8858,  12020, 11990, 3004,  2930,  8324,  9421,  2053,  7550,  4959,  3675,  173,   3846,  5958,  1616,  5416,
    9632,  1160,  10759, 5679,  12252, 5903,  8376,  5872,  6299,  11074, 1591,  12271, 2305,  12090, 2705,  7179,  5154,  1399,  6109,  6639,  883,   4809,
    2680,  8925,  9882,  6164,  1116,  5931,  4013,  6634,  2550,  4607,  8534,  6742,  7635,  4755,  2636,  3000,  5305,  3789,  3940,  8584,  10314, 7222,
    82,    8384,  3380,  939,   4861,  6147,  6388,  10256, 10522, 5609,  2142,  7634,  3690,  12218, 7314,  3177,  7339,  10847, 7451,  1710,  2574,  8926,
    2865,  12070, 9897,  9950,  12195, 194};
uint64_t message_blocks[MESSAGE_BLOCK_COUNT] = {
    40 + 12, 0x837e8bcfb23c5981, 0x41d5b10176855b9a, 0x92208190cdfbc47f, 0x92e859a168bea29f, 0xa335ead74efe6969, 0x6f57206f6c6c6548, 0x0000000021646c72};
uint64_t signature_blocks[SIGNATURE_BLOCK_COUNT] = {0,
                                                    5000,
                                                    0xa0419223bd4a6372,
                                                    0x1a58ccb4e73f1726,
                                                    0x6639462c2cbc86c9,
                                                    0x81588aba090bd137,
                                                    0x7b848999c8bbb33d,
                                                    0x93bb1ca8aa844b09,
                                                    0x3598b2fb5ba24541,
                                                    0x5933ca988644b44c,
                                                    0x91a579213091ade0,
                                                    0xa6f23b9cece4c224,
                                                    0x652fa2675299f88b,
                                                    0x147cec9df0fb914f,
                                                    0x9aa94adaf9cba4db,
                                                    0xbf52c026d4c9eb36,
                                                    0x61e83d9fea72aff1,
                                                    0xdb39f914f2263f74,
                                                    0xd179686e69e490c5,
                                                    0xdb3cef26159c884a,
                                                    0xe30b8fd9f571f986,
                                                    0x8bc0fb2a6e615482,
                                                    0x213bc49aa283ed2e,
                                                    0x51fec9a331ab7b11,
                                                    0xdddb4cb81c38177f,
                                                    0x4263f8668cded02e,
                                                    0xf8fcb704559002bd,
                                                    0x75edffaa9697a774,
                                                    0xec3076a4129facf7,
                                                    0x2b9adc0ccb79f3d8,
                                                    0xd9e3c28281a88eda,
                                                    0x50786e95d40bd9c6,
                                                    0x660ebb0dc9c1ba2e,
                                                    0xaa16962048a698cd,
                                                    0xf61454095fe116a9,
                                                    0x9599f8b65114d78d,
                                                    0x3fdad68f91239d59,
                                                    0x6499043cb8c3f0e4,
                                                    0x88e847e2a4596d4c,
                                                    0x4762e52bc037304c,
                                                    0x9e28e95d25bbbf1c,
                                                    0x18b8236dcc62f66a,
                                                    0xc51d4bf6c1187c5b,
                                                    0x4b9b65a2d38f0f43,
                                                    0xeb9e6f30b78a0bdf,
                                                    0x53ebc0dcff54b308,
                                                    0x233b9c8d9a61acba,
                                                    0xd0165a3ec920ef41,
                                                    0x539aafa91e4e78ab,
                                                    0xe6d4e6d5d32ee36f,
                                                    0x43ba75bbba4fbbbe,
                                                    0x7867772b1c3d12cf,
                                                    0x77ac7497936dd2b5,
                                                    0x3b736816c3d06163,
                                                    0x10fc810b28572531,
                                                    0x56d1e17b3d7ecdd7,
                                                    0xe0e24cfcf23eccc1,
                                                    0x8e6d7f9018db639f,
                                                    0x6f6bc7491378b6f5,
                                                    0x92ab93ee57218fe5,
                                                    0xd386ca611c772b83,
                                                    0xda7dac6e5a0b8172,
                                                    0xb37706c77dcefb30,
                                                    0x862f374d40d40f51,
                                                    0xb9424d242716e7fd,
                                                    0xd15d05d088b59e15,
                                                    0x6e8f15f9a4e9fcaf,
                                                    0xfc9b3c0b552a12d4,
                                                    0x3311ab8e958de47e,
                                                    0x4e934138aa7c7910,
                                                    0xdedc415068de5eff,
                                                    0xa230de76d328a717,
                                                    0x31de97acbc9a7392,
                                                    0xddc718aee7922902,
                                                    0x53eca64497ba1aae,
                                                    0xc1647658f3205d66,
                                                    0x26f4db4fbb31a55f,
                                                    0xf712ce4b5d578614,
                                                    0x9626ed3400000000,
                                                    0x0000000000000000,
                                                    0x0000000000000000};

// Loads the public key into BRAM0
void load_public_key() {
    for (unsigned int i = 0; i < N / 2; i++) {
        uint128_t temp = createUint128_t(public_key[i], public_key[i + N / 2]);
        bram_write(&temp, BRAM0, i, 1);
    }
}

// Loads the message into BRAM6
void load_message() {
    for (unsigned int i = 0; i < MESSAGE_BLOCK_COUNT; i++) {
        uint128_t temp = createUint128_t(0, message_blocks[i]);
        bram_write(&temp, BRAM6, i, 1);
    }
}

// Loads the signature into BRAM1
void load_signature() {
    for (unsigned int i = 0; i < SIGNATURE_BLOCK_COUNT / 2; i++) {
        uint128_t temp = createUint128_t(signature_blocks[i * 2], signature_blocks[i * 2 + 1]);
        bram_write(&temp, BRAM1, i, 1);
    }
}

// Writes count*128bit of data from src to BRAM bram_id at address bram_addr
void bram_write(uint128_t *src, unsigned int bram_id, unsigned int bram_addr, unsigned int count) {
    volatile uint128_t *bram_ptr = (volatile uint128_t *)BRAM_BASE;
    unsigned int bank_offset = bram_id << 13; // Top 3 bits are BRAM id

    for (unsigned int i = 0; i < count; i++) {
        // Enable BRAM access
        *((int *)BRAM_ENABLE_REG) = 0b1;

        bram_ptr[bank_offset + bram_addr + i] = src[i];

        // Disable BRAM access
        *((int *)BRAM_ENABLE_REG) = 0b0;
    }
}

// Reads count*128 bit of data from BRAM bram_id at address bram_addr to dest
void bram_read(unsigned int bram_id, unsigned int bram_addr, uint128_t *dest, unsigned int count) {
    volatile uint128_t *bram_ptr = (volatile uint128_t *)BRAM_BASE;
    unsigned int bank_offset = bram_id << 13; // Top 3 bits are BRAM id

    for (unsigned int i = 0; i < count; i++) {
        // Enable BRAM access
        *((int *)BRAM_ENABLE_REG) = 0b1;

        dest[i] = bram_ptr[bank_offset + bram_addr + i];

        // Disable BRAM access
        *((int *)BRAM_ENABLE_REG) = 0b0;
    }
}

// Creates an uint128_t from 2 uint64_t values
uint128_t createUint128_t(uint64_t high, uint64_t low) { return ((uint128_t)high << 64) | low; }

// Starts the verification process
// If block is 1, it will block until the verification is done
// If block is 0, it will return immediately after starting the verification
void start_verification(int block) {
    // Set the algorithm to Falcon
    *((int *)ALGORITHM_SELECT_REG) = 0b1;

    // Start the verification process
    *((int *)START_REG) = 0b1;

    // If block is 1 we should wait for the verification to complete
    if (!block)
        return;

    // Wait for the verification to complete
    while (*((int *)POLL_DONE_REG) != 0b1) {
        // Busy wait
    }
}

uint128_t arr[N];

int main() {
    init_platform();

    print("Starting Falcon\n");

    print("Loading keys, signature, and message...\n");
    load_public_key();
    load_signature();
    load_message();
    print("Keys, signature, and message loaded.\n");

    print("Starting verification...\n");
    start_verification(1);

    print("Done\n");

    cleanup_platform();
    return 0;
}
