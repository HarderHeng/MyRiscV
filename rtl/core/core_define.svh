`define     DataWidth       31:0            //数据位宽
`define     AddrWidth       31:0            //地址位宽
`define     CpuResetAddr    32'h80000000    //cpu复位地址

`define     RegAddrWidth    4:0             //通用寄存器地址位宽

`define     CsrAddrWidth    11:0            //csr寄存器地址位宽




//ID模块
`define     INST_TYPE_R         7'b0110011      //R型指令
`define     INST_FUNCT3_ADD_SUB 3'b000          //ADDorSUB
`define     INST_FUNCT3_SLL     3'b001          //SLL
`define     INST_FUNCT3_SLT     3'b010          //SLT
`define     INST_FUNCT3_SLTU    3'b011          //SLTU
`define     INST_FUNCT3_XOR     3'b100          //XOR
`define     INST_FUNCT3_SRL_SRA 3'b101          //SRLorSRA
`define     INST_FUNCT3_OR      3'b110          //OR
`define     INST_FUNCT3_AND     3'b111          //AND

`define     INST_FUNCT7_ADD     7'b0000000      //ADD
`define     INST_FUNCT7_SUB     7'b0100000      //SUB
`define     INST_FUNCT7_SRL     7'b0000000      //SRL
`define     INST_FUNCT7_SRA     7'b0100000      //SRA

`define     INST_TYPE_I         7'b0010011      //I型指令 
`define     INST_FUNCT3_ADDI    3'b000          //ADDI
`define     INST_FUNCT3_SLLI    3'b001          //SLLI
`define     INST_FUNCT3_SLTI    3'b010          //SLTI
`define     INST_FUNCT3_SLTIU   3'b011          //SLTIU
`define     INST_FUNCT3_XORI    3'b100          //XORI
`define     INST_FUNCT3_SRLI_SRAI    3'b101     //SRLIorSRAI
`define     INST_FUNCT3_ORI     3'b110          //ORI
`define     INST_FUNCT3_ANDI    3'b111          //ANDI

`define     INST_FUNCT7_SLLI    7'b0000000      //SLLI
`define     INST_FUNCT7_SRLI    7'b0000000      //SRLI
`define     INST_FUNCT7_SRAI    7'b0100000      //SRAI

`define     INST_TYPE_I_L       7'b0000011      //I型中的Load
`define     INST_FUNCT3_LB      3'b000          //LB
`define     INST_FUNCT3_LH      3'b001          //LH
`define     INST_FUNCT3_LW      3'b010          //LW
`define     INST_FUNCT3_LBU     3'b100          //LBU
`define     INST_FUNCT3_LHU     3'b101          //LBH

`define     MEM_OP_LOAD         1'b0            //MemOpLoad
`define     MEM_OP_STORE        1'b1            //MemOpLoad