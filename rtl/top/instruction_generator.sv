`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// Generates the instructions for signing and verification on the fly. It is based on scripts/generate_instruction_list.py.
//
// Signing consists of a fixed preamble, ffSampling and a fixed postamble. ffSampling is a recursion over the Falcon tree.
//
//////////////////////////////////////////////////////////////////////////////////

module instruction_generator #(
    parameter int N = 512
  )(
    input logic clk,
    input logic restart,
    input logic algorithm, // 0 = signing, 1 = verification
    input logic next,

    output logic [`INSTRUCTION_WIDTH-1:0] instruction,
    output logic finished
  );

  localparam int LOGN = $clog2(N);
  localparam int SAVED_HM_ADDR = N == 512 ? 2560 : 5632;  // Where hm is kept during signing (BRAM6, after the tree)
  localparam int TREE_BRAM = 6;
  localparam int SEED_BRAM = 3;

  typedef struct packed {
    logic COPY, HASH_TO_POINT, INT_TO_DOUBLE, FFT_IFFT, NTT_INTT, COMPLEX_MUL, MUL_CONST, SPLIT, MERGE, MULT_MOD_Q,
          CHECK_BOUND, DECOMPRESS, COMPRESS, ADD_SUB, SAMPLERZ;
  } modules_t;

  typedef struct packed {
    modules_t modules;
    logic input_output_addr_same;
    logic mul_const_constant;
    logic [3:0] element_count;
    logic mode2, mode1;
    logic [12:0] addr2, addr1;
    logic [2:0] bank7, bank6, bank5, bank4, bank3, bank2, bank1;
  } instruction_t;

  //////////////////////////////// Fixed instructions ////////////////////////////////

  function automatic instruction_t verify_instruction(int i);
    instruction_t inst = '0;
    case (i)
      0: begin
        inst.modules.NTT_INTT = 1; inst.modules.DECOMPRESS = 1; inst.modules.HASH_TO_POINT = 1;
        inst.bank1 = 0; inst.bank2 = 2;                 // NTT
        inst.bank3 = 6; inst.bank4 = 5;                 // hash_to_point input, output
        inst.bank5 = 1; inst.bank6 = 4; inst.bank7 = 3; // decompress input, outputs
      end
      1: begin
        inst.modules.NTT_INTT = 1;
        inst.bank1 = 4; inst.bank2 = 1;
      end
      2: begin
        inst.modules.MULT_MOD_Q = 1;
        inst.bank1 = N == 512 ? 1 : 4; inst.bank2 = N == 512 ? 2 : 0; inst.bank3 = 6;
        inst.element_count = LOGN - 1;
      end
      3: begin
        inst.modules.NTT_INTT = 1;
        inst.mode1 = 1; // INTT
        inst.bank1 = 6; inst.bank2 = 4;
      end
      4: begin
        inst.modules.CHECK_BOUND = 1;
        inst.bank1 = 5; inst.bank2 = N == 512 ? 4 : 6; inst.bank3 = 3;
        inst.element_count = LOGN - 1;
      end
      default: ;
    endcase
    return inst;
  endfunction
  localparam int VERIFY_COUNT = 5;

  // Before ffSampling
  function automatic instruction_t sign_pre_instruction(int i);
    instruction_t inst = '0;
    case (i)
      0: begin
        inst.modules.HASH_TO_POINT = 1;
        inst.bank3 = 4; inst.bank4 = 5;
      end
      1: begin
        inst.modules.INT_TO_DOUBLE = 1; inst.modules.COPY = 1;
        inst.bank1 = 5; inst.bank2 = 5;                           // INT_TO_DOUBLE input, output
        inst.bank3 = 5; inst.bank4 = 6; inst.addr2 = SAVED_HM_ADDR; // COPY hm
        inst.element_count = LOGN - 1;
      end
      2: begin
        inst.modules.FFT_IFFT = 1;
        inst.bank1 = 5; inst.bank2 = 4;
      end
      3: begin
        inst.modules.COPY = 1; inst.modules.COMPLEX_MUL = 1;
        inst.bank1 = N == 512 ? 5 : 4; inst.bank2 = 1;  // COMPLEX_MUL
        inst.bank3 = N == 512 ? 5 : 4; inst.bank4 = N == 512 ? 4 : 5;  // COPY
        inst.element_count = LOGN - 1;
      end
      4: begin
        inst.modules.COMPLEX_MUL = 1; inst.modules.MUL_CONST = 1;
        inst.bank1 = N == 512 ? 4 : 5; inst.bank2 = 3;  // COMPLEX_MUL
        inst.bank3 = N == 512 ? 5 : 4; inst.bank4 = N == 512 ? 5 : 4;  // MUL_CONST
        inst.mul_const_constant = 1;
        inst.element_count = LOGN - 1;
      end
      5: begin
        inst.modules.MUL_CONST = 1;
        inst.bank3 = N == 512 ? 4 : 5; inst.bank4 = N == 512 ? 4 : 5;
        inst.element_count = LOGN - 1;
      end
      default: ;
    endcase
    return inst;
  endfunction
  localparam int SIGN_PRE_COUNT = 6;

  // After ffSampling
  function automatic instruction_t sign_post_instruction(int i);
    instruction_t inst = '0;
    inst.element_count = LOGN - 1;
    case (i)
      0: begin  // COPY b00
        inst.modules.COPY = 1;
        inst.bank3 = 0; inst.bank4 = 3; inst.addr2 = N/2;
      end
      1: begin  // COPY b10
        inst.modules.COPY = 1;
        inst.bank3 = 2; inst.bank4 = 2; inst.addr2 = N/2;
      end
      2: begin
        inst.modules.COMPLEX_MUL = 1; inst.modules.COPY = 1;
        inst.bank1 = 3; inst.bank2 = 0; inst.bank3 = 0; inst.bank4 = 4;
        inst.addr1 = N/2; inst.addr2 = N/2;
      end
      3: begin
        inst.modules.COMPLEX_MUL = 1; inst.modules.COPY = 1;
        inst.bank1 = 2; inst.bank2 = 0; inst.bank3 = 0; inst.bank4 = 5;
        inst.addr1 = N/2; inst.addr2 = N;
        inst.input_output_addr_same = 1;
      end
      4: begin
        inst.modules.COMPLEX_MUL = 1; inst.modules.ADD_SUB = 1;
        inst.bank1 = 4; inst.bank2 = 1; inst.bank3 = 3; inst.bank4 = 2;
        inst.addr1 = N/2;
        inst.input_output_addr_same = 1;
      end
      5: begin
        inst.modules.COMPLEX_MUL = 1;
        inst.bank1 = 5; inst.bank2 = 3;
        inst.addr1 = N/2;
      end
      6: begin
        inst.modules.FFT_IFFT = 1; inst.modules.ADD_SUB = 1;
        inst.mode1 = 1;  // IFFT
        inst.bank1 = 2; inst.bank2 = 3; inst.bank3 = 4; inst.bank4 = 5;
        inst.addr1 = N/2; inst.addr2 = N/2;
      end
      7: begin
        inst.modules.FFT_IFFT = 1;
        inst.mode1 = 1;  // IFFT
        inst.bank1 = 5; inst.bank2 = 4;
        inst.addr1 = N/2; inst.addr2 = N/2;
        inst.element_count = 0;
      end
      8: begin
        inst.modules.COMPRESS = 1;
        inst.bank1 = N == 512 ? 2 : 3;  // t0
        inst.bank2 = N == 512 ? 5 : 4;  // t1
        inst.bank3 = 6;                 // hm
        inst.bank4 = 0;                 // output
        inst.addr1 = N/2; inst.addr2 = SAVED_HM_ADDR;
        inst.element_count = LOGN;
      end
      default: ;
    endcase
    return inst;
  endfunction
  localparam int SIGN_POST_COUNT = 9;

  //////////////////////////////// ffSampling ////////////////////////////////

  // Address of z0 at a recursion level: each level reserves n = N >> level words in BRAM (level % 4), after the first
  // N/2 words and the levels above it that use the same BRAM
  function automatic logic [12:0] level_addr(int level);
    logic [12:0] addr = N/2;
    for (int j = 0; j <= LOGN; j++)
      if (j < level && j % 4 == level % 4)
        addr += N >> j;
    return addr;
  endfunction

  typedef enum logic [2:0] {SIGN_PRE, FFSAMPLING, SIGN_POST, VERIFY, FINISHED} phase_t;
  phase_t phase;
  logic [3:0] index;  // Instruction index in SIGN_PRE, SIGN_POST and VERIFY

  logic [$clog2(LOGN+1)-1:0] level;  // Recursion level, n = N >> level (2 at the lowest level, LOGN - 1)
  logic [2:0] step;                  // Step within the node at this level
  logic [LOGN:0] second_child;       // For each level: 0 if it is the first child of its parent (z1), 1 if the second (z0)
  logic [13:0] tree [LOGN+1];        // Address in the tree (one element per row, two per BRAM row) of each level
  logic first_samplerz;              // The first SamplerZ call restarts SamplerZ

  // Operands of the node at the current level (n = N >> level)
  logic [3:0] log_n;
  logic [2:0] curr_bram, next_bram, prev_bram, t0_bram;
  logic [12:0] z0, z1, tmp, t0, t1;
  logic n_is_2;
  always_comb begin
    log_n = LOGN - level;
    curr_bram = level % 4;
    next_bram = (level + 1) % 4;
    prev_bram = level == 0 ? (N == 512 ? 5 : 4) : (level - 1) % 4;  // At the top the input is in BRAM5/BRAM4
    t0_bram = level == 0 ? (N == 512 ? 4 : 5) : prev_bram;
    z0 = level_addr(level);
    z1 = z0 + (N >> (level + 1));
    tmp = level_addr(level + 1);  // z0 of the child
    // t0 and t1 are z1 (first child) or z0 (second child) of the parent, and that plus a quarter of the parent's size
    t0 = level == 0 ? 0 : level_addr(level - 1) + (second_child[level] ? 0 : N >> level);
    t1 = level == 0 ? 0 : t0 + (N >> (level + 1));
    n_is_2 = log_n == 1;
  end

  // Operation of the current step
  typedef enum logic [3:0] {SPLIT1, MERGE1, COPY_T1, SUB_Z1, MUL_TREE, ADD_T0, SPLIT2, MERGE2, SAMPLERZ1, SAMPLERZ2} op_t;
  op_t op;
  always_comb begin
    if (n_is_2)
      case (step)
        0: op = COPY_T1;
        1: op = SAMPLERZ1;
        2: op = SUB_Z1;
        3: op = MUL_TREE;
        4: op = ADD_T0;
        default: op = SAMPLERZ2;
      endcase
    else
      op = op_t'(step);
  end

  // Tree addresses of the children: tree0 = tree + n (second child), tree1 = tree0 + treesize(n/2) (first child),
  // with treesize(n) = (log2(n) + 1) * n. For n = 2 the children are leaves: tree0 = tree + 2, tree1 = tree + 3.
  logic [13:0] child_tree, leaf_tree;
  always_comb begin
    child_tree = tree[level] + (N >> level);
    if (op == SPLIT1)
      child_tree += log_n << (log_n - 1);
    leaf_tree = tree[level] + (op == SAMPLERZ1 ? 3 : 2);
  end

  // Instruction for the current ffSampling step
  instruction_t ff_inst;
  always_comb begin
    ff_inst = '0;
    case (op)
      SPLIT1, SPLIT2: begin  // Split t1 into z1 (first child) or tmp into z0 (second child)
        ff_inst.modules.SPLIT = 1;
        ff_inst.bank1 = op == SPLIT1 ? prev_bram : next_bram; ff_inst.addr1 = op == SPLIT1 ? t1 : tmp;
        ff_inst.bank2 = curr_bram; ff_inst.addr2 = op == SPLIT1 ? z1 : z0;
        ff_inst.element_count = log_n;
      end
      MERGE1, MERGE2: begin  // Merge the child's result into z1 or z0
        ff_inst.modules.MERGE = 1;
        ff_inst.bank1 = next_bram; ff_inst.addr1 = tmp;
        ff_inst.bank2 = curr_bram; ff_inst.addr2 = op == MERGE1 ? z1 : z0;
        ff_inst.element_count = log_n;
      end
      COPY_T1: begin
        ff_inst.modules.COPY = 1;
        ff_inst.bank3 = prev_bram; ff_inst.addr1 = t1;
        ff_inst.bank4 = next_bram; ff_inst.addr2 = tmp;
        ff_inst.element_count = log_n - 1;
      end
      SUB_Z1: begin  // tmp = t1 - z1
        ff_inst.modules.ADD_SUB = 1;
        ff_inst.mode2 = 1;
        ff_inst.bank3 = curr_bram; ff_inst.addr1 = z1;
        ff_inst.bank4 = next_bram; ff_inst.addr2 = tmp;
        ff_inst.element_count = log_n - 1;
      end
      MUL_TREE: begin  // tmp = tmp * tree
        ff_inst.modules.COMPLEX_MUL = 1;
        ff_inst.bank1 = next_bram; ff_inst.addr1 = tmp;
        ff_inst.bank2 = TREE_BRAM; ff_inst.addr2 = tree[level] >> 1;
        ff_inst.element_count = log_n - 1;
      end
      ADD_T0: begin  // tmp = tmp + t0
        ff_inst.modules.ADD_SUB = 1;
        ff_inst.bank3 = t0_bram; ff_inst.addr1 = t0;
        ff_inst.bank4 = next_bram; ff_inst.addr2 = tmp;
        ff_inst.element_count = log_n - 1;
      end
      SAMPLERZ1, SAMPLERZ2: begin  // Input at tmp in next_bram (fixed address in the control unit), output to z1 or z0
        ff_inst.modules.SAMPLERZ = 1;
        ff_inst.mode1 = first_samplerz;
        ff_inst.mode2 = leaf_tree[0];  // Two tree elements per BRAM row
        ff_inst.bank1 = next_bram;
        ff_inst.bank2 = TREE_BRAM; ff_inst.addr2 = leaf_tree >> 1;
        ff_inst.bank3 = curr_bram; ff_inst.addr1 = op == SAMPLERZ1 ? z1 : z0;
        ff_inst.bank4 = SEED_BRAM;
      end
      default: ;
    endcase
  end

  //////////////////////////////// Sequencing ////////////////////////////////

  always_comb begin
    case (phase)
      SIGN_PRE: instruction = sign_pre_instruction(index);
      FFSAMPLING: instruction = ff_inst;
      SIGN_POST: instruction = sign_post_instruction(index);
      VERIFY: instruction = verify_instruction(index);
      default: instruction = '0;
    endcase
  end
  assign finished = phase == FINISHED;

  always_ff @(posedge clk) begin
    if (restart) begin
      phase <= algorithm ? VERIFY : SIGN_PRE;
      index <= 0;
      level <= 0;
      step <= 0;
      second_child <= 0;
      tree[0] <= 0;
      first_samplerz <= 1;
    end
    else if (next) begin
      case (phase)
        SIGN_PRE: begin
          index <= index + 1;
          if (index == SIGN_PRE_COUNT - 1)
            phase <= FFSAMPLING;
        end
        FFSAMPLING: begin
          if (op == SAMPLERZ1 || op == SAMPLERZ2)
            first_samplerz <= 0;
          if (op == MERGE2 || op == SAMPLERZ2) begin  // Node done: return to the parent
            if (level == 0) begin
              phase <= SIGN_POST;
              index <= 0;
            end
            else begin
              level <= level - 1;
              step <= second_child[level] ? 3'(MERGE2) : 3'(MERGE1);  // Merge the child's result
            end
          end
          else if (op == SPLIT1 || op == SPLIT2) begin  // Descend into the first or second child
            level <= level + 1;
            step <= 0;
            second_child[level + 1] <= op == SPLIT2;
            tree[level + 1] <= child_tree;
          end
          else
            step <= step + 1;
        end
        SIGN_POST: begin
          index <= index + 1;
          if (index == SIGN_POST_COUNT - 1)
            phase <= FINISHED;
        end
        VERIFY: begin
          index <= index + 1;
          if (index == VERIFY_COUNT - 1)
            phase <= FINISHED;
        end
        default: ;
      endcase
    end
  end

endmodule
