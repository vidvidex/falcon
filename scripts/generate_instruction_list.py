# Reference model of the instruction sequence for the Falcon hardware accelerator's control unit.
#
# rtl/top/instruction_generator.sv generates the same instructions in hardware. This script writes them to
# mem/tb/instructions_<algorithm><N>.hex, which instruction_generator_tb compares with the hardware.
#
# Usage: python3 scripts/generate_instruction_list.py   (enable debug_prints below to print the instructions)

import math
from pathlib import Path

debug_prints = False  # Enable debug prints
tree_index_print = False  # Additionally print the addresses accessed in the Falcon tree


def dprint(*args, **kwargs):
    if debug_prints:
        print(*args, **kwargs)


class InstructionGenerator:

    def pack_instruction(self, fields):
        instruction = 0
        for name, width, value in fields:
            instruction = (instruction << width) | (value & ((1 << width) - 1))
        return instruction

    def add_instruction(
        self,
        modules=0,
        bank1=0,
        bank2=0,
        bank3=0,
        bank4=0,
        bank5=0,
        bank6=0,
        bank7=0,
        addr1=0,
        addr2=0,
        mode1=0,
        mode2=0,
        element_count=0,
        mul_const_constant=0,
        input_output_addr_same=0,
    ):
        fields = [
            ("modules", 16, modules),
            ("input_output_addr_same", 1, input_output_addr_same),
            ("mul_const_constant", 1, mul_const_constant),
            ("element_count", 4, element_count),
            ("mode2", 1, mode2),
            ("mode1", 1, mode1),
            ("addr2", 13, addr2),
            ("addr1", 13, addr1),
            ("bank7", 3, bank7),
            ("bank6", 3, bank6),
            ("bank5", 3, bank5),
            ("bank4", 3, bank4),
            ("bank3", 3, bank3),
            ("bank2", 3, bank2),
            ("bank1", 3, bank1),
        ]
        self.instructions.append(self.pack_instruction(fields))

    def sel_module(
        self,
        COPY=0,
        HASH_TO_POINT=0,
        INT_TO_DOUBLE=0,
        FFT_IFFT=0,
        NTT_INTT=0,
        COMPLEX_MUL=0,
        MUL_CONST=0,
        SPLIT=0,
        MERGE=0,
        MULT_MOD_Q=0,
        CHECK_BOUND=0,
        DECOMPRESS=0,
        COMPRESS=0,
        ADD_SUB=0,
        SAMPLERZ=0,
    ):
        modules = (
            (COPY << 14)
            | (HASH_TO_POINT << 13)
            | (INT_TO_DOUBLE << 12)
            | (FFT_IFFT << 11)
            | (NTT_INTT << 10)
            | (COMPLEX_MUL << 9)
            | (MUL_CONST << 8)
            | (SPLIT << 7)
            | (MERGE << 6)
            | (MULT_MOD_Q << 5)
            | (CHECK_BOUND << 4)
            | (DECOMPRESS << 3)
            | (COMPRESS << 2)
            | (ADD_SUB << 1)
            | (SAMPLERZ << 0)
        )
        return modules

    def treesize(self, n):
        logn = int(math.log2(n))
        return (logn + 1) << logn

    def write_hex(self, path):
        path.write_text("".join(f"{instruction:018x}\n" for instruction in self.instructions))
        print(f"wrote {path} ({len(self.instructions)} instructions)")

    def verify(self, N):
        self.instructions = []
        log2N = int(math.log2(N))

        # timestep 1: NTT, DECOMPRESS, HASH_TO_POINT
        dprint("NTT DECOMPRESS HASH_TO_POINT")
        self.add_instruction(
            modules=self.sel_module(NTT_INTT=1, DECOMPRESS=1, HASH_TO_POINT=1),
            mode1=0,  # NTT mode1: NTT
            bank1=0,  # NTT bank1
            bank2=2,  # NTT bank2
            bank3=6,  # hash_to_point input
            bank4=5,  # hash_to_point output
            bank5=1,  # decompress input
            bank6=4,  # decompress output 1
            bank7=3,  # decompress output 2
        )

        # timestep 2: NTT
        dprint("NTT")
        self.add_instruction(
            modules=self.sel_module(NTT_INTT=1),
            mode1=0,  # NTT mode1: NTT
            bank1=4,  # NTT bank1
            bank2=1,  # NTT bank2
        )

        # timestep 3: MULT_MOD_Q
        dprint("MULT_MOD_Q")
        mult_mod_q_ntt_input1 = 1 if N == 512 else 4
        mult_mod_q_ntt_input2 = 2 if N == 512 else 0
        self.add_instruction(
            modules=self.sel_module(MULT_MOD_Q=1),
            bank1=mult_mod_q_ntt_input1,  # MULT_MOD_Q input 1
            bank2=mult_mod_q_ntt_input2,  # MULT_MOD_Q input 2
            bank3=6,  # MULT_MOD_Q output
            element_count=log2N - 1,
        )

        # timestep 4: INTT
        dprint("INTT")
        self.add_instruction(
            modules=self.sel_module(NTT_INTT=1),
            mode1=1,  # NTT mode1: INTT
            bank1=6,  # NTT bank1
            bank2=4,  # NTT bank2
        )

        # timestep 5: CHECK_BOUND
        CHECK_BOUND_intt_input = 4 if N == 512 else 6
        dprint("CHECK_BOUND")
        self.add_instruction(
            modules=self.sel_module(CHECK_BOUND=1),
            bank1=5,  # CHECK_BOUND input 1
            bank2=CHECK_BOUND_intt_input,  # CHECK_BOUND input 2
            bank3=3,  # CHECK_BOUND input 3
            element_count=log2N - 1,
        )


    def ffsampling(self, N, n, curr_bram, next_free_addr, t0, t1, tree):
        # Each level of the recursion keeps its z0 and z1 in curr_bram, its child's in next_bram (at tmp), and reads its
        # inputs t0 and t1 from prev_bram. Tree addresses are in elements, the tree BRAM holds two per row.

        tree_bram = 6

        prev_bram = (curr_bram - 1) % 4 if t1 != 0 else (5 if N == 512 else 4)  # On top level (when t1 == 0) read from BRAM5 for N=512 and BRAM4 for N=1024
        next_bram = (curr_bram + 1) % 4
        t0_bram = prev_bram if n < N else (4 if N == 512 else 5)  # On top level of recursion this BRAM is different
        element_count_log2 = int(math.log2(n))

        z0 = next_free_addr[curr_bram]  # Located in curr_bram
        z1 = z0 + n // 2

        tmp = next_free_addr[next_bram]  # Located in next_bram (future z0 and z1)

        next_free_addr[curr_bram] += n

        tree0 = tree + n
        tree1 = tree0 + self.treesize(n // 2)

        def copy_t1():
            dprint(f"n={n},\tcopy_t1\tin_bram={prev_bram}\tin_addr={t1}\tout_bram={next_bram}\tout_addr={tmp}")
            self.add_instruction(
                modules=self.sel_module(COPY=1),
                bank3=prev_bram,  # Input
                addr1=t1,
                bank4=next_bram,  # Output
                addr2=tmp,
                element_count=element_count_log2 - 1,
            )

        def sub_mul_add():
            # tmp = (t1 - z1) * tree + t0
            dprint(f"n={n},\tsub_z1\tin_bram={curr_bram}\tin_addr={z1}\tout_bram={next_bram}\tout_addr={tmp}")
            self.add_instruction(
                modules=self.sel_module(ADD_SUB=1),
                mode2=1,  # Subtract mode1
                bank3=curr_bram,  # Input1
                addr1=z1,
                bank4=next_bram,  # Input2, output
                addr2=tmp,
                element_count=element_count_log2 - 1,
            )

            dprint(f"n={n},\tmul_tree\tin_bram={tree_bram}\tin_addr={tree//2}\tout_bram={next_bram}\tout_addr={tmp}")
            self.add_instruction(
                modules=self.sel_module(COMPLEX_MUL=1),
                bank1=next_bram,  # Input1, output
                addr1=tmp,
                bank2=tree_bram,  # Input2
                addr2=tree // 2,
                element_count=element_count_log2 - 1,
            )
            for i in range(tree, tree + n // 2):
                self.mul_tree_addrs.append(i)

            dprint(f"n={n},\tadd_t0\tin_bram={t0_bram}\tin_addr={t0}\tout_bram={next_bram}\tout_addr={tmp}")
            self.add_instruction(
                modules=self.sel_module(ADD_SUB=1),
                mode2=0,  # Add mode1
                bank3=t0_bram,  # Input1
                addr1=t0,
                bank4=next_bram,  # Input2, output
                addr2=tmp,
                element_count=element_count_log2 - 1,
            )

        if n == 2:
            # The children (n = 1) are single SamplerZ calls. Instead of copying the input to the child and the result
            # back (split and merge of one element), SamplerZ reads its input from next_bram at tmp (where the child's
            # input would be) and writes the result directly to z1 or z0.
            def samplerz(out_addr, leaf_tree):
                dprint(f"n={n},\tsamplerz\tin_bram={next_bram},\tin_addr={tmp}\ttree_addr={leaf_tree},\tout_bram={curr_bram},\tout_addr={out_addr}")
                self.add_instruction(
                    modules=self.sel_module(SAMPLERZ=1),
                    mode1=1 if self.first_samplerz_call else 0,
                    mode2=1 if leaf_tree % 2 == 1 else 0,
                    bank1=next_bram,  # Input, at tmp (fixed address in the control unit)
                    bank2=tree_bram,  # Tree
                    addr2=leaf_tree // 2,
                    bank3=curr_bram,  # Output
                    addr1=out_addr,
                    bank4=3,  # Seed
                )
                self.first_samplerz_call = False
                self.samplerz_tree_addrs.append(leaf_tree)

            copy_t1()  # input of the first child
            samplerz(z1, tree1)
            sub_mul_add()  # input of the second child
            samplerz(z0, tree0)
            return

        dprint(f"n={n},\tsplit_fft1 \tin_bram={prev_bram},\tin_addr={t1},\tout_bram={curr_bram},\tout_addr={z1}\tsm_size={element_count_log2}")
        self.add_instruction(
            modules=self.sel_module(SPLIT=1),
            bank1=prev_bram,  # Input
            addr1=t1,
            bank2=curr_bram,  # Output
            addr2=z1,
            element_count=element_count_log2,
        )

        self.ffsampling(
            N=N,
            n=n // 2,
            curr_bram=next_bram,
            next_free_addr=[next_free_addr[0], next_free_addr[1], next_free_addr[2], next_free_addr[3]],
            t0=z1,
            t1=z1 + n // 4,
            tree=tree1,
        )

        dprint(f"n={n},\tmerge_fft1 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z1}\tsm_size={element_count_log2}")
        self.add_instruction(
            modules=self.sel_module(MERGE=1),
            bank1=next_bram,  # Input
            addr1=tmp,
            bank2=curr_bram,  # Output
            addr2=z1,
            element_count=element_count_log2,
        )

        copy_t1()
        sub_mul_add()

        dprint(f"n={n},\tsplit_fft2 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z0}\tsm_size={element_count_log2}")
        self.add_instruction(
            modules=self.sel_module(SPLIT=1),
            bank1=next_bram,  # Input
            addr1=tmp,
            bank2=curr_bram,  # Output
            addr2=z0,
            element_count=element_count_log2,
        )

        self.ffsampling(
            N=N,
            n=n // 2,
            curr_bram=next_bram,
            next_free_addr=[next_free_addr[0], next_free_addr[1], next_free_addr[2], next_free_addr[3]],
            t0=z0,
            t1=z0 + n // 4,
            tree=tree0,
        )

        dprint(f"n={n},\tmerge_fft2 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z0}\tsm_size={element_count_log2}")
        self.add_instruction(
            modules=self.sel_module(MERGE=1),
            bank1=next_bram,  # Input
            addr1=tmp,
            bank2=curr_bram,  # Output
            addr2=z0,
            element_count=element_count_log2,
        )

    def sign(self, N):
        self.instructions = []
        self.samplerz_tree_addrs = []  # Addresses of tree where samplerz will access
        self.mul_tree_addrs = []  # Addresses of tree where mul with tree will access

        # timestep 1: HASH_TO_POINT
        dprint("HASH_TO_POINT")
        self.add_instruction(
            modules=self.sel_module(HASH_TO_POINT=1),
            bank3=4,  # HASH_TO_POINT input
            bank4=5,  # HASH_TO_POINT output
        )

        # timestep 2: INT_TO_DOUBLE, COPY
        dprint("INT_TO_DOUBLE, COPY")
        saved_hm_address = 2560 if N == 512 else 5632
        self.add_instruction(
            modules=self.sel_module(INT_TO_DOUBLE=1, COPY=1),
            bank1=5,  # INT_TO_DOUBLE input
            bank2=5,  # INT_TO_DOUBLE output
            bank3=5,  # COPY input
            bank4=6,  # COPY output
            addr1=0,  # COPY input offset
            addr2=saved_hm_address,  # COPY output offset
            element_count=int(math.log2(N // 2)),
        )

        # timestep 3: FFT
        dprint("FFT")
        self.add_instruction(
            modules=self.sel_module(FFT_IFFT=1),
            mode1=0,  # FFT mode1: FFT
            bank1=5,  # FFT bank1
            bank2=4,  # FFT bank2
            addr1=0,  # Offset in bank1
            addr2=0,  # Offset in bank2
        )

        # timestep 4: COPY, COMPLEX_MUL
        dprint("COPY COMPLEX_MUL")
        if N == 512:
            self.add_instruction(
                modules=self.sel_module(COPY=1, COMPLEX_MUL=1),
                bank1=5,  # COMPLEX_MUL input 1, output
                bank2=1,  # COMPLEX_MUL input 2
                bank3=5,  # COPY input
                bank4=4,  # COPY output
                addr1=0,  # Start offset for COPY and COMPLEX_MUL
                addr2=0,  # End offset for COPY and COMPLEX_MUL
                element_count=int(math.log2(N // 2)),
            )
        else:
            self.add_instruction(
                modules=self.sel_module(COPY=1, COMPLEX_MUL=1),
                bank1=4,  # COMPLEX_MUL input 1, output
                bank2=1,  # COMPLEX_MUL input 2
                bank3=4,  # COPY input
                bank4=5,  # COPY output
                addr1=0,  # Start offset for COPY and COMPLEX_MUL
                addr2=0,  # End offset for COPY and COMPLEX_MUL
                element_count=int(math.log2(N // 2)),
            )

        # timestep 5: COMPLEX_MUL, MUL_CONST
        dprint("COMPLEX_MUL MUL_CONST")
        if N == 512:
            self.add_instruction(
                modules=self.sel_module(COMPLEX_MUL=1, MUL_CONST=1),
                bank1=4,  # COMPLEX_MUL input 1, output
                bank2=3,  # COMPLEX_MUL input 2
                bank3=5,  # MUL_CONST input
                bank4=5,  # MUL_CONST output
                addr1=0,  # Start offset for COMPLEX_MUL
                addr2=0,  # End offset for COMPLEX_MUL
                mul_const_constant=1,  # Select constant for multiplication
                element_count=int(math.log2(N // 2)),
            )
        else:
            self.add_instruction(
                modules=self.sel_module(COMPLEX_MUL=1, MUL_CONST=1),
                bank1=5,  # COMPLEX_MUL input 1, output
                bank2=3,  # COMPLEX_MUL input 2
                bank3=4,  # MUL_CONST input
                bank4=4,  # MUL_CONST output
                addr1=0,  # Start offset for COMPLEX_MUL
                addr2=0,  # End offset for COMPLEX_MUL
                mul_const_constant=1,  # Select constant for multiplication
                element_count=int(math.log2(N // 2)),
            )

        # timestep 6: MUL_CONST
        timestep6_bank = 4 if N == 512 else 5
        dprint("MUL_CONST")
        self.add_instruction(
            modules=self.sel_module(MUL_CONST=1),
            bank3=timestep6_bank,  # MUL_CONST input
            bank4=timestep6_bank,  # MUL_CONST output
            mul_const_constant=0,  # Select constant for multiplication
            element_count=int(math.log2(N // 2)),
        )

        self.first_samplerz_call = True
        self.ffsampling(N=N, n=N, curr_bram=0, next_free_addr=[N // 2, N // 2, N // 2, N // 2], t0=0, t1=0, tree=0)

        dprint("COPY b00")
        self.add_instruction(
            modules=self.sel_module(COPY=1),
            bank3=0,  # COPY input
            bank4=3,  # COPY output
            addr1=0,  # COPY input offset
            addr2=N // 2,  # COPY output offset
            element_count=int(math.log2(N // 2)),
        )

        dprint("COPY b10")
        self.add_instruction(
            modules=self.sel_module(COPY=1),
            bank3=2,  # COPY input
            bank4=2,  # COPY output
            addr1=0,  # COPY input offset
            addr2=N // 2,  # COPY output offset
            element_count=int(math.log2(N // 2)),
        )

        dprint("COMPLEX_MUL, COPY (1)")
        self.add_instruction(
            modules=self.sel_module(COMPLEX_MUL=1, COPY=1),
            bank1=3,  # COMPLEX_MUL input1, output
            bank2=0,  # COMPLEX_MUL input2
            addr1=N // 2,  # Offset for COMPLEX_MUL input1 and output, COPY input
            addr2=N // 2,  # Offset for COMPLEX_MUL input2, COPY output
            bank3=0,  # COPY input
            bank4=4,  # COPY output
            element_count=int(math.log2(N // 2)),
        )

        dprint("COMPLEX_MUL, COPY (2)")
        self.add_instruction(
            modules=self.sel_module(COMPLEX_MUL=1, COPY=1),
            bank1=2,  # COMPLEX_MUL input1, output
            bank2=0,  # COMPLEX_MUL input2
            addr1=N // 2,  # Offset for COMPLEX_MUL input1 and output, COPY input, output
            addr2=N,  # Offset for COMPLEX_MUL input2
            bank3=0,  # COPY input
            bank4=5,  # COPY output
            element_count=int(math.log2(N // 2)),
            input_output_addr_same=1,  # Both inputs and output of COPY are addr1
        )

        dprint("COMPLEX_MUL, ADD_SUB")
        self.add_instruction(
            modules=self.sel_module(COMPLEX_MUL=1, ADD_SUB=1),
            mode2=0,  # Add mode1
            bank1=4,  # COMPLEX_MUL input1, output
            bank2=1,  # COMPLEX_MUL input2
            addr1=N // 2,  # Offset for COMPLEX_MUL input1 and output, both inputs and output for ADD_SUB
            addr2=0,  # Offset for COMPLEX_MUL input2
            bank3=3,  # ADD_SUB input1
            bank4=2,  # ADD_SUB input2, output
            element_count=int(math.log2(N // 2)),
            input_output_addr_same=1,  # Both inputs and output of ADD_SUB are addr1
        )

        dprint("COMPLEX_MUL")
        self.add_instruction(
            modules=self.sel_module(COMPLEX_MUL=1),
            bank1=5,  # COMPLEX_MUL input1, output
            bank2=3,  # COMPLEX_MUL input2
            addr1=N // 2,  # Offset for COMPLEX_MUL input1 and output
            addr2=0,  # Offset for COMPLEX_MUL input2
            element_count=int(math.log2(N // 2)),
        )

        dprint("IFFT, ADD_SUB")
        self.add_instruction(
            modules=self.sel_module(FFT_IFFT=1, ADD_SUB=1),
            mode1=1,  # IFFT mode1: IFFT
            mode2=0,  # add
            bank1=2,  # FFT bank1
            bank2=3,  # FFT bank2
            addr1=N // 2,  # Offset for FFT bank1, ADD_SUB input
            addr2=N // 2,  # Offset for FFT bank2, ADD_SUB output
            bank3=4,  # ADD_SUB input1
            bank4=5,  # ADD_SUB input2, output
            element_count=int(math.log2(N // 2)),
        )

        dprint("IFFT")
        self.add_instruction(
            modules=self.sel_module(FFT_IFFT=1),
            mode1=1,  # IFFT mode1: IFFT
            bank1=5,  # FFT bank1
            bank2=4,  # FFT bank2
            addr1=N // 2,  # Offset for FFT bank1, ADD_SUB input
            addr2=N // 2,  # Offset for FFT bank2, ADD_SUB output
        )

        dprint("compress")
        compress_t0_bank = 2 if N == 512 else 3
        compress_t1_bank = 5 if N == 512 else 4
        self.add_instruction(
            modules=self.sel_module(COMPRESS=1),
            bank1=compress_t0_bank,  # bank with t0
            bank2=compress_t1_bank,  # bank with t1
            bank3=6,  # bank with hm
            bank4=0,  # output bank
            addr1=N // 2,  # Offset for bank1 (t0), bank2 (t1) and output
            addr2=saved_hm_address,  # Offset for bank3 (hm)
            element_count=int(math.log2(N)),
        )

        if tree_index_print:
            print(f"Indices where samplerz will read tree:")
            print(self.samplerz_tree_addrs)

            print(f"Indices where mul with tree will read tree:")
            print(self.mul_tree_addrs)


if __name__ == "__main__":

    out_dir = Path(__file__).resolve().parent.parent / "mem" / "tb"
    generator = InstructionGenerator()
    for algorithm in ("sign", "verify"):
        for n in (512, 1024):
            getattr(generator, algorithm)(n)
            generator.write_hex(out_dir / f"instructions_{algorithm}{n}.hex")
