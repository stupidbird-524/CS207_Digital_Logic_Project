`timescale 1ns / 1ps

module config_manager (
    input wire clk,
    input wire rst_n,
    input wire [1:0] dip_sw,           // 来自top模块的拨码开关
    output reg [2:0] max_per_type,    // 输出配置值 (2-5)
    output reg config_changed         // 新增：配置变化信号（高电平有效）
);

// ===== 配置变化检测 =====
reg [1:0] prev_dip_sw;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prev_dip_sw <= 2'b00;
        config_changed <= 1'b0;
    end else begin
        // 存储上一次的拨码开关值
        prev_dip_sw <= dip_sw;
        
        // 检测变化，产生一个时钟周期的脉冲
        if (prev_dip_sw != dip_sw) begin
            config_changed <= 1'b1;
        end else begin
            config_changed <= 1'b0;
        end
    end
end

// ===== 配置映射逻辑 =====
always @(*) begin
    case(dip_sw)
        2'b00: max_per_type = 3'd2;  // 0 -> 2
        2'b01: max_per_type = 3'd3;  // 1 -> 3
        2'b10: max_per_type = 3'd4;  // 2 -> 4
        2'b11: max_per_type = 3'd5;  // 3 -> 5
        // 其他组合映射到默认值
        default: max_per_type = 3'd2; // 默认为2
    endcase
end

endmodule

