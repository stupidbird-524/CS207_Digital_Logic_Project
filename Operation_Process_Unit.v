module Operation_Process_Unit #(
    parameter CLK_FREQ = 50_000_000 // 系统时钟频率，用于产生1秒定时
)(
    input  wire         clk,
    input  wire         rst_n,

    // --- 用户控制接口 ---
    input  wire         confirm_btn,     // 确认按键（经过消抖）
    input  wire         op_code,         // 0: 矩阵加法, 1: 矩阵乘法
    
    // --- 矩阵维度信息 (来自存储模块或选择模块) ---
    input  wire [7:0]   matA_row,
    input  wire [7:0]   matA_col,
    input  wire [7:0]   matB_row,
    input  wire [7:0]   matB_col,

    // --- 倒计时动态配置接口 ---
    input  wire         config_en,       // 配置使能信号 (高电平有效)
    input  wire [3:0]   config_val,      // 用户设置的倒计时时长 (5-15)

    // --- 系统输出 ---
    output reg          error_led,       // 报错 LED：高电平点亮
    output reg [3:0]    cnt_display,     // 输出给数码管的倒计时数值
    output reg          calc_start,      // 启动计算核心的脉冲信号
    output reg          sel_reset,       // 超时重置信号：通知选择模块清空当前选择
    output reg [2:0]    status_code      // 状态码 (用于调试或VGA显示状态)
);

    //====================================================
    // 1. 状态机状态定义
    //====================================================
    localparam S_IDLE   = 3'd0; // 等待用户选择运算数
    localparam S_CHECK  = 3'd1; // 校验维度合法性 (瞬态)
    localparam S_CALC   = 3'd2; // 合法，进入计算模式
    localparam S_ERROR  = 3'd3; // 非法，报错并倒计时
    
    reg [2:0] state, next_state;

    //====================================================
    // 2. 维度合法性判定逻辑 (组合逻辑)
    //====================================================
    reg is_dim_valid;

    always @(*) begin
        if (op_code == 1'b0) begin // 矩阵加法
            // 要求：A行=B行 且 A列=B列
            if ((matA_row == matB_row) && (matA_col == matB_col))
                is_dim_valid = 1'b1;
            else
                is_dim_valid = 1'b0;
        end 
        else begin // 矩阵乘法
            // 要求：A列 = B行
            if (matA_col == matB_row)
                is_dim_valid = 1'b1;
            else
                is_dim_valid = 1'b0;
        end
    end

    //====================================================
    // 3. 倒计时配置与定时器逻辑
    //====================================================
    reg [3:0] timeout_setting; // 存储用户设定的时长
    reg [3:0] current_cnt;     // 当前倒计时计数
    reg [31:0] timer_tick;     // 1秒分频计数器
    wire       pulse_1s;       // 1秒脉冲

    // 3.1 动态配置倒计时时长 (限制在5-15秒)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_setting <= 4'd10; // 默认10秒
        end else if (config_en) begin
            if (config_val < 4'd5)       timeout_setting <= 4'd5;
            else if (config_val > 4'd15) timeout_setting <= 4'd15;
            else                         timeout_setting <= config_val;
        end
    end

    // 3.2 产生1秒脉冲
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_tick <= 0;
        end else if (state == S_ERROR) begin
            if (timer_tick >= CLK_FREQ - 1) 
                timer_tick <= 0;
            else 
                timer_tick <= timer_tick + 1;
        end else begin
            timer_tick <= 0; // 非Error状态清零
        end
    end
    assign pulse_1s = (timer_tick == CLK_FREQ - 1);

    // 3.3 倒计时逻辑
    reg timeout_flag; // 倒计时结束标志

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_cnt <= 4'd10;
            timeout_flag <= 1'b0;
        end else if (state == S_CHECK && !is_dim_valid) begin
            // 刚进入报错状态时，装载设定值
            current_cnt <= timeout_setting;
            timeout_flag <= 1'b0;
        end else if (state == S_ERROR) begin
            if (pulse_1s) begin
                if (current_cnt > 0)
                    current_cnt <= current_cnt - 1;
                else
                    timeout_flag <= 1'b1; // 倒计时归零
            end
        end else begin
            timeout_flag <= 1'b0;
        end
    end

    //====================================================
    // 4. 状态机逻辑 (FSM)
    //====================================================
    
    // 4.1 状态跳转
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // 4.2 次态判断
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                // 用户按下确认键，开始检查
                if (confirm_btn) 
                    next_state = S_CHECK;
            end

            S_CHECK: begin
                if (is_dim_valid)
                    next_state = S_CALC;  // 符合要求 -> 计算
                else
                    next_state = S_ERROR; // 不符合 -> 报错
            end

            S_ERROR: begin
                if (timeout_flag) begin
                    // c) 倒计时结束，未修正 -> 回到IDLE重置
                    next_state = S_IDLE;
                end else if (confirm_btn) begin
                    // b) 倒计时期间，用户重新按确认 -> 重新检查
                    next_state = S_CHECK;
                end
            end

            S_CALC: begin
                // 这里假设进入计算后，等待外部重置或自动返回
                // 实际项目中通常接收 calc_done 信号返回 IDLE
                // 这里为了演示流程，保持在CALC状态
                next_state = S_CALC; 
            end

            default: next_state = S_IDLE;
        endcase
    end

    //====================================================
    // 5. 输出逻辑控制
    //====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            error_led   <= 1'b0;
            calc_start  <= 1'b0;
            sel_reset   <= 1'b0;
            cnt_display <= 4'd0;
            status_code <= S_IDLE;
        end else begin
            status_code <= state; // 输出当前状态给外部观测

            case (state)
                S_IDLE: begin
                    error_led   <= 1'b0;
                    calc_start  <= 1'b0;
                    cnt_display <= 4'd0; 
                    // 如果刚从超时状态回来(利用一个标志位判断)，发出sel_reset
                    // 这里简化逻辑：如果是IDLE且上一周期是ERROR且timeout_flag为1(需寄存器辅助)，则复位
                    // 为简化，直接判断：如果在IDLE，始终不主动复位，复位动作由状态跳变沿触发
                    // 下面使用更稳健的方法：
                    if (timeout_flag) sel_reset <= 1'b1; // 超时时刻产生的脉冲
                    else sel_reset <= 1'b0;
                end

                S_CHECK: begin
                    error_led   <= 1'b0;
                    calc_start  <= 1'b0;
                    sel_reset   <= 1'b0;
                    cnt_display <= 4'd0;
                end

                S_ERROR: begin
                    error_led   <= 1'b1;         // 点亮红灯
                    calc_start  <= 1'b0;
                    sel_reset   <= 1'b0;
                    cnt_display <= current_cnt;  // 数码管显示倒计时
                end

                S_CALC: begin
                    error_led   <= 1'b0;
                    calc_start  <= 1'b1;         // 启动计算单元
                    sel_reset   <= 1'b0;
                    cnt_display <= 4'd0;
                end
            endcase
        end
    end

endmodule
