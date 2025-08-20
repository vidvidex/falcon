`ifndef TASK_DFF_DONE

    `define TASK_DFF_DONE

    package falconsoar_pkg;
        ///////////////////////////////////////////////////////////////////////////////////                  
        //here is about the memory banks
        parameter int BANK_NUM = 4;
        parameter     BANK_DEPTH = 13'd2048; //BRAM depth = 1024, 36Kb = 36b * 1024; dual-port
        parameter int BANK_WIDTH = 256;  //ceil((4*256)/36) = ceil((1024)/36) = 29;
                
        parameter int unsigned MEM_ADDR_BITS = $clog2(BANK_NUM*BANK_DEPTH);

        ///////////////////////////////////////////////////////////////////////////////////                  
        //here is some type definition used in SamplerZ module
        parameter int VEC_BW = 32;
        parameter int VEC_PER_ROW = 16;

        typedef logic [VEC_BW-1:0] vect_t;
        typedef logic [VEC_PER_ROW-1:0][VEC_BW-1:0] row_data_pack_t;

        parameter SAMPLERZ_READ_DELAY = 4'd2;


    endpackage

`endif // TASK_DFF_DONE
