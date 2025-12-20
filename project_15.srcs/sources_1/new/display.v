`timescale 1ns/1ps
module matrix_display #(
    parameter CLK_FREQ = 100_000_000,      // 时钟频率 100MHz
    parameter BAUD_RATE = 115200,          // 波特率
    parameter MAX_MATRICES = 12            // 最大矩阵数量
)(
    // 系统接口
    input wire clk,
    input wire rst_n,
    
    // 控制接口
    input wire display_en,                  // 显示使能，高电平有效
    
    // 批量查询接口
    output reg query_en,                    // 查询使能
    output reg [3:0] query_id,              // 查询ID
    input wire [2:0] q_rows,                // 查询结果行数
    input wire [2:0] q_cols,                // 查询结果列数
    input wire [99:0] q_data,               // 查询结果数据
    input wire q_valid,                     // 查询结果有效
    
    // 统计信息接口
    input wire [3:0] total_matrices,        // 总矩阵数量
    input wire [124:0] matrix_info_flat,    // 规格统计信息展平
    
    // UART发送接口
    output reg uart_tx_start,               // UART发送开始
    output reg [7:0] uart_tx_data,          // UART发送数据
    input wire uart_tx_busy,                // UART发送忙标志
    
    // 状态输出
    output reg display_done,                // 显示完成标志
    output reg [3:0] disp_state             // 显示状态（用于调试）
);
// ===== 状态机定义 =====
localparam ST_IDLE      = 4'b0000;  // 空闲状态
localparam ST_START     = 4'b0001;  // 开始显示
localparam ST_QUERY     = 4'b0010;  // 查询状态
localparam ST_WAIT_DATA = 4'b0011;  // 等待数据
localparam ST_SEND_HDR  = 4'b0100;  // 发送头部
localparam ST_SEND_DATA = 4'b0101;  // 发送数据
localparam ST_NEXT      = 4'b0110;  // 下一个矩阵
localparam ST_SEND_STAT = 4'b0111;  // 发送统计
localparam ST_DONE      = 4'b1000;  // 完成状态

// ===== 内部寄存器 =====
reg [3:0] state, next_state;
reg [3:0] matrix_id;               // 当前矩阵ID
reg [2:0] row_idx;                 // 当前行索引
reg [2:0] col_idx;                 // 当前列索引
reg [99:0] data_buffer;            // 数据缓存
reg [2:0] rows_buffer;             // 行数缓存
reg [2:0] cols_buffer;             // 列数缓存
reg [4:0] byte_counter;            // 字节计数器
reg [2:0] char_counter;            // 字符计数器
reg [7:0] tx_buffer;               // 发送缓冲区
reg data_ready;                    // 数据准备就绪标志

// ===== ASCII码定义 =====
localparam ASCII_SPACE  = 8'h20;   // 空格
localparam ASCII_CR     = 8'h0D;   // 回车
localparam ASCII_LF     = 8'h0A;   // 换行
localparam ASCII_COLON  = 8'h3A;   // 冒号
localparam ASCII_LBRACK = 8'h5B;   // [
localparam ASCII_RBRACK = 8'h5D;   // ]
localparam ASCII_DASH   = 8'h2D;   // -

// ===== 十六进制转ASCII函数 =====
function [7:0] hex_to_ascii;
    input [3:0] hex;
    begin
        if (hex <= 4'h9)
            hex_to_ascii = 8'h30 + hex;  // '0'-'9'
        else
            hex_to_ascii = 8'h41 + (hex - 4'hA);  // 'A'-'F'
    end
endfunction

// ===== 状态机主逻辑 =====
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= ST_IDLE;
        disp_state <= ST_IDLE;
    end else begin
        state <= next_state;
        disp_state <= state;
    end
end

always @(*) begin
    next_state = state;
    case (state)
        ST_IDLE: begin
            if (display_en) begin
                next_state = ST_START;
            end
        end
        
        ST_START: begin
            next_state = ST_QUERY;
        end
        
        ST_QUERY: begin
            next_state = ST_WAIT_DATA;
        end
        
        ST_WAIT_DATA: begin
            if (data_ready) begin
                next_state = ST_SEND_HDR;
            end else if (matrix_id >= total_matrices) begin
                next_state = ST_SEND_STAT;
            end else if (!display_en) begin
                next_state = ST_IDLE;
            end
        end
        
        ST_SEND_HDR: begin
            if (byte_counter == 5'd21 && !uart_tx_busy) begin
                next_state = ST_SEND_DATA;
            end
        end
        
        ST_SEND_DATA: begin
            if (byte_counter == 0 && row_idx == rows_buffer && !uart_tx_busy) begin
                next_state = ST_NEXT;
            end
        end
        
        ST_NEXT: begin
            if (matrix_id < total_matrices) begin
                next_state = ST_QUERY;
            end else begin
                next_state = ST_SEND_STAT;
            end
        end
        
        ST_SEND_STAT: begin
            if (byte_counter == 5'd18 && !uart_tx_busy) begin
                next_state = ST_DONE;
            end
        end
        
        ST_DONE: begin
            if (!display_en) begin
                next_state = ST_IDLE;
            end
        end
        
        default: next_state = ST_IDLE;
    endcase
end

// ===== 主控制逻辑 =====
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        query_en <= 1'b0;
        query_id <= 4'b0;
        matrix_id <= 4'b0;
        uart_tx_start <= 1'b0;
        uart_tx_data <= 8'b0;
        display_done <= 1'b0;
        byte_counter <= 5'b0;
        char_counter <= 3'b0;
        row_idx <= 3'b0;
        col_idx <= 3'b0;
        data_buffer <= 100'b0;
        rows_buffer <= 3'b0;
        cols_buffer <= 3'b0;
        data_ready <= 1'b0;
    end else begin
        // 默认值
        query_en <= 1'b0;
        uart_tx_start <= 1'b0;
        
        case (state)
            ST_IDLE: begin
                matrix_id <= 4'b0;
                display_done <= 1'b0;
                data_ready <= 1'b0;
            end
            
            ST_START: begin
                matrix_id <= 4'b0;
                data_ready <= 1'b0;
            end
            
            ST_QUERY: begin
                if (matrix_id < total_matrices) begin
                    query_en <= 1'b1;
                    query_id <= matrix_id;
                    data_ready <= 1'b0;
                end
            end
            
            ST_WAIT_DATA: begin
                if (q_valid) begin
                    // 缓存查询结果
                    data_buffer <= q_data;
                    rows_buffer <= q_rows;
                    cols_buffer <= q_cols;
                    data_ready <= 1'b1;
                end
            end
            
            ST_SEND_HDR: begin
                if (!uart_tx_busy) begin
                    uart_tx_start <= 1'b1;
                    case (byte_counter)
                        5'd0:  uart_tx_data <= ASCII_CR;
                        5'd1:  uart_tx_data <= ASCII_LF;
                        5'd2:  uart_tx_data <= 8'h4D;  // 'M'
                        5'd3:  uart_tx_data <= 8'h61;  // 'a'
                        5'd4:  uart_tx_data <= 8'h74;  // 't'
                        5'd5:  uart_tx_data <= 8'h72;  // 'r'
                        5'd6:  uart_tx_data <= 8'h69;  // 'i'
                        5'd7:  uart_tx_data <= 8'h78;  // 'x'
                        5'd8:  uart_tx_data <= ASCII_SPACE;
                        5'd9:  uart_tx_data <= 8'h23;  // '#'
                        5'd10: uart_tx_data <= hex_to_ascii(matrix_id[3:0]);
                        5'd11: uart_tx_data <= ASCII_COLON;
                        5'd12: uart_tx_data <= ASCII_SPACE;
                        5'd13: uart_tx_data <= ASCII_LBRACK;
                        5'd14: uart_tx_data <= hex_to_ascii({1'b0, rows_buffer});
                        5'd15: uart_tx_data <= 8'h78;  // 'x'
                        5'd16: uart_tx_data <= hex_to_ascii({1'b0, cols_buffer});
                        5'd17: uart_tx_data <= ASCII_RBRACK;
                        5'd18: uart_tx_data <= ASCII_COLON;
                        5'd19: uart_tx_data <= ASCII_SPACE;
                        5'd20: begin
                            // 发送第一个元素
                            if (rows_buffer > 0 && cols_buffer > 0) begin
                                uart_tx_data <= hex_to_ascii(data_buffer[3:0]);
                                row_idx <= 3'b0;
                                col_idx <= 3'b1;
                            end
                        end
                        default: ; // 不发送
                    endcase
                    
                    if (byte_counter < 5'd20) begin
                        byte_counter <= byte_counter + 1;
                    end else begin
                        byte_counter <= 5'd0;
                    end
                end
            end
            
            ST_SEND_DATA: begin
                if (!uart_tx_busy) begin
                    if (row_idx < rows_buffer) begin
                        if (col_idx < cols_buffer) begin
                            // 发送空格
                            uart_tx_start <= 1'b1;
                            uart_tx_data <= ASCII_SPACE;
                            
                            // 等待下一个周期发送数据
                            col_idx <= col_idx + 1;
                        end else begin
                            // 发送回车换行
                            uart_tx_start <= 1'b1;
                            uart_tx_data <= ASCII_CR;
                            
                            row_idx <= row_idx + 1;
                            col_idx <= 3'b0;
                        end
                    end else begin
                        // 所有数据发送完成
                        row_idx <= 3'b0;
                        col_idx <= 3'b0;
                    end
                end else begin
                    // 如果UART忙，等待
                    if (!uart_tx_busy) begin
                        if (row_idx < rows_buffer) begin
                            // 发送数据
                            if (col_idx > 0) begin
                                // 发送元素
                                uart_tx_start <= 1'b1;
                                uart_tx_data <= hex_to_ascii(
                                    data_buffer[(row_idx * cols_buffer + col_idx - 1) * 4 +: 4]
                                );
                            end
                        end
                    end
                end
            end
            
            ST_NEXT: begin
                matrix_id <= matrix_id + 1;
                data_ready <= 1'b0;
                byte_counter <= 5'b0;
            end
            
            ST_SEND_STAT: begin
                if (!uart_tx_busy) begin
                    uart_tx_start <= 1'b1;
                    case (byte_counter)
                        5'd0:  uart_tx_data <= ASCII_CR;
                        5'd1:  uart_tx_data <= ASCII_LF;
                        5'd2:  uart_tx_data <= ASCII_DASH;
                        5'd3:  uart_tx_data <= ASCII_DASH;
                        5'd4:  uart_tx_data <= ASCII_DASH;
                        5'd5:  uart_tx_data <= ASCII_CR;
                        5'd6:  uart_tx_data <= ASCII_LF;
                        5'd7:  uart_tx_data <= 8'h54;  // 'T'
                        5'd8:  uart_tx_data <= 8'h6F;  // 'o'
                        5'd9:  uart_tx_data <= 8'h74;  // 't'
                        5'd10: uart_tx_data <= 8'h61;  // 'a'
                        5'd11: uart_tx_data <= 8'h6C;  // 'l'
                        5'd12: uart_tx_data <= ASCII_COLON;
                        5'd13: uart_tx_data <= ASCII_SPACE;
                        5'd14: begin
                            // 发送总矩阵数
                            if (total_matrices < 10) begin
                                uart_tx_data <= 8'h30 + total_matrices;
                            end else begin
                                uart_tx_data <= 8'h30 + (total_matrices / 10);
                            end
                        end
                        5'd15: begin
                            if (total_matrices >= 10) begin
                                uart_tx_data <= 8'h30 + (total_matrices % 10);
                            end else begin
                                uart_tx_data <= ASCII_CR;
                            end
                        end
                        5'd16: begin
                            if (total_matrices >= 10) begin
                                uart_tx_data <= ASCII_CR;
                            end else begin
                                uart_tx_data <= ASCII_LF;
                            end
                        end
                        5'd17: begin
                            if (total_matrices >= 10) begin
                                uart_tx_data <= ASCII_LF;
                            end else begin
                                uart_tx_start <= 1'b0;
                            end
                        end
                        default: ; // 不发送
                    endcase
                    
                    if (byte_counter < 5'd17) begin
                        byte_counter <= byte_counter + 1;
                    end else begin
                        byte_counter <= 5'd0;
                    end
                end
            end
            
            ST_DONE: begin
                display_done <= 1'b1;
            end
        endcase
    end
end
endmodule
