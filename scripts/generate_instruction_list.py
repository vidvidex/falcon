import math

debug_prints = True


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
        address1=0,
        address2=0,
        mode=0,
        mul_const_selection=0,
        element_count=0,
        decompress_output2=0,
    ):
        fields = [
            ("modules", 16, modules),
            ("empty", 59, 0),
            ("decompress_output2", 3, decompress_output2),
            ("element_count", 4, element_count),
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
        self.instructions.append(self.pack_instruction(fields))

    def sel_module(
        self,
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
        ADD_SUB=0,
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
            | (ADD_SUB << 0)
        )
        return modules

    def treesize(self, n):
        logn = int(math.log2(n))
        return (logn + 1) << logn

    def print_verilog(self, algorithm):

        if algorithm not in ["verify", "sign"]:
            print(f"Error: Unsupported algorithm '{algorithm}'")
            return

        formatted_instructions = [f"128'h{instruction:032x}" for instruction in self.instructions]

        print(f"localparam int {algorithm.upper()}_INSTRUCTION_COUNT = {len(formatted_instructions)};")
        print(f"logic [127:0] {algorithm}_instructions[{algorithm.upper()}_INSTRUCTION_COUNT] = '{{")
        print(",\n".join(formatted_instructions))
        print("};")

    def verify512(self):
        self.instructions = []
        N = 512
        log2N = int(math.log2(N))

        # timestep 1: NTT, DECOMPRESS, HASH_TO_POINT
        self.add_instruction(
            modules=self.sel_module(NTT_INTT=1, DECOMPRESS=1, HASH_TO_POINT=1),
            mode=0,  # NTT mode: NTT
            bank1=0,  # NTT bank1
            bank2=2,  # NTT bank2
            bank3=6,  # hash_to_point input
            bank4=5,  # hash_to_point output
            bank5=1,  # decompress input
            bank6=4,  # decompress output
            decompress_output2=3,  # Second output for decompress
        )

        # timestep 2: NTT
        self.add_instruction(
            modules=self.sel_module(NTT_INTT=1),
            mode=0,  # NTT mode: NTT
            bank1=4,  # NTT bank1
            bank2=1,  # NTT bank2
        )

        # timestep 3: MOD_MULT_Q
        self.add_instruction(
            modules=self.sel_module(MOD_MULT_Q=1),
            bank1=1,  # MOD_MULT_Q input 1
            bank2=2,  # MOD_MULT_Q input 2
            bank3=4,  # MOD_MULT_Q output
            element_count=log2N - 1,
        )

        # timestep 4: INTT
        self.add_instruction(
            modules=self.sel_module(NTT_INTT=1),
            mode=1,  # NTT mode: INTT
            bank1=4,  # NTT bank1
            bank2=1,  # NTT bank2
        )

        # timestep 5: SUB_NORM_SQ
        self.add_instruction(
            modules=self.sel_module(SUB_NORM_SQ=1),
            bank1=5,  # SUB_NORM_SQ input 1
            bank2=1,  # SUB_NORM_SQ input 2
            bank3=3,  # SUB_NORM_SQ input 3
            element_count=log2N - 1,
        )

        self.print_verilog(algorithm="verify")

    def ffsampling(self, N, n, curr_bram, next_free_addr, t0, t1, tree):

        tree_bram = 6

        prev_bram = (curr_bram - 1) % 4 if t1 != 0 else 5  # On top level (when t1 == 0) read from BRAM5
        next_bram = (curr_bram + 1) % 4
        element_count_log2 = int(math.log2(n))

        z0 = next_free_addr[curr_bram]  # Located in curr_bram
        z1 = z0 + n // 2

        tmp = next_free_addr[next_bram]  # Located in next_bram (future z0 and z1)

        next_free_addr[curr_bram] += n

        if n == 1:
            dprint(f"n={n},\tsamplerz\tin_bram={prev_bram},\tin_addr={t0}\ttree_bram={tree_bram},\ttree_addr={tree},\tout_bram={curr_bram},\tout_addr={z0}")
            return

        tree0 = tree + n // 2
        tree1 = tree0 + self.treesize(n // 2) // 2

        if n > 2:  # Replace last split with a copy
            dprint(f"n={n},\tsplit_fft1 \tin_bram={prev_bram},\tin_addr={t1},\tout_bram={curr_bram},\tout_addr={z1}\tsm_size={element_count_log2}")
            self.add_instruction(
                modules=self.sel_module(SPLIT=1),
                bank1=prev_bram,  # Input
                address1=t1,
                bank2=curr_bram,  # Output
                address2=z1,
                element_count=element_count_log2,
            )
        else:
            dprint(f"n={n},\tcopy_split1 \tin_bram={prev_bram},\tin_addr={t1},\tout_bram={curr_bram},\tout_addr={z1}")
            self.add_instruction(
                modules=self.sel_module(COPY=1),
                bank3=prev_bram,  # Input
                address1=t1,
                bank4=curr_bram,  # Output
                address2=z1,
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

        if n > 2:  # Replace last merge with a copy
            dprint(f"n={n},\tmerge_fft1 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z1}\tsm_size={element_count_log2}")
            self.add_instruction(
                modules=self.sel_module(MERGE=1),
                bank1=next_bram,  # Input
                address1=tmp,
                bank2=curr_bram,  # Output
                address2=z1,
                element_count=element_count_log2,
            )
        else:
            dprint(f"n={n},\tcopy_merge1 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z1}")
            self.add_instruction(
                modules=self.sel_module(COPY=1),
                bank3=next_bram,  # Input
                address1=tmp,
                bank4=curr_bram,  # Output
                address2=z1,
                element_count=element_count_log2,
            )

        dprint(f"n={n},\tcopy_t1\tin_bram={prev_bram}\tin_addr={t1}\tout_bram={next_bram}\tout_addr={tmp}")
        self.add_instruction(
            modules=self.sel_module(COPY=1),
            bank3=prev_bram,  # Input
            address1=t1,
            bank4=next_bram,  # Output
            address2=tmp,
            element_count=element_count_log2,
        )

        dprint(f"n={n},\tsub_z1\tin_bram={curr_bram}\tin_addr={z1}\tout_bram={next_bram}\tout_addr={tmp}")
        self.add_instruction(
            modules=self.sel_module(ADD_SUB=1),
            mode=1,  # Subtract mode
            bank1=curr_bram,  # Input1
            address1=z1,
            bank2=next_bram,  # Input2, output
            address2=tmp,
            element_count=element_count_log2,
        )

        dprint(f"n={n},\tmul_tree\tin_bram={tree_bram}\tin_addr={tree}\tout_bram={next_bram}\tout_addr={tmp}")
        self.add_instruction(
            modules=self.sel_module(COMPLEX_MUL=1),
            mode=1,  # Subtract mode
            bank1=next_bram,  # Input1, output
            address1=tmp,
            bank2=tree_bram,  # Input2
            address2=tree,
            element_count=element_count_log2,
        )

        dprint(f"n={n},\tadd_t0\tin_bram={prev_bram}\tin_addr={t0}\tout_bram={next_bram}\tout_addr={tmp}")
        self.add_instruction(
            modules=self.sel_module(ADD_SUB=1),
            mode=0,  # Add mode
            bank1=prev_bram,  # Input1
            address1=t0,
            bank2=next_bram,  # Input2, output
            address2=tmp,
            element_count=element_count_log2,
        )

        if n > 2:  # Replace last split with a copy
            dprint(f"n={n},\tsplit_fft2 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z0}\tsm_size={element_count_log2}")
        else:
            dprint(f"n={n},\tcopy_split2 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z0}")
            self.add_instruction(
                modules=self.sel_module(COPY=1),
                bank3=next_bram,  # Input
                address1=tmp,
                bank4=curr_bram,  # Output
                address2=z0,
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

        if n > 2:  # Replace last merge with a copy
            dprint(f"n={n},\tmerge_fft2 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z0}\tsm_size={element_count_log2}")
        else:
            dprint(f"n={n},\tcopy_merge2 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z0}")
            self.add_instruction(
                modules=self.sel_module(COPY=1),
                bank3=next_bram,  # Input
                address1=tmp,
                bank4=curr_bram,  # Output
                address2=z0,
                element_count=element_count_log2,
            )

    def sign512(self):
        N = 512
        self.instructions = []

        # timestep 1: HASH_TO_POINT
        self.add_instruction(
            modules=self.sel_module(HASH_TO_POINT=1),
            bank3=4,  # HASH_TO_POINT input
            bank4=5,  # HASH_TO_POINT output
        )

        # timestep 2: INT_TO_DOUBLE
        self.add_instruction(
            modules=self.sel_module(INT_TO_DOUBLE=1),
            bank1=5,  # INT_TO_DOUBLE input
            bank2=5,  # INT_TO_DOUBLE output
            element_count=int(math.log2(N // 2)),
        )

        # timestep 3: FFT
        self.add_instruction(
            modules=self.sel_module(FFT_IFFT=1),
            mode=0,  # FFT mode: FFT
            bank1=5,  # FFT bank1
            bank2=4,  # FFT bank2
        )

        # timestep 4: COPY, COMPLEX_MUL
        self.add_instruction(
            modules=self.sel_module(COPY=1, COMPLEX_MUL=1),
            bank1=5,  # COMPLEX_MUL input 1, output
            bank2=1,  # COMPLEX_MUL input 2
            bank3=5,  # COPY input
            bank4=4,  # COPY output
            address1=0,  # Start offset for COPY and COMPLEX_MUL
            address2=0,  # End offset for COPY and COMPLEX_MUL
            element_count=int(math.log2(N // 2)),
        )

        # timestep 5: COMPLEX_MUL, MUL_CONST
        self.add_instruction(
            modules=self.sel_module(COMPLEX_MUL=1, MUL_CONST=1),
            bank1=4,  # COMPLEX_MUL input 1, output
            bank2=3,  # COMPLEX_MUL input 2
            bank3=5,  # MUL_CONST input
            bank4=5,  # MUL_CONST output
            address1=0,  # Start offset for COMPLEX_MUL
            address2=0,  # End offset for COMPLEX_MUL
            mul_const_selection=1,  # Select constant for multiplication
            element_count=int(math.log2(N // 2)),
        )

        # timestep 6: MUL_CONST
        self.add_instruction(
            modules=self.sel_module(MUL_CONST=1),
            bank3=4,  # MUL_CONST input
            bank4=4,  # MUL_CONST output
            mul_const_selection=0,  # Select constant for multiplication
            element_count=int(math.log2(N // 2)),
        )

        # self.ffsampling(N=512, n=512, curr_bram=0, next_free_addr=[256, 256, 256, 256], t0=0, t1=0, tree=0)

        generator.print_verilog(algorithm="sign")


if __name__ == "__main__":

    generator = InstructionGenerator()
    generator.verify512()
    # generator.sign512()
