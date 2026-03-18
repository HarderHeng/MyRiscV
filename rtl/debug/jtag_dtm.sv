`ifndef JTAG_DTM_SV
`define JTAG_DTM_SV

// ============================================================
//  JTAG DTM（Debug Transport Module）
//  符合 RISC-V Debug Spec 0.13.2
//
//  功能：
//    - IEEE 1149.1 标准 JTAG TAP 状态机（16个状态）
//    - IR（5位指令寄存器），上电后默认 IDCODE
//    - 支持 IDCODE / DTMCS / DMI / BYPASS DR 寄存器
//    - TCK 时钟域 → 系统时钟域跨域同步（toggle + 2FF）
//    - 系统时钟域 DMI 总线输出（连接 DebugModule）
//
//  时钟域说明：
//    - TAP 状态机、IR/DR 移位：TCK 时钟域（posedge tck）
//    - TDO 输出：TCK 下降沿驱动（negedge tck）
//    - DMI 输出总线、同步逻辑：系统时钟域（posedge clk）
// ============================================================

module JtagDTM (
    // ---------- JTAG 物理引脚 ----------
    input  wire        tck,
    input  wire        tms,
    input  wire        tdi,
    output wire        tdo,
    input  wire        trst_n,     // JTAG 异步复位，低有效；不用时接 1'b1

    // ---------- 系统时钟（用于跨域同步） ----------
    input  wire        clk,
    input  wire        rst,        // 系统同步复位，高有效

    // ---------- DMI 总线（系统时钟域，已同步输出） ----------
    output reg  [6:0]  dmi_addr,
    output reg  [31:0] dmi_wdata,
    output reg  [1:0]  dmi_op,     // 0=nop, 1=read, 2=write
    output reg         dmi_req,    // 系统时钟域单周期脉冲
    input  wire [31:0] dmi_rdata,  // DM 返回数据（系统时钟域）
    input  wire [1:0]  dmi_resp,   // 0=ok, 2=fail, 3=busy
    input  wire        dmi_ack     // DM 完成确认（系统时钟域单周期）
);

// ============================================================
//  一、TAP 状态编码
// ============================================================
localparam [3:0]
    TEST_LOGIC_RESET = 4'd0,
    RUN_TEST_IDLE    = 4'd1,
    SELECT_DR_SCAN   = 4'd2,
    CAPTURE_DR       = 4'd3,
    SHIFT_DR         = 4'd4,
    EXIT1_DR         = 4'd5,
    PAUSE_DR         = 4'd6,
    EXIT2_DR         = 4'd7,
    UPDATE_DR        = 4'd8,
    SELECT_IR_SCAN   = 4'd9,
    CAPTURE_IR       = 4'd10,
    SHIFT_IR         = 4'd11,
    EXIT1_IR         = 4'd12,
    PAUSE_IR         = 4'd13,
    EXIT2_IR         = 4'd14,
    UPDATE_IR        = 4'd15;

// ============================================================
//  二、IR 指令编码及常数
// ============================================================
localparam [4:0]
    IR_IDCODE  = 5'h01,
    IR_DTMCS   = 5'h10,
    IR_DMI     = 5'h11,
    IR_BYPASS  = 5'h1F;

// IDCODE：bit[0]=1（IEEE 1149.1 标准要求）
localparam [31:0] IDCODE_VAL = 32'h1000563;

// DTMCS 固定字段
localparam [2:0] DTMCS_IDLE  = 3'd1;  // 建议在 Run-Test/Idle 停留的周期数
localparam [3:0] DTMCS_ABITS = 4'd7;  // DMI 地址宽度 = 7 位
localparam [3:0] DTMCS_VER   = 4'd1;  // Debug Spec 版本 = 0.13

// ============================================================
//  三、TCK 时钟域寄存器
// ============================================================

// TAP 状态机
reg [3:0] tap_state;

// IR 寄存器
reg [4:0] ir_reg;    // 当前生效的 IR
reg [4:0] ir_shift;  // IR 移位中间寄存器

// DR 移位寄存器（32位 IDCODE/DTMCS，41位 DMI，1位 BYPASS）
reg [31:0] dr_shift_32;  // IDCODE 或 DTMCS 的移位寄存器
reg [40:0] dmi_shift;    // DMI 移位寄存器，格式：{addr[6:0], data[31:0], op[1:0]}
reg        bypass_bit;   // BYPASS 移位寄存器

// DTMCS 可写字段
reg [1:0]  dmistat;      // DMI 最近操作状态：0=ok, 2=fail, 3=busy（读写在 TCK 域）

// TCK 域：DMI 请求 toggle 信号（每次有效的 UPDATE_DR 翻转一次）
reg        dmi_req_tck_tog;

// TCK 域：锁存 UPDATE_DR 时的 DMI 内容
reg [6:0]  dmi_addr_tck;
reg [31:0] dmi_wdata_tck;
reg [1:0]  dmi_op_tck;

// 系统时钟域回传的响应数据（在 clk 域 ack 后锁存，供 TCK 域 CAPTURE_DR 读取）
// 驱动域：系统时钟域（clk）
reg [31:0] dmi_resp_rdata; // 上次 DM 返回的读数据
reg [1:0]  dmi_resp_stat;  // 上次 DM 返回的状态

// ============================================================
//  四、DTMCS 读出值（组合）
// ============================================================
wire [31:0] dtmcs_rval;
assign dtmcs_rval = {
    14'b0,          // [31:18] 保留
    1'b0,           // [17] dmihardreset（只写，读返回 0）
    1'b0,           // [16] dmireset（只写，读返回 0）
    3'b0,           // [15:13] 保留
    DTMCS_IDLE,     // [12:10] idle
    dmistat,        // [9:8]   dmistat（当前 DMI 错误状态）
    DTMCS_ABITS,    // [7:4]   abits（DMI 地址位宽）
    DTMCS_VER       // [3:0]   version
};

// ============================================================
//  五、TAP 状态机 + IR + DR（全部 TCK 上升沿，trst_n 异步复位）
// ============================================================
always @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
        // ---------- 异步复位 ----------
        tap_state        <= TEST_LOGIC_RESET;
        ir_reg           <= IR_IDCODE;      // 复位后默认 IDCODE
        ir_shift         <= 5'b11111;
        dr_shift_32      <= 32'b0;
        dmi_shift        <= 41'b0;
        bypass_bit       <= 1'b0;
        dmistat          <= 2'b00;
        dmi_req_tck_tog  <= 1'b0;
        dmi_addr_tck     <= 7'b0;
        dmi_wdata_tck    <= 32'b0;
        dmi_op_tck       <= 2'b0;
    end else begin

        // ======================================================
        //  TAP 状态转换（标准 16 状态机）
        // ======================================================
        case (tap_state)
            TEST_LOGIC_RESET: tap_state <= tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE:    tap_state <= tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_DR_SCAN:   tap_state <= tms ? SELECT_IR_SCAN   : CAPTURE_DR;
            CAPTURE_DR:       tap_state <= tms ? EXIT1_DR         : SHIFT_DR;
            SHIFT_DR:         tap_state <= tms ? EXIT1_DR         : SHIFT_DR;
            EXIT1_DR:         tap_state <= tms ? UPDATE_DR        : PAUSE_DR;
            PAUSE_DR:         tap_state <= tms ? EXIT2_DR         : PAUSE_DR;
            EXIT2_DR:         tap_state <= tms ? UPDATE_DR        : SHIFT_DR;
            UPDATE_DR:        tap_state <= tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_IR_SCAN:   tap_state <= tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR:       tap_state <= tms ? EXIT1_IR         : SHIFT_IR;
            SHIFT_IR:         tap_state <= tms ? EXIT1_IR         : SHIFT_IR;
            EXIT1_IR:         tap_state <= tms ? UPDATE_IR        : PAUSE_IR;
            PAUSE_IR:         tap_state <= tms ? EXIT2_IR         : PAUSE_IR;
            EXIT2_IR:         tap_state <= tms ? UPDATE_IR        : SHIFT_IR;
            UPDATE_IR:        tap_state <= tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            default:          tap_state <= TEST_LOGIC_RESET;
        endcase

        // ======================================================
        //  TEST_LOGIC_RESET：强制复位 IR
        // ======================================================
        if (tap_state == TEST_LOGIC_RESET) begin
            ir_reg   <= IR_IDCODE;
            ir_shift <= 5'b11111;
        end

        // ======================================================
        //  IR 扫描路径
        // ======================================================
        if (tap_state == CAPTURE_IR) begin
            // 捕获：低 2 位固定为 01（JTAG 标准）
            ir_shift <= {ir_reg[4:2], 2'b01};
        end
        if (tap_state == SHIFT_IR) begin
            // LSB first 移入
            ir_shift <= {tdi, ir_shift[4:1]};
        end
        if (tap_state == UPDATE_IR) begin
            ir_reg <= ir_shift;
        end

        // ======================================================
        //  DR 扫描路径
        // ======================================================

        // ----- CAPTURE_DR：根据当前 IR 加载捕获值 -----
        if (tap_state == CAPTURE_DR) begin
            case (ir_reg)
                IR_IDCODE: dr_shift_32 <= IDCODE_VAL;
                IR_DTMCS:  dr_shift_32 <= dtmcs_rval;
                IR_DMI: begin
                    // 捕获上次操作的结果：{addr, rdata, resp}
                    // dmi_resp_rdata / dmi_resp_stat 由系统时钟域在 dmi_ack 后更新
                    // TCK 远慢于 clk，此时结果必然已稳定
                    dmi_shift <= {dmi_addr_tck, dmi_resp_rdata, dmi_resp_stat};
                    // 同时更新 dmistat（反映上次操作结果）
                    dmistat <= dmi_resp_stat;
                end
                IR_BYPASS: bypass_bit <= 1'b0;
                default:   bypass_bit <= 1'b0;
            endcase
        end

        // ----- SHIFT_DR：LSB first 移位 -----
        if (tap_state == SHIFT_DR) begin
            case (ir_reg)
                IR_IDCODE: dr_shift_32 <= {tdi, dr_shift_32[31:1]};
                IR_DTMCS:  dr_shift_32 <= {tdi, dr_shift_32[31:1]};
                IR_DMI:    dmi_shift   <= {tdi, dmi_shift[40:1]};
                IR_BYPASS: bypass_bit  <= tdi;
                default:   bypass_bit  <= tdi;
            endcase
        end

        // ----- UPDATE_DR：锁存移位结果，触发操作 -----
        if (tap_state == UPDATE_DR) begin
            case (ir_reg)
                IR_DTMCS: begin
                    // dmihardreset（bit17）：硬复位 DMI 状态
                    if (dr_shift_32[17]) begin
                        dmistat         <= 2'b00;
                        dmi_req_tck_tog <= 1'b0;  // 取消可能挂起的请求
                    end
                    // dmireset（bit16）：仅清除 dmistat 错误标志
                    if (dr_shift_32[16]) begin
                        dmistat <= 2'b00;
                    end
                end
                IR_DMI: begin
                    // 锁存新的 DMI 操作内容
                    // dmi_shift 格式：[40:34]=addr, [33:2]=data, [1:0]=op
                    dmi_addr_tck  <= dmi_shift[40:34];
                    dmi_wdata_tck <= dmi_shift[33:2];
                    dmi_op_tck    <= dmi_shift[1:0];
                    // 仅当 op 非 nop 时才发起请求（toggle）
                    if (dmi_shift[1:0] != 2'b00) begin
                        dmi_req_tck_tog <= ~dmi_req_tck_tog;
                    end
                end
                default: ;
            endcase
        end

    end // else
end // always TCK

// ============================================================
//  六、TDO 输出（negedge TCK 驱动，保证 TDI 建立时间）
// ============================================================
reg tdo_reg;

always @(negedge tck or negedge trst_n) begin
    if (!trst_n) begin
        tdo_reg <= 1'b0;
    end else begin
        case (tap_state)
            SHIFT_DR: begin
                case (ir_reg)
                    IR_IDCODE: tdo_reg <= dr_shift_32[0];
                    IR_DTMCS:  tdo_reg <= dr_shift_32[0];
                    IR_DMI:    tdo_reg <= dmi_shift[0];
                    default:   tdo_reg <= bypass_bit;
                endcase
            end
            SHIFT_IR: tdo_reg <= ir_shift[0];
            default:  tdo_reg <= 1'b0;
        endcase
    end
end

assign tdo = tdo_reg;

// ============================================================
//  七、跨时钟域：TCK → 系统时钟域
//  策略：toggle + 3-FF（2FF同步 + 1FF边沿检测）
// ============================================================

reg sync_tog_ff1, sync_tog_ff2, sync_tog_ff3;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sync_tog_ff1 <= 1'b0;
        sync_tog_ff2 <= 1'b0;
        sync_tog_ff3 <= 1'b0;
    end else begin
        // 2-FF 同步消除亚稳态
        sync_tog_ff1 <= dmi_req_tck_tog;
        sync_tog_ff2 <= sync_tog_ff1;
        // 第 3 拍用于边沿检测
        sync_tog_ff3 <= sync_tog_ff2;
    end
end

// toggle 边沿变化 → 单周期脉冲
wire dmi_req_pulse = sync_tog_ff2 ^ sync_tog_ff3;

// ============================================================
//  八、系统时钟域：DMI 总线输出
//  在 toggle 边沿脉冲时锁存 TCK 域稳定的请求内容，并发出 req 脉冲
//  （TCK 远慢于 clk，dmi_addr/wdata/op_tck 已稳定多个 clk 周期）
// ============================================================

always @(posedge clk or posedge rst) begin
    if (rst) begin
        dmi_addr  <= 7'b0;
        dmi_wdata <= 32'b0;
        dmi_op    <= 2'b0;
        dmi_req   <= 1'b0;
    end else begin
        // req 默认为 0，仅在 pulse 时拉高一个周期
        dmi_req <= 1'b0;
        if (dmi_req_pulse) begin
            dmi_addr  <= dmi_addr_tck;
            dmi_wdata <= dmi_wdata_tck;
            dmi_op    <= dmi_op_tck;
            dmi_req   <= 1'b1;
        end
    end
end

// ============================================================
//  九、系统时钟域：锁存 DM 响应，供 TCK 域 CAPTURE_DR 读取
//  dmi_resp_rdata / dmi_resp_stat 在 clk 域驱动，
//  TCK 域只读（CAPTURE_DR 时采样）
//  因 TCK << clk，无需额外同步
// ============================================================

always @(posedge clk or posedge rst) begin
    if (rst) begin
        dmi_resp_rdata <= 32'b0;
        dmi_resp_stat  <= 2'b0;
    end else if (dmi_ack) begin
        dmi_resp_rdata <= dmi_rdata;
        dmi_resp_stat  <= dmi_resp;
    end
end

endmodule

`endif // JTAG_DTM_SV
