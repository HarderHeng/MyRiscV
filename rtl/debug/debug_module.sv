`ifndef DEBUG_MODULE_SV
`define DEBUG_MODULE_SV

// ============================================================
//  RISC-V Debug Module（DM）
//  符合 RISC-V Debug Spec 0.13.2
//
//  功能：
//    - 实现最小化 DMI 寄存器集合
//    - 支持 halt / resume CPU（通过 dmcontrol）
//    - 支持 Abstract Command（Access Register，cmdtype=0）
//    - 支持 System Bus Access（SBA，32 位读写）
//    - 单 hart（hartid=0）
//
//  DMI 寄存器映射（spec Table 3.1）：
//    0x04  data0        数据寄存器 0
//    0x10  dmcontrol    DM 控制
//    0x11  dmstatus     DM 状态（只读）
//    0x12  hartinfo     Hart 信息（只读，全 0）
//    0x16  abstractcs   Abstract Command 状态
//    0x17  command      Abstract Command 触发（只写）
//    0x18  abstractauto 自动执行（只读，返回 0）
//    0x1D  nextdm       下一 DM 地址（只读，返回 0）
//    0x20  progbuf0     程序缓冲区 0（默认 NOP，可写）
//    0x21  progbuf1     程序缓冲区 1（默认 EBREAK，可写）
//    0x38  sbcs         System Bus Access 控制
//    0x39  sbaddress0   System Bus 地址（低 32 位）
//    0x3C  sbdata0      System Bus 数据（低 32 位）
//
//  时序：
//    - 普通 DMI 读写：1 周期完成（同周期 ack）
//    - Abstract Command：3 周期（COMMAND写入 → EXECUTING → DONE → ack）
//    - SBA 写：1 周期完成（同周期发出 sba_wen，随后 sba_busy 清零）
//    - SBA 读（由写 sbaddress0 触发）：等待 sba_rdata_vld
//      OpenOCD 会轮询 sbcs.sbbusy 直至为 0，再读 sbdata0，因此异步完成即可
//
//  所有逻辑在系统时钟域（posedge clk，同步复位 rst 高有效）
// ============================================================

module DebugModule (
    input  wire        clk,
    input  wire        rst,         // 系统复位，高有效

    // ---------- DTM 接口（系统时钟域） ----------
    input  wire [6:0]  dmi_addr,
    input  wire [31:0] dmi_wdata,
    input  wire [1:0]  dmi_op,      // 1=read, 2=write
    input  wire        dmi_req,     // 请求脉冲（单周期）
    output reg  [31:0] dmi_rdata,
    output reg  [1:0]  dmi_resp,    // 0=ok, 3=busy
    output reg         dmi_ack,     // 完成脉冲（单周期）

    // ---------- CPU 调试接口 ----------
    output reg         cpu_halt_req,    // 请求 CPU 暂停（电平信号）
    input  wire        cpu_halted,      // CPU 已暂停确认
    output reg         cpu_resume_req,  // 请求 CPU 继续运行（脉冲）
    output reg         cpu_reset_req,   // ndmreset：非调试系统复位（电平）

    // ---------- CPU 寄存器访问（Abstract Command 使用） ----------
    output reg  [4:0]  dbg_reg_raddr,   // 读寄存器地址（组合有效）
    input  wire [31:0] dbg_reg_rdata,   // 读寄存器数据（下一周期有效）
    output reg         dbg_reg_wen,     // 写使能（单周期脉冲）
    output reg  [4:0]  dbg_reg_waddr,   // 写寄存器地址
    output reg  [31:0] dbg_reg_wdata,   // 写寄存器数据
    output wire [31:0] dbg_pc,          // 当前 PC（直连 cpu_pc，只读）
    input  wire [31:0] cpu_pc,          // 来自 CPU 的当前 PC

    // ---------- System Bus Access（SBA） ----------
    output reg  [31:0] sba_addr,
    output reg         sba_ren,         // 读使能（单周期脉冲）
    output reg         sba_wen,         // 写使能（单周期脉冲）
    output reg  [3:0]  sba_be,          // 字节使能（32 位时 = 4'hF）
    output reg  [31:0] sba_wdata,
    input  wire [31:0] sba_rdata,
    input  wire        sba_rdata_vld    // 读数据有效（可同周期或下一周期）
);

// ============================================================
//  一、常数定义
// ============================================================

// DMI 操作码
localparam [1:0]
    DMI_OP_NOP   = 2'b00,
    DMI_OP_READ  = 2'b01,
    DMI_OP_WRITE = 2'b10;

// DMI 响应码
localparam [1:0]
    DMI_RESP_OK   = 2'b00,
    DMI_RESP_FAIL = 2'b10,
    DMI_RESP_BUSY = 2'b11;

// DMI 寄存器地址
localparam [6:0]
    ADDR_DATA0        = 7'h04,
    ADDR_DMCONTROL    = 7'h10,
    ADDR_DMSTATUS     = 7'h11,
    ADDR_HARTINFO     = 7'h12,
    ADDR_ABSTRACTCS   = 7'h16,
    ADDR_COMMAND      = 7'h17,
    ADDR_ABSTRACTAUTO = 7'h18,
    ADDR_NEXTDM       = 7'h1D,
    ADDR_PROGBUF0     = 7'h20,
    ADDR_PROGBUF1     = 7'h21,
    ADDR_SBCS         = 7'h38,
    ADDR_SBADDRESS0   = 7'h39,
    ADDR_SBDATA0      = 7'h3C;

// Abstract Command 错误码（cmderr 字段）
localparam [2:0]
    CMDERR_NONE       = 3'd0,  // 无错误
    CMDERR_BUSY       = 3'd1,  // DM 忙时收到命令
    CMDERR_NOTSUP     = 3'd2,  // 不支持的命令
    CMDERR_EXCEPTION  = 3'd3,  // 执行异常
    CMDERR_HALTRESUME = 3'd4;  // Hart 未处于 halt 状态

// RISC-V 指令常数（progbuf 初始值）
localparam [31:0]
    INST_NOP    = 32'h0000_0013,  // addi x0, x0, 0（NOP）
    INST_EBREAK = 32'h0010_0073;  // ebreak

// sbcs 固定只读字段
localparam [2:0] SBCS_VERSION = 3'd1; // SB version = 1（spec 0.13.2）
localparam [6:0] SBCS_ASIZE   = 7'd32; // 总线地址宽度 32 位

// ============================================================
//  二、内部寄存器
// ============================================================

// --- dmcontrol 字段 ---
reg        dm_active;   // [0]  DM 使能（dmactive）
reg        ndmreset;    // [1]  非调试系统复位
reg        haltreq;     // [31] halt 请求（持续电平，写 dmcontrol 时更新）

// --- abstractcs 字段 ---
reg        abs_busy;    // [12] Abstract Command 正在执行
reg [2:0]  abs_cmderr;  // [10:8] 错误状态（W1C 清零）

// --- data0 ---
reg [31:0] data0;

// --- progbuf ---
reg [31:0] progbuf0;    // 程序缓冲区 0
reg [31:0] progbuf1;    // 程序缓冲区 1

// --- sbcs 可写字段 ---
reg        sb_readonaddr;  // [20] 写 sbaddress0 时自动触发总线读
reg [2:0]  sb_access;      // [19:17] 访问宽度（2=32bit）
reg        sb_autoincr;    // [16] 读写后地址自动递增 4
reg        sb_readondata;  // [15] 读 sbdata0 后自动触发下一次读
reg [2:0]  sb_error;       // [14:12] SBA 错误标志（W1C）
reg        sb_busyerror;   // [22] SBA busy 时访问产生的错误（W1C）

// --- sbaddress0 / sbdata0 ---
reg [31:0] sb_addr;        // System Bus 地址
reg [31:0] sb_data;        // System Bus 读数据缓冲

// --- SBA 内部状态 ---
reg        sba_busy;       // SBA 操作进行中（sbcs.sbbusy）
reg        sba_is_read;    // 当前挂起的 SBA 是读操作

// --- resume_ack 标志 ---
// OpenOCD 在 resume 后检查 dmstatus.allresumeack / anyresumeack
// 策略：发出 cpu_resume_req 时置 1，收到新的 haltreq 时清 0
reg        resume_ack;

// ============================================================
//  三、Abstract Command 状态机
// ============================================================

localparam [1:0]
    ABS_IDLE      = 2'd0,   // 空闲
    ABS_EXECUTING = 2'd1,   // 执行中（发出寄存器读/写请求）
    ABS_DONE      = 2'd2;   // 完成（采样读寄存器结果）

reg [1:0]  abs_state;

// 锁存 command 字段（UPDATE_DR 时解码）
reg [7:0]  cmd_type;      // [31:24] cmdtype（0=Access Register）
reg [2:0]  cmd_aarsize;   // [22:20] 访问宽度（2=32bit）
reg        cmd_postexec;  // [18]    执行 progbuf（本实现忽略）
reg        cmd_transfer;  // [17]    执行寄存器传输
reg        cmd_write;     // [16]    1=写寄存器，0=读寄存器
reg [15:0] cmd_regno;     // [15:0]  目标寄存器编号

// ============================================================
//  四、DMI 请求状态机
// ============================================================

localparam [1:0]
    ST_IDLE       = 2'd0,   // 等待 dmi_req
    ST_PROCESSING = 2'd1;   // 处理请求（1 周期完成）

reg [1:0] dmi_state;

// ============================================================
//  五、组合信号
// ============================================================

// PC 透传
assign dbg_pc = cpu_pc;

// dmstatus 组合值（spec 0.13.2 Table 3.3，共 32 位）
wire [31:0] dmstatus_val;
assign dmstatus_val = {
    9'b0,                           // [31:23] 保留 = 0
    1'b0,                           // [22]    impebreak = 0
    2'b0,                           // [21:20] 保留 = 0
    resume_ack,                     // [19]    allresumeack
    resume_ack,                     // [18]    anyresumeack
    1'b0,                           // [17]    allnonexistent = 0
    1'b0,                           // [16]    anynonexistent = 0
    1'b0,                           // [15]    allunavail = 0
    1'b0,                           // [14]    anyunavail = 0
    (dm_active & ~cpu_halted),      // [13]    allrunning
    (dm_active & ~cpu_halted),      // [12]    anyrunning
    (dm_active &  cpu_halted),      // [11]    allhalted
    (dm_active &  cpu_halted),      // [10]    anyhalted
    1'b1,                           // [9]     authenticated = 1（无认证）
    1'b0,                           // [8]     authbusy = 0
    1'b0,                           // [7]     hasresethaltreq = 0
    1'b0,                           // [6]     confstrptrvalid = 0
    1'b0,                           // [5]     保留 = 0
    5'd2                            // [4:0]   version = 2（spec 0.13）
};

// abstractcs 组合值（spec 0.13.2 Table 3.7，共 32 位）
wire [31:0] abstractcs_val;
assign abstractcs_val = {
    3'b0,        // [31:29] 保留
    5'd2,        // [28:24] progbufsize = 2（有 progbuf0/1）
    11'b0,       // [23:13] 保留
    abs_busy,    // [12]    busy
    1'b0,        // [11]    保留
    abs_cmderr,  // [10:8]  cmderr
    4'b0,        // [7:4]   保留
    4'd1         // [3:0]   datacount = 1（有 data0）
};

// sbcs 组合值（spec 0.13.2 Table 3.20，共 32 位）
wire [31:0] sbcs_val;
assign sbcs_val = {
    2'b0,           // [31:30] 保留
    SBCS_VERSION,   // [29:27] sbversion = 1
    4'b0,           // [26:23] 保留
    sb_busyerror,   // [22]    sbbusyerror（W1C）
    sba_busy,       // [21]    sbbusy（只读）
    sb_readonaddr,  // [20]    sbreadonaddr
    sb_access,      // [19:17] sbaccess
    sb_autoincr,    // [16]    sbautoincrement
    sb_readondata,  // [15]    sbreadondata
    sb_error,       // [14:12] sberror（W1C）
    SBCS_ASIZE,     // [11:5]  sbasize = 32
    1'b0,           // [4]     sbaccess128 = 0
    1'b0,           // [3]     sbaccess64 = 0
    1'b1,           // [2]     sbaccess32 = 1
    1'b0,           // [1]     sbaccess16 = 0
    1'b0            // [0]     sbaccess8 = 0
};

// ============================================================
//  六、主时序逻辑
// ============================================================

always @(posedge clk) begin
    if (rst) begin
        // ---- 全局复位 ----
        dmi_rdata      <= 32'b0;
        dmi_resp       <= DMI_RESP_OK;
        dmi_ack        <= 1'b0;
        dmi_state      <= ST_IDLE;

        dm_active      <= 1'b0;
        ndmreset       <= 1'b0;
        haltreq        <= 1'b0;
        resume_ack     <= 1'b0;

        cpu_halt_req   <= 1'b0;
        cpu_resume_req <= 1'b0;
        cpu_reset_req  <= 1'b0;

        dbg_reg_raddr  <= 5'b0;
        dbg_reg_wen    <= 1'b0;
        dbg_reg_waddr  <= 5'b0;
        dbg_reg_wdata  <= 32'b0;

        data0          <= 32'b0;
        progbuf0       <= INST_NOP;
        progbuf1       <= INST_EBREAK;

        abs_busy       <= 1'b0;
        abs_cmderr     <= CMDERR_NONE;
        abs_state      <= ABS_IDLE;
        cmd_type       <= 8'b0;
        cmd_aarsize    <= 3'b0;
        cmd_postexec   <= 1'b0;
        cmd_transfer   <= 1'b0;
        cmd_write      <= 1'b0;
        cmd_regno      <= 16'b0;

        sba_addr       <= 32'b0;
        sba_ren        <= 1'b0;
        sba_wen        <= 1'b0;
        sba_be         <= 4'hF;
        sba_wdata      <= 32'b0;
        sba_busy       <= 1'b0;
        sba_is_read    <= 1'b0;
        sb_addr        <= 32'b0;
        sb_data        <= 32'b0;
        sb_readonaddr  <= 1'b1;   // 复位后默认使能写地址触发读
        sb_access      <= 3'd2;   // 默认 32 位访问
        sb_autoincr    <= 1'b0;
        sb_readondata  <= 1'b0;
        sb_error       <= 3'd0;
        sb_busyerror   <= 1'b0;

    end else begin

        // ---- 单周期脉冲信号：每周期默认清零 ----
        dmi_ack        <= 1'b0;
        cpu_resume_req <= 1'b0;
        dbg_reg_wen    <= 1'b0;
        sba_ren        <= 1'b0;
        sba_wen        <= 1'b0;

        // ================================================
        //  CPU 控制信号（电平）
        // ================================================
        cpu_halt_req  <= haltreq & dm_active;
        cpu_reset_req <= ndmreset;

        // ================================================
        //  SBA 完成处理
        //  写操作：sba_wen 脉冲发出后下一周期即认为完成
        //  读操作：等待 sba_rdata_vld
        // ================================================
        if (sba_busy) begin
            if (sba_is_read) begin
                // 等待总线返回读数据
                if (sba_rdata_vld) begin
                    sb_data  <= sba_rdata;
                    sba_busy <= 1'b0;
                    if (sb_autoincr) begin
                        sb_addr <= sb_addr + 32'd4;
                    end
                end
            end else begin
                // 写操作：sba_wen 已在上一周期发出，本周期清 busy
                sba_busy <= 1'b0;
                if (sb_autoincr) begin
                    sb_addr <= sb_addr + 32'd4;
                end
            end
        end

        // ================================================
        //  Abstract Command 执行状态机
        //  ABS_IDLE → ABS_EXECUTING → ABS_DONE → ABS_IDLE
        // ================================================
        case (abs_state)
            ABS_IDLE: begin
                // 由 DMI 写 command 触发，转入 ABS_EXECUTING
            end

            ABS_EXECUTING: begin
                // 第 1 周期：发出寄存器读/写请求
                if (cmd_transfer) begin
                    if (cmd_write) begin
                        // 写寄存器：data0 → regno
                        if (cmd_regno == 16'h1020) begin
                            // PC 只读，写操作静默忽略
                        end else if (cmd_regno >= 16'h1000 &&
                                     cmd_regno <= 16'h101F) begin
                            dbg_reg_wen   <= 1'b1;
                            dbg_reg_waddr <= cmd_regno[4:0];
                            dbg_reg_wdata <= data0;
                        end
                        // 其他 regno：spec 允许忽略或报错，此处忽略
                    end else begin
                        // 读寄存器：建立读地址（rdata 下一周期有效）
                        if (cmd_regno == 16'h1020) begin
                            // 读 PC：直接组合取值，在 ABS_DONE 中捕获
                        end else if (cmd_regno >= 16'h1000 &&
                                     cmd_regno <= 16'h101F) begin
                            dbg_reg_raddr <= cmd_regno[4:0];
                        end
                    end
                end
                abs_state <= ABS_DONE;
            end

            ABS_DONE: begin
                // 第 2 周期：采样寄存器读结果，完成操作
                if (cmd_transfer && !cmd_write) begin
                    if (cmd_regno == 16'h1020) begin
                        data0 <= cpu_pc;            // 读 PC
                    end else if (cmd_regno >= 16'h1000 &&
                                 cmd_regno <= 16'h101F) begin
                        data0 <= dbg_reg_rdata;     // 读通用寄存器
                    end
                end
                abs_busy  <= 1'b0;
                abs_state <= ABS_IDLE;
            end

            default: abs_state <= ABS_IDLE;
        endcase

        // ================================================
        //  DMI 请求处理状态机
        // ================================================
        case (dmi_state)

            ST_IDLE: begin
                if (dmi_req) begin
                    dmi_state <= ST_PROCESSING;
                end
            end

            ST_PROCESSING: begin
                // 默认：1 周期完成，resp = ok
                dmi_resp  <= DMI_RESP_OK;
                dmi_rdata <= 32'b0;
                dmi_ack   <= 1'b1;
                dmi_state <= ST_IDLE;

                // ---- READ ----
                if (dmi_op == DMI_OP_READ) begin
                    case (dmi_addr)
                        ADDR_DATA0:
                            dmi_rdata <= data0;

                        ADDR_DMCONTROL:
                            dmi_rdata <= {
                                haltreq,   // [31]
                                1'b0,      // [30] resumereq（只写，读返回 0）
                                1'b0,      // [29] hartreset
                                1'b0,      // [28] ackhavereset
                                1'b0,      // [27] 保留
                                1'b0,      // [26] hasel = 0（单 hart）
                                10'b0,     // [25:16] hartselhi/lo = 0
                                14'b0,     // [15:2] 保留
                                ndmreset,  // [1]
                                dm_active  // [0]
                            };

                        ADDR_DMSTATUS:
                            dmi_rdata <= dmstatus_val;

                        ADDR_HARTINFO:
                            dmi_rdata <= 32'b0;

                        ADDR_ABSTRACTCS:
                            dmi_rdata <= abstractcs_val;

                        ADDR_COMMAND:
                            dmi_rdata <= 32'b0; // command 只写

                        ADDR_ABSTRACTAUTO:
                            dmi_rdata <= 32'b0;

                        ADDR_NEXTDM:
                            dmi_rdata <= 32'b0;

                        ADDR_PROGBUF0:
                            dmi_rdata <= progbuf0;

                        ADDR_PROGBUF1:
                            dmi_rdata <= progbuf1;

                        ADDR_SBCS:
                            dmi_rdata <= sbcs_val;

                        ADDR_SBADDRESS0:
                            dmi_rdata <= sb_addr;

                        ADDR_SBDATA0: begin
                            // 返回上次读取到的 sb_data
                            dmi_rdata <= sb_data;
                            // sbreadondata：读 sbdata0 后自动触发下一次总线读
                            if (sb_readondata && !sba_busy &&
                                !sb_busyerror && (sb_error == 3'd0)) begin
                                sba_ren     <= 1'b1;
                                sba_addr    <= sb_addr;
                                sba_be      <= 4'hF;
                                sba_busy    <= 1'b1;
                                sba_is_read <= 1'b1;
                            end
                        end

                        default:
                            dmi_rdata <= 32'b0;
                    endcase

                // ---- WRITE ----
                end else if (dmi_op == DMI_OP_WRITE) begin
                    case (dmi_addr)

                        // data0：直接写（abs_busy 时写入无效，spec 允许）
                        ADDR_DATA0: begin
                            if (!abs_busy) begin
                                data0 <= dmi_wdata;
                            end
                        end

                        // dmcontrol：控制 halt/resume/reset
                        ADDR_DMCONTROL: begin
                            dm_active <= dmi_wdata[0];
                            ndmreset  <= dmi_wdata[1];

                            if (dmi_wdata[0]) begin
                                // haltreq：写入时更新（电平）
                                haltreq <= dmi_wdata[31];

                                // resumereq（bit30）：写 1 触发一次 resume
                                if (dmi_wdata[30] && cpu_halted) begin
                                    cpu_resume_req <= 1'b1;
                                    resume_ack     <= 1'b1;
                                end
                            end

                            // 写 dmactive=1（从 0→1）时清 resume_ack
                            if (!dm_active && dmi_wdata[0]) begin
                                resume_ack <= 1'b0;
                            end

                            // haltreq 重新置位时清 resume_ack
                            if (dmi_wdata[31] && dmi_wdata[0]) begin
                                resume_ack <= 1'b0;
                            end
                        end

                        // abstractcs：仅 cmderr 字段支持 W1C 清除
                        ADDR_ABSTRACTCS: begin
                            if (!abs_busy) begin
                                // W1C：写 1 的位清零
                                abs_cmderr <= abs_cmderr & ~dmi_wdata[10:8];
                            end
                        end

                        // command：触发 Abstract Command 执行
                        ADDR_COMMAND: begin
                            if (abs_busy) begin
                                // DM 正忙：报 busy 错误（不执行命令）
                                abs_cmderr <= CMDERR_BUSY;

                            end else if (abs_cmderr != CMDERR_NONE) begin
                                // 有未清除错误：忽略新命令（spec 规定）

                            end else begin
                                // 解码命令字段
                                cmd_type     <= dmi_wdata[31:24];
                                cmd_aarsize  <= dmi_wdata[22:20];
                                cmd_postexec <= dmi_wdata[18];
                                cmd_transfer <= dmi_wdata[17];
                                cmd_write    <= dmi_wdata[16];
                                cmd_regno    <= dmi_wdata[15:0];

                                // 合法性检查
                                if (dmi_wdata[31:24] != 8'd0) begin
                                    // cmdtype 不支持（只支持 0=Access Register）
                                    abs_cmderr <= CMDERR_NOTSUP;

                                end else if (dmi_wdata[22:20] != 3'd2) begin
                                    // aarsize 不支持（只支持 2=32bit）
                                    abs_cmderr <= CMDERR_NOTSUP;

                                end else if (!cpu_halted || !dm_active) begin
                                    // Hart 未 halt，无法执行
                                    abs_cmderr <= CMDERR_HALTRESUME;

                                end else begin
                                    // 合法命令，启动执行状态机
                                    abs_busy  <= 1'b1;
                                    abs_state <= ABS_EXECUTING;
                                end
                            end
                        end

                        // progbuf：可写（OpenOCD 会写入调试程序）
                        ADDR_PROGBUF0: progbuf0 <= dmi_wdata;
                        ADDR_PROGBUF1: progbuf1 <= dmi_wdata;

                        // sbcs：配置 System Bus Access 参数
                        ADDR_SBCS: begin
                            // W1C 清除错误标志
                            if (dmi_wdata[22]) sb_busyerror <= 1'b0;
                            sb_error <= sb_error & ~dmi_wdata[14:12];
                            // 可写配置字段
                            sb_readonaddr <= dmi_wdata[20];
                            sb_access     <= dmi_wdata[19:17];
                            sb_autoincr   <= dmi_wdata[16];
                            sb_readondata <= dmi_wdata[15];
                        end

                        // sbaddress0：设置 SBA 地址，可选自动触发读
                        ADDR_SBADDRESS0: begin
                            if (sba_busy) begin
                                // SBA 正忙时访问：记录 busyerror
                                sb_busyerror <= 1'b1;
                            end else begin
                                sb_addr <= dmi_wdata;
                                // sbreadonaddr：写地址时自动触发总线读
                                if (sb_readonaddr && (sb_error == 3'd0)) begin
                                    sba_ren     <= 1'b1;
                                    sba_addr    <= dmi_wdata;
                                    sba_be      <= 4'hF;
                                    sba_busy    <= 1'b1;
                                    sba_is_read <= 1'b1;
                                end
                            end
                        end

                        // sbdata0：写触发总线写操作
                        ADDR_SBDATA0: begin
                            if (sba_busy) begin
                                sb_busyerror <= 1'b1;
                            end else if (sb_error == 3'd0) begin
                                sba_wen     <= 1'b1;
                                sba_addr    <= sb_addr;
                                sba_be      <= 4'hF;
                                sba_wdata   <= dmi_wdata;
                                sba_busy    <= 1'b1;
                                sba_is_read <= 1'b0;
                            end
                        end

                        default: ; // 未实现地址：忽略写操作
                    endcase
                end
                // dmi_op == DMI_OP_NOP：直接 ack，rdata = 0

            end // ST_PROCESSING

            default: dmi_state <= ST_IDLE;

        endcase

    end // else (not rst)
end // always @(posedge clk)

endmodule

`endif // DEBUG_MODULE_SV
