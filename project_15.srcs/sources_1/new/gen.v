`timescale 1ns / 1ps

module gen #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200,
    parameter SEND_END_MS = 50,
    parameter SUPPORT_MODE = 1,
    parameter MAX_MATRICES = 12,
    parameter MAX_ELEMENTS = 25,
    parameter RAND_SEED = 32'h87654321
) (
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire rx_done,
    input wire [7:0] rx_data,
    
    output reg wr_en,
    output reg [2:0] wr_rows,
    output reg [2:0] wr_cols,
    output reg [99:0] wr_data,
    output reg [3:0] wr_matrix_id,
    output reg wr_done,
    
    output reg param_valid,
    output reg input_complete,
    output reg gen_done,
    output reg [3:0] gen_count,
    output reg error,
    output reg [2:0] error_code,
    output reg error_latched
    

);

// ===== 状态定义 =====
localparam [2:0]
    STATE_IDLE        = 3'b000,
    STATE_RECV_PARAMS = 3'b001,
    STATE_CHECK_PARAMS= 3'b010,
    STATE_GEN_MATRIX  = 3'b011,
    STATE_WRITE_MATRIX= 3'b100,
    STATE_GEN_DONE    = 3'b101,
    STATE_ERROR       = 3'b110;

localparam [2:0]
    ERR_NONE       = 3'b000,
    ERR_DIMENSION  = 3'b001,
    ERR_COUNT      = 3'b010,
    ERR_MODE       = 3'b011,
    ERR_PARAM_CNT  = 3'b100;
reg [2:0] state;
reg [5:0] recv_count;
reg [3:0] expected_k;
reg [31:0] random_seed;
// ===== 参数存储 =====
reg [7:0] param_raw [0:3];
reg [2:0] m_reg, n_reg;
reg [3:0] k_reg;
reg [1:0] mode_reg;
reg [4:0] total_elements;

// ===== 超时控制 =====
localparam SEND_END_CYCLES = (CLK_FREQ/1000) * SEND_END_MS;
reg [31:0] rx_quiet_cnt;
reg [5:0] recv_index;

// ===== 矩阵生成控制 =====
reg [3:0] matrix_counter;
reg [4:0] element_counter;
reg [3:0] current_matrix_id;
reg [99:0] current_matrix_data;
reg [4:0] elements_per_matrix;

// ===== LFSR随机数生成器 =====
reg [31:0] lfsr_reg;
wire [31:0] lfsr_next;
assign lfsr_next = {lfsr_reg[30:0], lfsr_reg[31] ^ lfsr_reg[21] ^ lfsr_reg[1] ^ lfsr_reg[0]};

wire [2:0] expected_params = (SUPPORT_MODE == 1) ? 3'd4 : 3'd3;

// ===== 计算信号 =====
wire [2:0] row_idx;
wire [2:0] col_idx;
wire [3:0] lfsr_low;
wire [3:0] random_mod10;

// 使用除法器计算行列索引
assign row_idx = element_counter / n_reg;
assign col_idx = element_counter % n_reg;
assign lfsr_low = lfsr_reg[3:0];
assign random_mod10 = (lfsr_low >= 4'd10) ? (lfsr_low - 4'd10) : lfsr_low;

// ===== 模式选择逻辑 =====
reg [3:0] elem_value;
always @* begin
    case (mode_reg)
        2'b00: begin // 随机模式
            elem_value = random_mod10;
        end
        
        2'b01: begin // 顺序递增模式
            elem_value = element_counter % 4'd10;
        end
        
        2'b10: begin // 行列索引和模式
            elem_value = (row_idx + col_idx) % 4'd10;
        end
        
        2'b11: begin // 对角线模式
            elem_value = (row_idx == col_idx) ? 4'd1 : 4'd0;
        end
        
        default: begin
            elem_value = random_mod10;
        end
    endcase
end

integer i;
integer bit_offset;
// ===== 主状态机 =====
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位所有寄存器
        state <= STATE_IDLE;
        recv_index <= 6'd0;
        rx_quiet_cnt <= 32'd0;
        param_valid <= 1'b0;
        input_complete <= 1'b0;
        gen_done <= 1'b0;
        error <= 1'b0;
        error_code <= ERR_NONE;
        error_latched <= 1'b0;
        matrix_counter <= 4'd0;
        element_counter <= 5'd0;
        wr_en <= 1'b0;
        wr_done <= 1'b0;
        wr_rows <= 3'd0;
        wr_cols <= 3'd0;
        wr_data <= 100'd0;
        wr_matrix_id <= 4'd0;
        
        m_reg <= 3'd0;
        n_reg <= 3'd0;
        k_reg <= 4'd0;
        mode_reg <= 2'd0;
        total_elements <= 5'd0;
        elements_per_matrix <= 5'd0;
        expected_k <= 4'd0;
        current_matrix_id <= 4'd0;
        current_matrix_data <= 100'd0;
        random_seed <= RAND_SEED;
        
        lfsr_reg <= RAND_SEED;
        
        for (i = 0; i < 4; i = i + 1) begin
            param_raw[i] <= 8'd0;
        end
    end else begin
        // 默认输出
        wr_en <= 1'b0;
        wr_done <= 1'b0;
        
        case (state)
            STATE_IDLE: begin
                if (en) begin
                    state <= STATE_RECV_PARAMS;
                    recv_index <= 6'd0;
                    rx_quiet_cnt <= 32'd0;
                    param_valid <= 1'b0;
                    input_complete <= 1'b0;
                    gen_done <= 1'b0;
                    error <= 1'b0;
                    error_code <= ERR_NONE;
                    error_latched <= 1'b0;
                    matrix_counter <= 4'd0;
                    expected_k <= 4'd0;
                    recv_count <= 6'd0;
                    
                    for (i = 0; i < 4; i = i + 1) begin
                        param_raw[i] <= 8'd0;
                    end
                    
                    lfsr_reg <= random_seed;
                end
            end
            
            STATE_RECV_PARAMS: begin
                if (rx_done && recv_index < 4) begin
                    param_raw[recv_index] <= rx_data;
                    recv_index <= recv_index + 1'b1;
                    recv_count <= recv_index + 1'b1;
                    rx_quiet_cnt <= 32'd0;
                end else if (recv_index > 0) begin
                    if (rx_quiet_cnt < SEND_END_CYCLES) begin
                        rx_quiet_cnt <= rx_quiet_cnt + 1'b1;
                    end
                end
                
                // 超时检测或接收完所有参数
                if ((recv_index >= 3 && rx_quiet_cnt >= SEND_END_CYCLES) || 
                    (recv_index >= 4)) begin
                    state <= STATE_CHECK_PARAMS;
                    input_complete <= 1'b1;
                end
                
                if (!en) begin
                    state <= STATE_IDLE;
                end
            end
            
            STATE_CHECK_PARAMS: begin
                // ===== 参数检查逻辑 =====
                error <= 1'b0;
                error_latched <= 1'b0;
                error_code <= ERR_NONE;
                
                // 检查是否接收到足够参数
                if (recv_index < 3) begin
                    error <= 1'b1;
                    error_latched <= 1'b1;
                    error_code <= ERR_PARAM_CNT;
                end else begin
                    // 提取并检查行数 (m)
                    m_reg <= param_raw[0][2:0];
                    if (param_raw[0] < 8'd1 || param_raw[0] > 8'd5) begin
                        error <= 1'b1;
                        error_latched <= 1'b1;
                        error_code <= ERR_DIMENSION;
                    end
                    
                    // 提取并检查列数 (n)
                    n_reg <= param_raw[1][2:0];
                    if (param_raw[1] < 8'd1 || param_raw[1] > 8'd5) begin
                        error <= 1'b1;
                        error_latched <= 1'b1;
                        error_code <= ERR_DIMENSION;
                    end
                    
                    // 提取并检查生成数量 (k)
                    k_reg <= param_raw[2][3:0];
                    if (param_raw[2] < 8'd1 || param_raw[2] > MAX_MATRICES) begin
                        error <= 1'b1;
                        error_latched <= 1'b1;
                        error_code <= ERR_COUNT;
                    end
                    
                    // 提取并检查生成模式
                    if (SUPPORT_MODE == 1) begin
                        if (recv_index >= 4) begin
                            mode_reg <= param_raw[3][1:0];
                            if (param_raw[3][1:0] > 2'b11) begin
                                error <= 1'b1;
                                error_latched <= 1'b1;
                                error_code <= ERR_MODE;
                            end
                        end else begin
                            mode_reg <= 2'b00;  // 默认模式0
                        end
                    end else begin
                        mode_reg <= 2'b00;  // 固定模式0
                    end
                end
                
                if (!error_latched) begin
                    // 参数有效，准备生成
                    param_valid <= 1'b1;
                    expected_k <= k_reg;
                    
                    // 计算每个矩阵的元素数
                    elements_per_matrix <= m_reg * n_reg;
                    total_elements <= m_reg * n_reg;
                    
                    // 初始化生成状态
                    matrix_counter <= 4'd0;
                    current_matrix_id <= 4'd0;
                    element_counter <= 5'd0;
                    
                    // 清空当前矩阵数据
                    current_matrix_data <= 100'd0;
                    
                    state <= STATE_GEN_MATRIX;
                end else begin
                    // 参数错误，进入错误状态
                    state <= STATE_ERROR;
                end
            end
            
            STATE_GEN_MATRIX: begin
                if (matrix_counter < k_reg) begin
                    if (element_counter < elements_per_matrix) begin
                        // 计算位偏移（使用乘法和加法）
                        bit_offset = element_counter * 4;
                        
                        // 存储元素到扁平化数据
                        case (bit_offset)
                            0:   current_matrix_data[3:0]   <= elem_value;
                            4:   current_matrix_data[7:4]   <= elem_value;
                            8:   current_matrix_data[11:8]  <= elem_value;
                            12:  current_matrix_data[15:12] <= elem_value;
                            16:  current_matrix_data[19:16] <= elem_value;
                            20:  current_matrix_data[23:20] <= elem_value;
                            24:  current_matrix_data[27:24] <= elem_value;
                            28:  current_matrix_data[31:28] <= elem_value;
                            32:  current_matrix_data[35:32] <= elem_value;
                            36:  current_matrix_data[39:36] <= elem_value;
                            40:  current_matrix_data[43:40] <= elem_value;
                            44:  current_matrix_data[47:44] <= elem_value;
                            48:  current_matrix_data[51:48] <= elem_value;
                            52:  current_matrix_data[55:52] <= elem_value;
                            56:  current_matrix_data[59:56] <= elem_value;
                            60:  current_matrix_data[63:60] <= elem_value;
                            64:  current_matrix_data[67:64] <= elem_value;
                            68:  current_matrix_data[71:68] <= elem_value;
                            72:  current_matrix_data[75:72] <= elem_value;
                            76:  current_matrix_data[79:76] <= elem_value;
                            80:  current_matrix_data[83:80] <= elem_value;
                            84:  current_matrix_data[87:84] <= elem_value;
                            88:  current_matrix_data[91:88] <= elem_value;
                            92:  current_matrix_data[95:92] <= elem_value;
                            96:  current_matrix_data[99:96] <= elem_value;
                            default: current_matrix_data[3:0] <= elem_value;
                        endcase
                        
                        // 更新LFSR随机数生成器
                        lfsr_reg <= lfsr_next;
                        random_seed <= lfsr_next;
                        
                        // 递增元素计数器
                        element_counter <= element_counter + 1'b1;
                    end else begin
                        // 当前矩阵生成完成，准备写入
                        element_counter <= 5'd0;
                        state <= STATE_WRITE_MATRIX;
                    end
                end else begin
                    // 所有矩阵生成完成
                    state <= STATE_GEN_DONE;
                end
            end
            
            STATE_WRITE_MATRIX: begin
                // 输出矩阵数据到storage接口
                wr_rows <= m_reg;
                wr_cols <= n_reg;
                wr_data <= current_matrix_data;
                wr_matrix_id <= current_matrix_id;
                wr_en <= 1'b1;
                wr_done <= 1'b1;
                
                // 更新计数器和状态
                matrix_counter <= matrix_counter + 1'b1;
                gen_count <= matrix_counter + 1'b1;
                current_matrix_id <= current_matrix_id + 1'b1;
                
                // 清空当前矩阵数据，准备生成下一个
                current_matrix_data <= 100'd0;
                
                if (matrix_counter + 1 >= k_reg) begin
                    // 这是最后一个矩阵
                    state <= STATE_GEN_DONE;
                end else begin
                    // 继续生成下一个矩阵
                    state <= STATE_GEN_MATRIX;
                end
            end
            
            STATE_GEN_DONE: begin
                gen_done <= 1'b1;
                
                // 等待使能变低，准备下一次
                if (!en) begin
                    state <= STATE_IDLE;
                end
            end
            
            STATE_ERROR: begin
                // 保持错误状态直到使能变低
                if (!en) begin
                    state <= STATE_IDLE;
                end
            end
        endcase
    end
end

endmodule

