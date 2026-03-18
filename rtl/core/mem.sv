// =============================================================
// 文件：rtl/core/mem.sv
// 描述：MEM 阶段 —— 数据总线访问、Load 数据对齐与扩展
//       - 纯组合逻辑（无时钟）
//       - 生成字节使能（dbus_be）
//       - Store 数据复制到对应字节位置
//       - Load 数据根据 funct3 做符号/零扩展对齐
//       - 非 Load 指令直通 ALU 结果到 WB
// =============================================================
`ifndef MEM_SV
`define MEM_SV

`include "core_define.svh"

module MemoryAccess (
    // 来自 EX/MEM 流水线寄存器
    input  wire [31:0] alu_result,
    input  wire        mem_ren,
    input  wire        mem_wen,
    input  wire [2:0]  mem_funct3,
    input  wire [31:0] mem_wdata,
    input  wire [31:0] mem_addr,
    input  wire        reg_wen,
    input  wire [4:0]  reg_waddr,
    input  wire [31:0] reg_wdata,
    input  wire        is_load,

    // 数据总线（输出到 SoC 总线）
    output wire [31:0] dbus_addr,
    output wire        dbus_ren,
    output wire        dbus_wen,
    output wire [3:0]  dbus_be,         // 字节使能
    output wire [31:0] dbus_wdata,

    // 来自数据总线的读数据
    input  wire [31:0] dbus_rdata,

    // 输出到 MEM/WB 流水线寄存器
    output wire        wb_reg_wen,
    output wire [4:0]  wb_reg_waddr,
    output wire [31:0] wb_reg_wdata,    // 已对齐、扩展后的 Load 数据 或 ALU 结果

    // 前递给 ID（MEM→ID forwarding）
    output wire [31:0] fwd_wdata
);

    // -------------------------------------------------------
    // 总线地址（字对齐，地址 bit[1:0] 在字节使能中体现）
    // -------------------------------------------------------
    assign dbus_addr = {mem_addr[31:2], 2'b00};
    assign dbus_ren  = mem_ren;
    assign dbus_wen  = mem_wen;

    // -------------------------------------------------------
    // 字节使能生成（组合逻辑）
    // 根据访存类型（funct3）和地址低两位确定使能的字节
    // -------------------------------------------------------
    reg [3:0] be;

    always @(*) begin
        be = 4'b1111;  // 默认全字节使能（SW）
        if (mem_wen) begin
            case (mem_funct3)
                `F3_SW: be = 4'b1111;
                `F3_SH: begin
                    // SH：半字写，addr[1] 决定高半字还是低半字
                    if (mem_addr[1])
                        be = 4'b1100;   // 高半字 [31:16]
                    else
                        be = 4'b0011;   // 低半字 [15:0]
                end
                `F3_SB: begin
                    // SB：字节写，addr[1:0] 决定具体字节
                    case (mem_addr[1:0])
                        2'b00: be = 4'b0001;   // byte 0 [7:0]
                        2'b01: be = 4'b0010;   // byte 1 [15:8]
                        2'b10: be = 4'b0100;   // byte 2 [23:16]
                        2'b11: be = 4'b1000;   // byte 3 [31:24]
                        default: be = 4'b0001;
                    endcase
                end
                default: be = 4'b1111;
            endcase
        end else if (mem_ren) begin
            // Load 的字节使能（便于带有 BE 功能的总线）
            case (mem_funct3)
                `F3_LW:  be = 4'b1111;
                `F3_LH: begin
                    // LH：有符号半字，addr[1] 决定高/低半字
                    if (mem_addr[1])
                        be = 4'b1100;
                    else
                        be = 4'b0011;
                end
                `F3_LHU: begin
                    // LHU：无符号半字，addr[1] 决定高/低半字
                    if (mem_addr[1])
                        be = 4'b1100;
                    else
                        be = 4'b0011;
                end
                `F3_LB: begin
                    // LB：有符号字节
                    case (mem_addr[1:0])
                        2'b00: be = 4'b0001;
                        2'b01: be = 4'b0010;
                        2'b10: be = 4'b0100;
                        2'b11: be = 4'b1000;
                        default: be = 4'b0001;
                    endcase
                end
                `F3_LBU: begin
                    // LBU：无符号字节
                    case (mem_addr[1:0])
                        2'b00: be = 4'b0001;
                        2'b01: be = 4'b0010;
                        2'b10: be = 4'b0100;
                        2'b11: be = 4'b1000;
                        default: be = 4'b0001;
                    endcase
                end
                default: be = 4'b1111;
            endcase
        end
    end

    assign dbus_be = be;

    // -------------------------------------------------------
    // Store 写数据：复制到对应字节位置（字对齐总线）
    // SW：直通；SH：高低半字各一份；SB：四个字节各一份
    // -------------------------------------------------------
    reg [31:0] wdata_aligned;

    always @(*) begin
        case (mem_funct3)
            `F3_SW: wdata_aligned = mem_wdata;
            `F3_SH: wdata_aligned = {mem_wdata[15:0], mem_wdata[15:0]};
            `F3_SB: wdata_aligned = {4{mem_wdata[7:0]}};
            default: wdata_aligned = mem_wdata;
        endcase
    end

    assign dbus_wdata = wdata_aligned;

    // -------------------------------------------------------
    // Load 数据对齐与扩展（组合逻辑）
    // dbus_rdata 为字对齐原始读取数据，根据 funct3 和 addr[1:0] 提取
    // -------------------------------------------------------
    reg [31:0] load_data;

    always @(*) begin
        load_data = 32'd0;
        case (mem_funct3)
            `F3_LW: begin
                // 字读取：直通
                load_data = dbus_rdata;
            end
            `F3_LH: begin
                // 有符号半字读取：根据 addr[1] 选择高/低半字，符号扩展
                if (mem_addr[1])
                    load_data = {{16{dbus_rdata[31]}}, dbus_rdata[31:16]};
                else
                    load_data = {{16{dbus_rdata[15]}}, dbus_rdata[15:0]};
            end
            `F3_LHU: begin
                // 无符号半字读取：零扩展
                if (mem_addr[1])
                    load_data = {16'd0, dbus_rdata[31:16]};
                else
                    load_data = {16'd0, dbus_rdata[15:0]};
            end
            `F3_LB: begin
                // 有符号字节读取：根据 addr[1:0] 选择字节，符号扩展
                case (mem_addr[1:0])
                    2'b00: load_data = {{24{dbus_rdata[7]}},  dbus_rdata[7:0]};
                    2'b01: load_data = {{24{dbus_rdata[15]}}, dbus_rdata[15:8]};
                    2'b10: load_data = {{24{dbus_rdata[23]}}, dbus_rdata[23:16]};
                    2'b11: load_data = {{24{dbus_rdata[31]}}, dbus_rdata[31:24]};
                    default: load_data = 32'd0;
                endcase
            end
            `F3_LBU: begin
                // 无符号字节读取：零扩展
                case (mem_addr[1:0])
                    2'b00: load_data = {24'd0, dbus_rdata[7:0]};
                    2'b01: load_data = {24'd0, dbus_rdata[15:8]};
                    2'b10: load_data = {24'd0, dbus_rdata[23:16]};
                    2'b11: load_data = {24'd0, dbus_rdata[31:24]};
                    default: load_data = 32'd0;
                endcase
            end
            default: load_data = dbus_rdata;
        endcase
    end

    // -------------------------------------------------------
    // 写回数据选择：Load 指令用对齐后数据，其他用 ALU 结果
    // -------------------------------------------------------
    assign wb_reg_wdata = is_load ? load_data : reg_wdata;
    assign wb_reg_wen   = reg_wen;
    assign wb_reg_waddr = reg_waddr;

    // 前递数据（MEM→ID forwarding，对齐后的最终写回值）
    assign fwd_wdata = wb_reg_wdata;

endmodule

`endif // MEM_SV
