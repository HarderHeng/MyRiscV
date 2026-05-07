// RISC-V CPU Core - 5 Stage Pipeline
// RV32I Instruction Set

module cpu (
    input  wire        clk,
    input  wire        rst,
    // Instruction fetch
    output wire [31:0] i_addr,
    input  wire [31:0] i_rdata,
    input  wire        i_ready,
    // Data memory
    output wire [31:0] d_addr,
    output wire        d_req,
    output wire        d_we,
    output wire [3:0]  d_be,
    output wire [31:0] d_wdata,
    input  wire [31:0] d_rdata,
    input  wire        d_ready
);

    // ========== PC ==========
    reg [31:0] pc;
    wire [31:0] pc_plus4;
    wire pc_en;

    assign pc_plus4 = pc + 4;
    assign i_addr = pc;
    assign pc_en = 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h80000000;  // IRAM reset vector
        end else if (pc_en) begin
            pc <= pc_next;
        end
    end

    // ========== IF/ID Pipeline Register ==========
    reg [31:0] if_id_pc;
    reg [31:0] if_id_pc_plus4;
    reg [31:0] if_id_inst;
    reg        if_id_valid;

    wire if_flush = branch_taken || jump_reg;
    wire if_hold = load_use_hazard;

    always @(posedge clk) begin
        if (rst || if_flush) begin
            if_id_pc <= 32'b0;
            if_id_pc_plus4 <= 32'b0;
            if_id_inst <= 32'b0;
            if_id_valid <= 1'b0;
        end else if (!if_hold) begin
            if_id_pc <= pc;
            if_id_pc_plus4 <= pc_plus4;
            if_id_inst <= i_rdata;
            if_id_valid <= i_ready;
        end
    end

    // ========== ID Stage ==========
    wire [6:0] id_opcode = if_id_inst[6:0];
    wire [2:0] id_funct3 = if_id_inst[14:12];
    wire [6:0] id_funct7 = if_id_inst[31:25];
    wire [4:0] id_rs1 = if_id_inst[19:15];
    wire [4:0] id_rs2 = if_id_inst[24:20];
    wire [4:0] id_rd = if_id_inst[11:7];

    // Immediate generation
    reg [31:0] id_imm;
    always @(*) begin
        id_imm = 32'b0;
        if (id_opcode == 7'b0010011 || id_opcode == 7'b0000011 || id_opcode == 7'b1100111) begin
            // I-type
            id_imm = {{21{if_id_inst[31]}}, if_id_inst[30:20]};
        end else if (id_opcode == 7'b0100011) begin
            // S-type
            id_imm = {{21{if_id_inst[31]}}, if_id_inst[30:25], if_id_inst[11:7]};
        end else if (id_opcode == 7'b1100011) begin
            // B-type
            id_imm = {{20{if_id_inst[31]}}, if_id_inst[7], if_id_inst[30:25], if_id_inst[11:8], 1'b0};
        end else if (id_opcode == 7'b0110111) begin
            // LUI
            id_imm = {if_id_inst[31:12], 12'b0};
        end else if (id_opcode == 7'b0010111) begin
            // AUIPC
            id_imm = {if_id_inst[31:12], 12'b0};
        end else if (id_opcode == 7'b1101111) begin
            // JAL
            id_imm = {{12{if_id_inst[31]}}, if_id_inst[19:12], if_id_inst[20], if_id_inst[30:21], 1'b0};
        end
    end

    // Control signals
    reg id_reg_write;
    reg id_mem_read;
    reg id_mem_write;
    reg id_alu_src;
    reg [2:0] id_alu_op;
    reg [1:0] id_wb_src;
    reg branch;
    reg jump_reg;

    // Opcode decoder
    wire is_rtype = (id_opcode == 7'b0110011);
    wire is_itype = (id_opcode == 7'b0010011);
    wire is_load  = (id_opcode == 7'b0000011);
    wire is_store = (id_opcode == 7'b0100011);
    wire is_branch= (id_opcode == 7'b1100011);
    wire is_lui   = (id_opcode == 7'b0110111);
    wire is_auipc = (id_opcode == 7'b0010111);
    wire is_jal   = (id_opcode == 7'b1101111);
    wire is_jalr  = (id_opcode == 7'b1100111);

    always @(*) begin
        id_reg_write = is_rtype || is_itype || is_load || is_lui || is_auipc || is_jal || is_jalr;
        id_mem_read = is_load;
        id_mem_write = is_store;
        id_alu_src = is_itype || is_load || is_store || is_lui || is_auipc;
        id_wb_src = is_load ? 2'b01 : 2'b00;
        branch = is_branch;
        jump_reg = is_jal || is_jalr;
    end

    // ALU operation
    reg [2:0] alu_op;
    always @(*) begin
        alu_op = 3'b000;  // ADD default
        if (is_rtype) begin
            case (id_funct3)
                3'b000: alu_op = id_funct7[5] ? 3'b001 : 3'b000;  // ADD/SUB
                3'b001: alu_op = 3'b010;  // SLL
                3'b010: alu_op = 3'b011;  // SLT
                3'b011: alu_op = 3'b100;  // SLTU
                3'b100: alu_op = 3'b101;  // XOR
                3'b101: alu_op = id_funct7[5] ? 3'b110 : 3'b111; // SRL/SRA
                3'b110: alu_op = 3'b001;  // OR
                3'b111: alu_op = 3'b000;  // AND
            endcase
        end else if (is_itype) begin
            case (id_funct3)
                3'b000: alu_op = 3'b000;  // ADDI
                3'b001: alu_op = 3'b010;  // SLLI
                3'b010: alu_op = 3'b011;  // SLTI
                3'b011: alu_op = 3'b100;  // SLTIU
                3'b100: alu_op = 3'b101;  // XORI
                3'b101: alu_op = id_funct7[5] ? 3'b110 : 3'b111; // SRLI/SRAI
                3'b110: alu_op = 3'b001;  // ORI
                3'b111: alu_op = 3'b000;  // ANDI
            endcase
        end else if (is_lui) begin
            alu_op = 3'b111;  // COPY_B (pass immediate)
        end else if (is_auipc) begin
            alu_op = 3'b000;  // ADD (PC + imm)
        end
    end

    // ========== Register File ==========
    reg [31:0] rf [0:31];
    wire [31:0] rf_rs1_data;
    wire [31:0] rf_rs2_data;

    assign rf_rs1_data = (id_rs1 == 5'b0) ? 32'b0 : rf[id_rs1];
    assign rf_rs2_data = (id_rs2 == 5'b0) ? 32'b0 : rf[id_rs2];

    // ========== ID/EX Pipeline Register ==========
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_rs1;
    reg [31:0] id_ex_rs2;
    reg [31:0] id_ex_imm;
    reg [4:0]  id_ex_rd;
    reg        id_ex_reg_write;
    reg        id_ex_mem_read;
    reg        id_ex_mem_write;
    reg        id_ex_alu_src;
    reg [2:0]  id_ex_alu_op;
    reg [1:0]  id_ex_wb_src;
    reg        id_ex_branch;
    reg        id_ex_valid;

    wire id_ex_flush = if_flush;

    always @(posedge clk) begin
        if (rst || id_ex_flush) begin
            id_ex_pc <= 32'b0;
            id_ex_rs1 <= 32'b0;
            id_ex_rs2 <= 32'b0;
            id_ex_imm <= 32'b0;
            id_ex_rd <= 5'b0;
            id_ex_reg_write <= 1'b0;
            id_ex_mem_read <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_alu_src <= 1'b0;
            id_ex_alu_op <= 3'b0;
            id_ex_wb_src <= 2'b0;
            id_ex_branch <= 1'b0;
            id_ex_valid <= 1'b0;
        end else if (!if_hold) begin
            id_ex_pc <= if_id_pc;
            id_ex_rs1 <= rf_rs1_data;
            id_ex_rs2 <= rf_rs2_data;
            id_ex_imm <= id_imm;
            id_ex_rd <= id_rd;
            id_ex_reg_write <= id_reg_write;
            id_ex_mem_read <= id_mem_read;
            id_ex_mem_write <= id_mem_write;
            id_ex_alu_src <= id_alu_src;
            id_ex_alu_op <= alu_op;
            id_ex_wb_src <= id_wb_src;
            id_ex_branch <= branch;
            id_ex_valid <= if_id_valid;
        end
    end

    // ========== EX Stage ==========
    wire [31:0] ex_alu_in_a = id_ex_rs1;
    wire [31:0] ex_alu_in_b = id_ex_alu_src ? id_ex_imm : id_ex_rs2;

    reg [31:0] ex_alu_result;
    always @(*) begin
        case (id_ex_alu_op)
            3'b000:   ex_alu_result = ex_alu_in_a + ex_alu_in_b;                    // ADD
            3'b001:   ex_alu_result = ex_alu_in_a - ex_alu_in_b;                    // SUB
            3'b010:   ex_alu_result = ex_alu_in_a << ex_alu_in_b[4:0];             // SLL
            3'b011:   ex_alu_result = ($signed(ex_alu_in_a) < $signed(ex_alu_in_b)) ? 32'd1 : 32'd0;  // SLT
            3'b100:    ex_alu_result = (ex_alu_in_a < ex_alu_in_b) ? 32'd1 : 32'd0; // SLTU
            3'b101:    ex_alu_result = ex_alu_in_a ^ ex_alu_in_b;                    // XOR
            3'b110:    ex_alu_result = ex_alu_in_a >> ex_alu_in_b[4:0];             // SRL
            3'b111:    ex_alu_result = $signed(ex_alu_in_a) >>> ex_alu_in_b[4:0];  // SRA
            default:   ex_alu_result = 32'b0;
        endcase
    end

    // Branch comparison
    reg branch_taken;
    always @(*) begin
        branch_taken = 1'b0;
        if (id_ex_branch) begin
            case (id_funct3)
                3'b000: branch_taken = (ex_alu_result == 32'b0);   // BEQ
                3'b001: branch_taken = (ex_alu_result != 32'b0);   // BNE
                3'b100: branch_taken = $signed(ex_alu_in_a) < $signed(ex_alu_in_b);  // BLT
                3'b101: branch_taken = $signed(ex_alu_in_a) >= $signed(ex_alu_in_b); // BGE
                3'b110: branch_taken = ex_alu_in_a < ex_alu_in_b;  // BLTU
                3'b111: branch_taken = ex_alu_in_a >= ex_alu_in_b; // BGEU
            endcase
        end
    end

    wire [31:0] branch_target = id_ex_pc + id_ex_imm;

    // ========== Load-Use Hazard Detection ==========
    wire ex_mem_read = id_ex_mem_read;
    wire load_use_hazard = ex_mem_read &&
                           (id_ex_rd == id_rs1 || id_ex_rd == id_rs2) &&
                           id_ex_rd != 5'b0 &&
                           if_id_valid;

    // ========== EX/MEM Pipeline Register ==========
    reg [31:0] ex_mem_pc;
    reg [31:0] ex_mem_alu_result;
    reg [31:0] ex_mem_rs2;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_reg_write;
    reg        ex_mem_mem_read;
    reg        ex_mem_mem_write;
    reg [1:0]  ex_mem_wb_src;
    reg        ex_mem_valid;

    always @(posedge clk) begin
        if (rst || id_ex_flush) begin
            ex_mem_pc <= 32'b0;
            ex_mem_alu_result <= 32'b0;
            ex_mem_rs2 <= 32'b0;
            ex_mem_rd <= 5'b0;
            ex_mem_reg_write <= 1'b0;
            ex_mem_mem_read <= 1'b0;
            ex_mem_mem_write <= 1'b0;
            ex_mem_wb_src <= 2'b0;
            ex_mem_valid <= 1'b0;
        end else begin
            ex_mem_pc <= id_ex_pc;
            ex_mem_alu_result <= ex_alu_result;
            ex_mem_rs2 <= id_ex_rs2;
            ex_mem_rd <= id_ex_rd;
            ex_mem_reg_write <= id_ex_reg_write;
            ex_mem_mem_read <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;
            ex_mem_wb_src <= id_ex_wb_src;
            ex_mem_valid <= id_ex_valid;
        end
    end

    // ========== MEM Stage ==========
    assign d_addr = ex_mem_alu_result;
    assign d_req = ex_mem_mem_read || ex_mem_mem_write;
    assign d_we = ex_mem_mem_write;
    assign d_wdata = ex_mem_rs2;

    // Byte enable
    reg [3:0] mem_be;
    always @(*) begin
        mem_be = 4'b1111;
        if (ex_mem_mem_write || ex_mem_mem_read) begin
            case (d_addr[1:0])
                2'b00: mem_be = 4'b0001;
                2'b01: mem_be = 4'b0010;
                2'b10: mem_be = 4'b0100;
                2'b11: mem_be = 4'b1000;
            endcase
        end
    end
    assign d_be = mem_be;

    // Load data processing
    reg [31:0] mem_load_data;
    always @(*) begin
        case (id_funct3)
            3'b000: begin  // LB
                case (d_addr[1:0])
                    2'b00: mem_load_data = {{24{d_rdata[7]}}, d_rdata[7:0]};
                    2'b01: mem_load_data = {{24{d_rdata[15]}}, d_rdata[15:8]};
                    2'b10: mem_load_data = {{24{d_rdata[23]}}, d_rdata[23:16]};
                    2'b11: mem_load_data = {{24{d_rdata[31]}}, d_rdata[31:24]};
                endcase
            end
            3'b001: begin  // LH
                case (d_addr[1])
                    1'b0: mem_load_data = {{16{d_rdata[15]}}, d_rdata[15:0]};
                    1'b1: mem_load_data = {{16{d_rdata[31]}}, d_rdata[31:16]};
                endcase
            end
            3'b010: mem_load_data = d_rdata;  // LW
            3'b100: begin  // LBU
                case (d_addr[1:0])
                    2'b00: mem_load_data = {24'b0, d_rdata[7:0]};
                    2'b01: mem_load_data = {24'b0, d_rdata[15:8]};
                    2'b10: mem_load_data = {24'b0, d_rdata[23:16]};
                    2'b11: mem_load_data = {24'b0, d_rdata[31:24]};
                endcase
            end
            3'b101: begin  // LHU
                case (d_addr[1])
                    1'b0: mem_load_data = {16'b0, d_rdata[15:0]};
                    1'b1: mem_load_data = {16'b0, d_rdata[31:16]};
                endcase
            end
            default: mem_load_data = d_rdata;
        endcase
    end

    // ========== MEM/WB Pipeline Register ==========
    reg [31:0] mem_wb_alu_result;
    reg [31:0] mem_wb_load_data;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_write;
    reg [1:0]  mem_wb_wb_src;
    reg        mem_wb_valid;

    always @(posedge clk) begin
        if (rst) begin
            mem_wb_alu_result <= 32'b0;
            mem_wb_load_data <= 32'b0;
            mem_wb_rd <= 5'b0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_wb_src <= 2'b0;
            mem_wb_valid <= 1'b0;
        end else begin
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_load_data <= mem_load_data;
            mem_wb_rd <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_wb_src <= ex_mem_wb_src;
            mem_wb_valid <= ex_mem_valid;
        end
    end

    // ========== WB Stage ==========
    reg [31:0] wb_write_data;
    always @(*) begin
        case (mem_wb_wb_src)
            2'b00: wb_write_data = mem_wb_alu_result;  // ALU result
            2'b01: wb_write_data = mem_wb_load_data;   // Load data
            2'b10: wb_write_data = ex_mem_pc + 4;      // PC+4 for JAL
            default: wb_write_data = mem_wb_alu_result;
        endcase
    end

    // Register writeback
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                rf[i] <= 32'b0;
            end
        end else if (mem_wb_reg_write && mem_wb_valid && mem_wb_rd != 5'b0) begin
            rf[mem_wb_rd] <= wb_write_data;
        end
    end

    // ========== PC Next Logic ==========
    wire [31:0] jump_target = (id_opcode == 7'b1100111) ?
                              (rf_rs1_data + id_imm) :  // JALR
                              (if_id_pc + id_imm);     // JAL/Branch

    assign pc_next = branch_taken ? branch_target :
                     (jump_reg) ? jump_target :
                     pc_plus4;

endmodule
