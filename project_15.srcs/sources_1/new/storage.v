`timescale 1ns/1ps

module storage #(
    parameter MAX_MATRICES = 12,
    parameter MAX_PER_TYPE = 2
)(
    // 系统接口
    input wire clk,
    input wire rst_n,
    
    // 配置接口
    input wire [2:0] max_per_type,
    
    // ===== 写入接口 =====
    input wire wr_en,
    input wire [2:0] wr_rows,
    input wire [2:0] wr_cols,
    input wire [99:0] wr_data,
    output reg wr_done,
    output reg [3:0] wr_matrix_id,
    
    // ===== 查询接口 =====
    input wire query_en,
    input wire [3:0] query_id,
    output reg [2:0] q_rows,
    output reg [2:0] q_cols,
    output reg [99:0] q_data,
    output reg q_valid,
    
    // ===== 统计输出 =====
    output reg [3:0] total_matrices,
    output wire [124:0] matrix_info_flat
);

// ===== 内部存储定义 =====
reg [99:0] matrix_data [0:MAX_MATRICES-1];
reg [2:0] matrix_rows [0:MAX_MATRICES-1];
reg [2:0] matrix_cols [0:MAX_MATRICES-1];
reg matrix_valid [0:MAX_MATRICES-1];
reg [4:0] matrix_spec [0:MAX_MATRICES-1];
reg [31:0] matrix_time [0:MAX_MATRICES-1];  // 时间戳

// ===== 规格计数 =====
reg [4:0] spec_count [0:24];  // 25种规格

// ===== 全局时间计数器 =====
reg [31:0] global_time_counter;

// ===== 状态机定义 =====
localparam WR_IDLE = 1'b0;
localparam WR_DO   = 1'b1;
reg wr_state;
reg [4:0] current_spec;
reg [3:0] write_pos;

// ===== 规格计算函数 =====
function [4:0] calc_spec_index;
    input [2:0] rows;
    input [2:0] cols;
    begin
        if (rows >= 1 && rows <= 5 && cols >= 1 && cols <= 5)
            calc_spec_index = (rows - 1) * 5 + (cols - 1);  // 1-5 => 0-24
        else
            calc_spec_index = 5'd31;  // 无效规格
    end
endfunction

// ===== 查找写入位置函数（修正版本）=====
function [3:0] find_write_position;
    input [4:0] spec_idx;
    input [2:0] max_pt;
    
    integer i;
    reg [3:0] result_pos;
    reg found_empty;
    reg [31:0] oldest_time;
    
    begin
        // ===== 关键修改：先检查规格限制！ =====
        
        // 1. 如果该规格已达到上限，必须替换同规格的矩阵
        if (spec_count[spec_idx] >= max_pt && spec_idx != 5'd31) begin
            // 寻找同规格中时间最早的矩阵
            oldest_time = 32'hFFFFFFFF;
            result_pos = 0;
            
            for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                if (matrix_valid[i] && matrix_spec[i] == spec_idx) begin
                    if (matrix_time[i] < oldest_time) begin
                        oldest_time = matrix_time[i];
                        result_pos = i;
                    end
                end
            end
            
            find_write_position = result_pos;
        end 
        // 2. 规格未达上限，先找空位置
        else begin
            // 寻找空位置
            found_empty = 1'b0;
            for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                if (!found_empty && !matrix_valid[i]) begin // 必须同时满足两个条件
                    result_pos = i;
                    found_empty = 1'b1; // 设置标志位，阻止后续的赋值
                end
            end
            
            if (found_empty) begin
                find_write_position = result_pos;
            end else begin
                // 没有空位置，全局替换最早的矩阵
                oldest_time = 32'hFFFFFFFF;
                result_pos = 0;
                
                for (i = 0; i < MAX_MATRICES; i = i + 1) begin
                    if (matrix_valid[i] && matrix_time[i] < oldest_time) begin
                        oldest_time = matrix_time[i];
                        result_pos = i;
                    end
                end
                
                find_write_position = result_pos;
            end
        end
    end
endfunction




// ===== 将spec_count展平为125位向量 =====
genvar gi;
generate
    for (gi = 0; gi < 25; gi = gi + 1) begin : spec_flat_gen
        assign matrix_info_flat[gi*5 +: 5] = spec_count[gi];
    end
endgenerate

integer j, k;  // 循环变量
reg was_valid;
reg [4:0] old_spec;

// ===== 主状态机（修正版本）=====
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位所有状态
        wr_state <= WR_IDLE;
        wr_done <= 0;
        wr_matrix_id <= 0;
        total_matrices <= 0;
        q_valid <= 0;
        global_time_counter <= 0;
        
        // 初始化规格计数
        for (j = 0; j < 25; j = j + 1) begin
            spec_count[j] <= 0;
        end
        
        // 初始化矩阵存储
        for (k = 0; k < MAX_MATRICES; k = k + 1) begin
            matrix_valid[k] <= 0;
            matrix_rows[k] <= 0;
            matrix_cols[k] <= 0;
            matrix_data[k] <= 0;
            matrix_spec[k] <= 0;
            matrix_time[k] <= 0;
        end
        
        // 初始化输出
        q_rows <= 0;
        q_cols <= 0;
        q_data <= 0;
    end else begin
        // 默认输出值
        wr_done <= 0;
        q_valid <= 0;
        
        // 更新全局时间计数器
        global_time_counter <= global_time_counter + 1;
        
        // ===== 写入状态机 =====
        case (wr_state)
            WR_IDLE: begin
                if (wr_en) begin
                    // 计算规格索引
                    current_spec <= calc_spec_index(wr_rows, wr_cols);
                    
                    // 计算写入位置
                    write_pos <= find_write_position(
                        calc_spec_index(wr_rows, wr_cols), 
                        max_per_type
                    );
                    
                    // 进入DO状态
                    wr_state <= WR_DO;
                end
            end
            
            WR_DO: begin
                // 断言写入完成
                wr_done <= 1'b1;
                
                // 记录旧状态（用于统计更新）
                was_valid = matrix_valid[write_pos];
                old_spec = matrix_spec[write_pos];
                
                // 更新矩阵存储
                matrix_valid[write_pos] <= 1'b1;
                matrix_rows[write_pos] <= wr_rows;
                matrix_cols[write_pos] <= wr_cols;
                matrix_data[write_pos] <= wr_data;
                matrix_spec[write_pos] <= current_spec;
                matrix_time[write_pos] <= global_time_counter;
                
                // 更新统计信息
                if (!was_valid) begin
                    // 新增矩阵
                    total_matrices <= total_matrices + 1;
                    spec_count[current_spec] <= spec_count[current_spec] + 1;
                end else if (old_spec != current_spec) begin
                    // 替换不同规格的矩阵
                    spec_count[old_spec] <= spec_count[old_spec] - 1;
                    spec_count[current_spec] <= spec_count[current_spec] + 1;
                end
                // 注意：如果是替换同规格矩阵，规格计数不变
                
                // 更新输出矩阵ID
                wr_matrix_id <= write_pos;
                
                // 返回IDLE状态
                wr_state <= WR_IDLE;
            end
        endcase
        
        // ===== 读取逻辑 =====
        if (query_en) begin
            if (query_id < MAX_MATRICES) begin
                if (matrix_valid[query_id]) begin
                    q_rows <= matrix_rows[query_id];
                    q_cols <= matrix_cols[query_id];
                    q_data <= matrix_data[query_id];
                    q_valid <= 1'b1;
                end
            end
        end
    end
end

endmodule