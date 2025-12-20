`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// matrix_in - 保存原始8位UART数据用于校验，低4位用于矩阵存储
//////////////////////////////////////////////////////////////////////////////////
module matrix_in #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200,
    parameter SEND_END_MS = 50  // 无活动时间阈值
) (
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire rx_done,
    input wire [7:0] rx_data,  // 原始8位UART接收数据
    output reg [2:0] matrix_rows,
    output reg [2:0] matrix_cols,
    output [99:0] matrix_data_flat, // 25元素×4位（低4位有效）
    output reg [4:0] data_index,    // 有效元素个数
    output reg input_rows_done,
    output reg input_cols_done,
    output reg input_data_done,
    output reg dimension_error,     // 维度错误（1~5外）
    output reg element_error,       // 元素错误（≥10）
    output need_restart,
    output reg error_latched
);

// 存储定义：
// matrix_raw[0..26]：保存原始8位数据（用于校验）
// matrix_data[0..26]：保存低4位数据（用于矩阵运算/输出）
integer i;
integer total;  // 预期元素总数（rows×cols）
integer provided;  // 实际接收元素个数（recv_count-2）

localparam SEND_END_CYCLES = (CLK_FREQ/1000) * SEND_END_MS;

reg [7:0] matrix_raw [0:26];   // 新增：原始8位数据存储
reg [3:0] matrix_data [0:26];  // 原有：低4位数据存储
reg [5:0] recv_count;          // 接收字节数（0~27）
reg [31:0] rx_quiet_cnt;       // 无活动计数器
reg element_err_tmp;           // 元素错误临时标志

// 初始化
initial begin
    for (i = 0; i < 27; i = i + 1) begin
        matrix_raw[i] = 8'd0;
        matrix_data[i] = 4'd0;
    end
    recv_count = 6'd0;
    rx_quiet_cnt = 32'd0;
    error_latched = 1'b0;
    dimension_error = 1'b0;
    element_error = 1'b0;
    input_rows_done = 1'b0;
    input_cols_done = 1'b0;
    input_data_done = 1'b0;
    matrix_rows = 3'd0;
    matrix_cols = 3'd0;
    data_index = 5'd0;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位：清空所有存储和标志
        for (i = 0; i < 27; i = i + 1) begin
            matrix_raw[i] <= 8'd0;
            matrix_data[i] <= 4'd0;
        end
        recv_count <= 6'd0;
        rx_quiet_cnt <= 32'd0;
        error_latched <= 1'b0;
        dimension_error <= 1'b0;
        element_error <= 1'b0;
        input_rows_done <= 1'b0;
        input_cols_done <= 1'b0;
        input_data_done <= 1'b0;
        matrix_rows <= 3'd0;
        matrix_cols <= 3'd0;
        data_index <= 5'd0;
    end else begin
        // 1. UART数据接收：同时保存原始8位和低4位
        if (en && rx_done) begin
            if (recv_count < 6'd27) begin
                matrix_raw[recv_count] <= rx_data;  // 保存原始8位（关键修改）
                matrix_data[recv_count] <= rx_data[3:0];  // 低4位用于矩阵
                recv_count <= recv_count + 1'b1;
            end
            rx_quiet_cnt <= 32'd0;  // 重置无活动计数器
        end else begin
            // 无接收时，递增无活动计数器（仅在使能且有接收数据时）
            if (en && recv_count != 6'd0) begin
                if (rx_quiet_cnt < 32'hFFFFFFFF) rx_quiet_cnt <= rx_quiet_cnt + 1'b1;
            end else begin
                rx_quiet_cnt <= 32'd0;
            end
        end

        // 2. 无活动超时：开始校验和处理数据
        if (en && recv_count != 6'd0 && rx_quiet_cnt >= SEND_END_CYCLES) begin
            // 重置状态标志
            input_rows_done <= 1'b0;
            input_cols_done <= 1'b0;
            input_data_done <= 1'b0;
            dimension_error <= 1'b0;
            element_error <= 1'b0;
            error_latched <= 1'b0;

            // 至少需要2字节（行列数）
            if (recv_count >= 2) begin
                // 提取行列数（原始8位数据校验，低3位用于存储）
                matrix_rows <= matrix_raw[0][2:0];  // 行列数仅支持1~5（3位足够）
                matrix_cols <= matrix_raw[1][2:0];
                input_rows_done <= 1'b1;
                input_cols_done <= 1'b1;

                // 3. 维度校验：用原始8位数据判断（避免低4位截断误差）
                if (matrix_raw[0] < 8'd1 || matrix_raw[0] > 8'd5 ||
                    matrix_raw[1] < 8'd1 || matrix_raw[1] > 8'd5) begin
                    dimension_error <= 1'b1;
                    error_latched <= 1'b1;
                end else begin
                    // 维度合法，计算预期元素总数
                    total = matrix_raw[0] * matrix_raw[1];
                    provided = recv_count - 2;  // 实际接收元素个数

                    // 4. 元素校验：用原始8位数据判断（关键修改）
                    element_err_tmp = 1'b0;
                    for (i = 0; i < 25; i = i + 1) begin  // 最大25个元素
                        if (i < provided) begin
                            // 元素值≥10 → 错误（原始8位数据比较）
                            if (matrix_raw[i+2] >= 8'd10) begin
                                element_err_tmp = 1'b1;
                            end
                        end
                    end

                    // 元素错误处理
                    if (element_err_tmp) begin
                        element_error <= 1'b1;
                        error_latched <= 1'b1;
                    end else begin
                        // 元素合法：补零（若实际接收数<预期）
                        for (i = 0; i < 25; i = i + 1) begin
                            if (i >= provided && i < total) begin
                                matrix_data[i+2] <= 4'd0;
                            end
                        end

                        // 更新输出：矩阵元素（低4位）
                        data_index <= total[4:0];
                        input_data_done <= 1'b1;
                        for (i = 0; i < 25; i = i + 1) begin
                            matrix_data[i] <= (i < total) ? matrix_data[i+2] : 4'd0;
                        end
                    end
                end
            end

            // 重置接收计数器，准备下次接收
            recv_count <= 6'd0;
            rx_quiet_cnt <= 32'd0;
        end
    end
end

// 矩阵扁平化输出（25元素×4位，仅低4位有效）
genvar gi;
generate
    for (gi = 0; gi < 25; gi = gi + 1) begin : FLATTEN
        assign matrix_data_flat[(gi*4)+3 : (gi*4)] = matrix_data[gi];
    end
endgenerate

assign need_restart = 1'b0;  // 简化设计：无需重启信号

endmodule
