import math


def pack_instruction(fields):
    instruction = 0
    total_bits = 0
    for name, width, value in fields:
        instruction = (instruction << width) | (value & ((1 << width) - 1))
        total_bits += width
    return instruction


def add_instruction(
    modules=0,
    bank1=0,
    bank2=0,
    bank3=0,
    bank4=0,
    bank5=0,
    bank6=0,
    address1=0,
    address2=0,
    mode=0,
    mul_const_selection=0,
    split_merge_size=0,
    decompress_output2=0,
):
    fields = [
        ("modules", 16, modules),
        ("empty", 59, 0),
        ("decompress_output2", 3, decompress_output2),
        ("split_merge_size", 4, split_merge_size),
        ("mul_const_selection", 1, mul_const_selection),
        ("mode", 1, mode),
        ("address2", 13, address2),
        ("address1", 13, address1),
        ("bank6", 3, bank6),
        ("bank5", 3, bank5),
        ("bank4", 3, bank4),
        ("bank3", 3, bank3),
        ("bank2", 3, bank2),
        ("bank1", 3, bank1),
    ]
    return pack_instruction(fields)


def sel_module(
    BRAM_READ=0,
    BRAM_WRITE=0,
    COPY=0,
    HASH_TO_POINT=0,
    INT_TO_DOUBLE=0,
    FFT_IFFT=0,
    NTT_INTT=0,
    COMPLEX_MUL=0,
    MUL_CONST=0,
    SPLIT=0,
    MERGE=0,
    MOD_MULT_Q=0,
    SUB_NORM_SQ=0,
    DECOMPRESS=0,
    COMPRESS=0,
    ADD=0,
):
    modules = (
        (BRAM_READ << 15)
        | (BRAM_WRITE << 14)
        | (COPY << 13)
        | (HASH_TO_POINT << 12)
        | (INT_TO_DOUBLE << 11)
        | (FFT_IFFT << 10)
        | (NTT_INTT << 9)
        | (COMPLEX_MUL << 8)
        | (MUL_CONST << 7)
        | (SPLIT << 6)
        | (MERGE << 5)
        | (MOD_MULT_Q << 4)
        | (SUB_NORM_SQ << 3)
        | (DECOMPRESS << 2)
        | (COMPRESS << 1)
        | (ADD << 0)
    )
    return modules


def verify512():
    instructions = []

    # timestep 1: NTT, DECOMPRESS, HASH_TO_POINT
    instructions.append(
        add_instruction(
            modules=sel_module(NTT_INTT=1, DECOMPRESS=1, HASH_TO_POINT=1),
            mode=0,  # NTT mode: NTT
            bank1=0,  # NTT bank1
            bank2=2,  # NTT bank2
            bank3=6,  # hash_to_point input
            bank4=5,  # hash_to_point output
            bank5=1,  # decompress input
            bank6=4,  # decompress output
            decompress_output2=3,  # Second output for decompress
        )
    )

    # timestep 2: NTT
    instructions.append(
        add_instruction(
            modules=sel_module(NTT_INTT=1),
            mode=0,  # NTT mode: NTT
            bank1=4,  # NTT bank1
            bank2=1,  # NTT bank2
        )
    )

    # timestep 3: MOD_MULT_Q
    instructions.append(
        add_instruction(
            modules=sel_module(MOD_MULT_Q=1),
            bank1=1,  # MOD_MULT_Q input 1
            bank2=2,  # MOD_MULT_Q input 2
            bank3=4,  # MOD_MULT_Q output
        )
    )

    # timestep 4: INTT
    instructions.append(
        add_instruction(
            modules=sel_module(NTT_INTT=1),
            mode=1,  # NTT mode: INTT
            bank1=4,  # NTT bank1
            bank2=1,  # NTT bank2
        )
    )

    # timestep 5: SUB_NORM_SQ
    instructions.append(
        add_instruction(
            modules=sel_module(SUB_NORM_SQ=1),
            bank1=5,  # SUB_NORM_SQ input 1
            bank2=1,  # SUB_NORM_SQ input 2
            bank3=3,  # SUB_NORM_SQ input 3
        )
    )

    formatted_instructions = [f"128'h{instruction:032x}" for instruction in instructions]

    print(f"localparam int VERIFY_INSTRUCTION_COUNT = {len(formatted_instructions)};")
    print("logic [127:0] verify_instructions[VERIFY_INSTRUCTION_COUNT] = '{")
    print(",\n".join(formatted_instructions))
    print("};")


def ffsampling(N, n, bram, next_free):

    out_bram = bram + 1
    if out_bram >= 4:  # Rotate BRAM use (we don't use % because the first one is always 5)
        out_bram = 0

    if N == n and N == 512:  # For N=512 we'll skip BRAM0 and go straight to BRAM1, so the rest is the same as for N=1024
        out_bram = 1
        next_free[0] = 1536  # BRAM0 will have an empty spot where z1 1024 would go

    if n == 1:
        print(f"n={n},\tbram={bram}\t\tsamplerz")
        return

    in_addr = next_free[bram] - n * 2 + n // 2 if bram < 4 else 0  # First iteration is special case (0), for others take output address of previous + n/2
    out_addr = 512 if n >= 128 else next_free[out_bram]
    split_merge_size = int(math.log2(n))

    next_free[out_bram] += n

    print(
        f"n={n},\tsplit_fft \tin_bram={bram},\tin_addr={in_addr},\tout_bram={out_bram},\tout_addr={out_addr}\tsplit_merge_size={split_merge_size}"
    )

    ffsampling(N=N, n=n // 2, bram=out_bram, next_free=next_free)

    print(f"n={n},\tbram={bram},\t\tmerge_fft")

    print(f"n={n},\tbram={bram},\t\tcopy, ...")

    print(f"n={n},\tbram={bram},\t\tsplit_fft")

    ffsampling(N=N, n=n // 2, bram=out_bram, next_free=next_free)

    print(f"n={n},\tbram={bram},\t\tmerge_fft")


def sign512():
    instructions = []

    # timestep 1: HASH_TO_POINT
    instructions.append(
        add_instruction(
            modules=sel_module(HASH_TO_POINT=1),
            bank3=4,  # HASH_TO_POINT input
            bank4=5,  # HASH_TO_POINT output
        )
    )

    # timestep 2: INT_TO_DOUBLE
    instructions.append(
        add_instruction(
            modules=sel_module(INT_TO_DOUBLE=1),
            bank1=5,  # INT_TO_DOUBLE input
            bank2=5,  # INT_TO_DOUBLE output
        )
    )

    # timestep 3: FFT
    instructions.append(
        add_instruction(
            modules=sel_module(FFT_IFFT=1),
            mode=0,  # FFT mode: FFT
            bank1=5,  # FFT bank1
            bank2=4,  # FFT bank2
        )
    )

    # timestep 4: COPY, COMPLEX_MUL
    instructions.append(
        add_instruction(
            modules=sel_module(COPY=1, COMPLEX_MUL=1),
            bank1=5,  # COMPLEX_MUL input 1, output
            bank2=1,  # COMPLEX_MUL input 2
            bank3=5,  # COPY input
            bank4=4,  # COPY output
        )
    )

    # timestep 5: COMPLEX_MUL, MUL_CONST
    instructions.append(
        add_instruction(
            modules=sel_module(COMPLEX_MUL=1, MUL_CONST=1),
            bank1=4,  # COMPLEX_MUL input 1, output
            bank2=3,  # COMPLEX_MUL input 2
            bank3=5,  # MUL_CONST input
            bank4=5,  # MUL_CONST output
            mul_const_selection=1,  # Select constant for multiplication
        )
    )

    # timestep 6: MUL_CONST
    instructions.append(
        add_instruction(
            modules=sel_module(MUL_CONST=1),
            bank3=4,  # MUL_CONST input
            bank4=4,  # MUL_CONST output
            mul_const_selection=0,  # Select constant for multiplication
        )
    )

    ffsampling(N=512, n=512, bram=5, next_free=[512, 512, 512, 512])

    formatted_instructions = [f"128'h{instruction:032x}" for instruction in instructions]

    print(f"localparam int SIGN_INSTRUCTION_COUNT = {len(formatted_instructions)};")
    print("logic [127:0] sign_instructions[SIGN_INSTRUCTION_COUNT] = '{")
    print(",\n".join(formatted_instructions))
    print("};")


if __name__ == "__main__":
    # verify512()
    sign512()
