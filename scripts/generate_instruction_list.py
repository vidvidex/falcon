import math

debug_prints = False
tree_index_print = False


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
        addr1=0,
        addr2=0,
        mode=0,
        mul_const_selection=0,
        element_count=0,
        decompress_output2=0,
        input_output_addr_same=0,
        add_sub_mode=0,
    ):
        fields = [
            ("modules", 16, modules),
            ("empty", 56, 0),
            ("add_sub_mode", 1, add_sub_mode),
            ("input_output_addr_same", 1, input_output_addr_same),
            ("decompress_output2", 3, decompress_output2),
            ("element_count", 4, element_count),
            ("mul_const_selection", 1, mul_const_selection),
            ("mode", 1, mode),
            ("addr2", 13, addr2),
            ("addr1", 13, addr1),
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
        SAMPLERZ=0,
    ):
        modules = (
            (BRAM_READ << 16)
            | (BRAM_WRITE << 15)
            | (COPY << 14)
            | (HASH_TO_POINT << 13)
            | (INT_TO_DOUBLE << 12)
            | (FFT_IFFT << 11)
            | (NTT_INTT << 10)
            | (COMPLEX_MUL << 9)
            | (MUL_CONST << 8)
            | (SPLIT << 7)
            | (MERGE << 6)
            | (MOD_MULT_Q << 5)
            | (SUB_NORM_SQ << 4)
            | (DECOMPRESS << 3)
            | (COMPRESS << 2)
            | (ADD_SUB << 1)
            | (SAMPLERZ << 0)
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
        dprint("NTT DECOMPRESS HASH_TO_POINT")
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
        dprint("NTT")
        self.add_instruction(
            modules=self.sel_module(NTT_INTT=1),
            mode=0,  # NTT mode: NTT
            bank1=4,  # NTT bank1
            bank2=1,  # NTT bank2
        )

        # timestep 3: MOD_MULT_Q
        dprint("MOD_MULT_Q")
        self.add_instruction(
            modules=self.sel_module(MOD_MULT_Q=1),
            bank1=1,  # MOD_MULT_Q input 1
            bank2=2,  # MOD_MULT_Q input 2
            bank3=4,  # MOD_MULT_Q output
            element_count=log2N - 1,
        )

        # timestep 4: INTT
        dprint("INTT")
        self.add_instruction(
            modules=self.sel_module(NTT_INTT=1),
            mode=1,  # NTT mode: INTT
            bank1=4,  # NTT bank1
            bank2=1,  # NTT bank2
        )

        # timestep 5: SUB_NORM_SQ
        dprint("SUB_NORM_SQ")
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

            # tree // 2 here because "tree" refers to the address in original array (1 element per row), but our BRAM has 2 per row
            dprint(f"n={n},\tsamplerz\tin_bram={prev_bram},\tin_addr={t0}\ttree_bram={tree_bram},\ttree_addr={tree//2},{'high' if tree % 2 == 0 else 'low'},\tout_bram={curr_bram},\tout_addr={z0}")
            self.add_instruction(
                modules=self.sel_module(SAMPLERZ=1),
                mode=1 if self.first_samplerz_call else 0,
                add_sub_mode=1 if tree % 2 == 1 else 0,
                bank1=prev_bram,  # Input
                addr1=t0,
                bank2=tree_bram,  # Tree
                addr2=tree // 2,
                bank3=curr_bram,  # Output
                bank4=2,  # Seed
            )
            self.first_samplerz_call = False
            self.samplerz_tree_addrs.append(tree)
            return

        tree0 = tree + n
        tree1 = tree0 + self.treesize(n // 2)

        if n > 2:
            dprint(f"n={n},\tsplit_fft1 \tin_bram={prev_bram},\tin_addr={t1},\tout_bram={curr_bram},\tout_addr={z1}\tsm_size={element_count_log2}")
            self.add_instruction(
                modules=self.sel_module(SPLIT=1),
                bank1=prev_bram,  # Input
                addr1=t1,
                bank2=curr_bram,  # Output
                addr2=z1,
                element_count=element_count_log2,
            )

        else:  # Replace last split with a copy
            dprint(f"n={n},\tcopy_split1 \tin_bram={prev_bram},\tin_addr={t1},\tout_bram={curr_bram},\tout_addr={z1}")
            self.add_instruction(
                modules=self.sel_module(COPY=1),
                bank3=prev_bram,  # Input
                addr1=t1,
                bank4=curr_bram,  # Output
                addr2=z1,
                element_count=element_count_log2 - 1,
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

        if n > 2:
            dprint(f"n={n},\tmerge_fft1 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z1}\tsm_size={element_count_log2}")
            self.add_instruction(
                modules=self.sel_module(MERGE=1),
                bank1=next_bram,  # Input
                addr1=tmp,
                bank2=curr_bram,  # Output
                addr2=z1,
                element_count=element_count_log2,
            )
        else:  # Replace first merge with a copy
            dprint(f"n={n},\tcopy_merge1 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z1}")
            self.add_instruction(
                modules=self.sel_module(COPY=1),
                bank3=next_bram,  # Input
                addr1=tmp,
                bank4=curr_bram,  # Output
                addr2=z1,
                element_count=element_count_log2 - 1,
            )

        dprint(f"n={n},\tcopy_t1\tin_bram={prev_bram}\tin_addr={t1}\tout_bram={next_bram}\tout_addr={tmp}")
        self.add_instruction(
            modules=self.sel_module(COPY=1),
            bank3=prev_bram,  # Input
            addr1=t1,
            bank4=next_bram,  # Output
            addr2=tmp,
            element_count=element_count_log2 - 1,
        )

        dprint(f"n={n},\tsub_z1\tin_bram={curr_bram}\tin_addr={z1}\tout_bram={next_bram}\tout_addr={tmp}")
        self.add_instruction(
            modules=self.sel_module(ADD_SUB=1),
            add_sub_mode=1,  # Subtract mode
            bank3=curr_bram,  # Input1
            addr1=z1,
            bank4=next_bram,  # Input2, output
            addr2=tmp,
            element_count=element_count_log2 - 1,
        )

        # tree // 2 here because "tree" refers to the address in original array (1 element per row), but our BRAM has 2 per row
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

        t0_bram = prev_bram if n < N else 4  # On top level of recursion this BRAM is different
        dprint(f"n={n},\tadd_t0\tin_bram={t0_bram}\tin_addr={t0}\tout_bram={next_bram}\tout_addr={tmp}")
        self.add_instruction(
            modules=self.sel_module(ADD_SUB=1),
            add_sub_mode=0,  # Add mode
            bank3=t0_bram,  # Input1
            addr1=t0,
            bank4=next_bram,  # Input2, output
            addr2=tmp,
            element_count=element_count_log2 - 1,
        )

        if n > 2:
            dprint(f"n={n},\tsplit_fft2 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z0}\tsm_size={element_count_log2}")
            self.add_instruction(
                modules=self.sel_module(SPLIT=1),
                bank1=next_bram,  # Input
                addr1=tmp,
                bank2=curr_bram,  # Output
                addr2=z0,
                element_count=element_count_log2,
            )

        else:  # Replace last split with a copy
            dprint(f"n={n},\tcopy_split2 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z0}")
            self.add_instruction(
                modules=self.sel_module(COPY=1),
                bank3=next_bram,  # Input
                addr1=tmp,
                bank4=curr_bram,  # Output
                addr2=z0,
                element_count=element_count_log2 - 1,
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

        if n > 2:
            dprint(f"n={n},\tmerge_fft2 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z0}\tsm_size={element_count_log2}")
            self.add_instruction(
                modules=self.sel_module(MERGE=1),
                bank1=next_bram,  # Input
                addr1=tmp,
                bank2=curr_bram,  # Output
                addr2=z0,
                element_count=element_count_log2,
            )

        else:  # Replace first merge with a copy
            dprint(f"n={n},\tcopy_merge2 \tin_bram={next_bram},\tin_addr={tmp},\tout_bram={curr_bram},\tout_addr={z0}")
            self.add_instruction(
                modules=self.sel_module(COPY=1),
                bank3=next_bram,  # Input
                addr1=tmp,
                bank4=curr_bram,  # Output
                addr2=z0,
                element_count=element_count_log2 - 1,
            )

    def sign512(self):
        N = 512
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
        self.add_instruction(
            modules=self.sel_module(INT_TO_DOUBLE=1, COPY=1),
            bank1=5,  # INT_TO_DOUBLE input
            bank2=5,  # INT_TO_DOUBLE output
            bank3=5,  # COPY input
            bank4=6,  # COPY output
            addr1=0,  # COPY input offset
            addr2=2560,  # COPY output offset
            element_count=int(math.log2(N // 2)),
        )

        # timestep 3: FFT
        dprint("FFT")
        self.add_instruction(
            modules=self.sel_module(FFT_IFFT=1),
            mode=0,  # FFT mode: FFT
            bank1=5,  # FFT bank1
            bank2=4,  # FFT bank2
            addr1=0,  # Offset in bank1
            addr2=0,  # Offset in bank2
        )

        # timestep 4: COPY, COMPLEX_MUL
        dprint("COPY COMPLEX_MUL")
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

        # timestep 5: COMPLEX_MUL, MUL_CONST
        dprint("COMPLEX_MUL MUL_CONST")
        self.add_instruction(
            modules=self.sel_module(COMPLEX_MUL=1, MUL_CONST=1),
            bank1=4,  # COMPLEX_MUL input 1, output
            bank2=3,  # COMPLEX_MUL input 2
            bank3=5,  # MUL_CONST input
            bank4=5,  # MUL_CONST output
            addr1=0,  # Start offset for COMPLEX_MUL
            addr2=0,  # End offset for COMPLEX_MUL
            mul_const_selection=1,  # Select constant for multiplication
            element_count=int(math.log2(N // 2)),
        )

        # timestep 6: MUL_CONST
        dprint("MUL_CONST")
        self.add_instruction(
            modules=self.sel_module(MUL_CONST=1),
            bank3=4,  # MUL_CONST input
            bank4=4,  # MUL_CONST output
            mul_const_selection=0,  # Select constant for multiplication
            element_count=int(math.log2(N // 2)),
        )

        self.first_samplerz_call = True
        self.ffsampling(N=512, n=512, curr_bram=0, next_free_addr=[256, 256, 256, 256], t0=0, t1=0, tree=0)

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
            add_sub_mode=0,  # Add mode
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
            mode=1,  # IFFT mode: IFFT
            add_sub_mode=0,  # add
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
            mode=1,  # IFFT mode: IFFT
            bank1=5,  # FFT bank1
            bank2=4,  # FFT bank2
            addr1=N // 2,  # Offset for FFT bank1, ADD_SUB input
            addr2=N // 2,  # Offset for FFT bank2, ADD_SUB output
        )

        dprint("compress")
        self.add_instruction(
            modules=self.sel_module(COMPRESS=1),
            bank1=2,  # bank with t0
            bank2=5,  # bank with t1
            bank3=6,  # bank with hm
            bank4=5,  # output bank
            addr1=N // 2,  # Offset for bank1 (t0), bank2 (t1) and output
            addr2=2560,  # Offset for bank3 (hm)
            element_count=int(math.log2(N)),
        )

        generator.print_verilog(algorithm="sign")

        if tree_index_print:
            print(f"Indices where samplerz will read tree:")
            print(self.samplerz_tree_addrs)

            print(f"Indices where mul with tree will read tree:")
            print(self.mul_tree_addrs)


if __name__ == "__main__":

    generator = InstructionGenerator()
    # generator.verify512()
    generator.sign512()
