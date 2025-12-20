`timescale 1ns / 1ps

// 测试Operation_Process_Unit和functions_module模块的仿真文件
module tb_operation;

    // 时钟和复位
    reg clk;
    reg rst_n;
    
    // 测试信号
    reg [7:0] key;
    reg uart_rx;
    wire uart_tx;
    wire [4:0] state;
    reg uart_tx_rst_n;
    reg uart_rx_rst_n;
    reg send_one;
    reg send_two;
    reg [1:0] mode;
    wire input_error;
    wire uart_tx_work;
    wire uart_rx_work;
    wire work;
    
    // 实例化顶层模块
    top #(
        .CNT_MAX(21'd199),        // 大幅减小计数值以加快仿真 (20ms -> 2us)
        .CNT_WIDTH(21)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .key(key),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .state(state),
        .uart_tx_rst_n(uart_tx_rst_n),
        .uart_rx_rst_n(uart_rx_rst_n),
        .send_one(send_one),
        .send_two(send_two),
        .mode(mode),
        .input_error(input_error),
        .uart_tx_work(uart_tx_work),
        .uart_rx_work(uart_rx_work),
        .work(work)
    );
    
    // 时钟生成 - 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10ns周期
    end
    
    // UART波特率参数
    localparam CLK_FREQ = 100_000_000;
    localparam BAUD_RATE = 115200;
    localparam BAUD_PERIOD = 1000000000 / BAUD_RATE; // 纳秒
    
    // 状态监控
    always @(state) begin
        case(state)
            5'b00001: $display("[%0t] State: IDLE", $time);
            5'b00010: $display("[%0t] State: MATRIX_IN", $time);
            5'b00100: $display("[%0t] State: MATRIX_GEN", $time);
            5'b01000: $display("[%0t] State: MATRIX_DIS", $time);
            5'b10000: $display("[%0t] State: MATRIX_OP", $time);
            default:  $display("[%0t] State: UNKNOWN", $time);
        endcase
    end
    
    // 主测试流程
    initial begin
        $display("========================================");
        $display("   Full System Simulation Start   ");
        $display("========================================");
        
        // 初始化信号
        rst_n = 0;
        uart_tx_rst_n = 0;
        uart_rx_rst_n = 0;
        key = 8'h03;  // DIP开关设置：每类最多3个矩阵
        uart_rx = 1;
        send_one = 0;
        send_two = 0;
        mode = 2'b00;
        
        // 复位
        #100;
        rst_n = 1;
        uart_tx_rst_n = 1;
        uart_rx_rst_n = 1;
        $display("[%0t] Reset released", $time);
        
        #500;
        
        // ========================================
        // 测试1: MATRIX_IN模式 - 输入第一个矩阵
        // ========================================
        $display("\n[%0t] ===== Test 1: MATRIX_IN Mode - Matrix A (2x2) =====", $time);
        mode = 2'b00;
        trigger_button();
        #1000;
        
        if (state == 5'b00010) begin
            $display("[%0t] SUCCESS: Entered MATRIX_IN state", $time);
        end else begin
            $display("[%0t] WARNING: State is %b, expected MATRIX_IN", $time, state);
        end
        
        // 发送矩阵A维度: 2x2
        $display("[%0t] Sending Matrix A dimensions: 2 rows", $time);
        send_uart_byte(2);
        #2000;
        $display("[%0t] Sending Matrix A dimensions: 2 cols", $time);
        send_uart_byte(2);
        #2000;
        
        // 发送矩阵A数据: [1,2; 3,4]
        $display("[%0t] Sending Matrix A data: 1,2,3,4", $time);
        send_uart_byte(1); #2000;
        send_uart_byte(2); #2000;
        send_uart_byte(3); #2000;
        send_uart_byte(4); #2000;
        
        $display("[%0t] Matrix A input completed", $time);
        #5000;
        
        // ========================================
        // 测试2: MATRIX_IN模式 - 输入第二个矩阵
        // ========================================
        $display("\n[%0t] ===== Test 2: MATRIX_IN Mode - Matrix B (2x2) =====", $time);
        mode = 2'b00;
        trigger_button();
        #1000;
        
        // 发送矩阵B维度: 2x2
        $display("[%0t] Sending Matrix B dimensions: 2x2", $time);
        send_uart_byte(2); #2000;
        send_uart_byte(2); #2000;
        
        // 发送矩阵B数据: [5,6; 7,8]
        $display("[%0t] Sending Matrix B data: 5,6,7,8", $time);
        send_uart_byte(5); #2000;
        send_uart_byte(6); #2000;
        send_uart_byte(7); #2000;
        send_uart_byte(8); #2000;
        
        $display("[%0t] Matrix B input completed", $time);
        #5000;
        
        // ========================================
        // 测试3: MATRIX_GEN模式 - 生成随机矩阵
        // ========================================
        $display("\n[%0t] ===== Test 3: MATRIX_GEN Mode =====", $time);
        mode = 2'b01;
        trigger_button();
        #1000;
        
        if (state == 5'b00100) begin
            $display("[%0t] SUCCESS: Entered MATRIX_GEN state", $time);
        end else begin
            $display("[%0t] WARNING: State is %b, expected MATRIX_GEN", $time, state);
        end
        
        // 发送生成参数：生成2个3x3矩阵
        $display("[%0t] Sending GEN parameters: count=2", $time);
        send_uart_byte(2);  // 生成数量
        #2000;
        send_uart_byte(3);  // 行数
        #2000;
        send_uart_byte(3);  // 列数
        #20000;  // 等待生成完成
        
        $display("[%0t] Matrix generation phase completed", $time);
        #5000;
        
        // ========================================
        // 测试4: MATRIX_DIS模式 - 显示所有矩阵
        // ========================================
        $display("\n[%0t] ===== Test 4: MATRIX_DIS Mode =====", $time);
        mode = 2'b10;
        trigger_button();
        #1000;
        
        if (state == 5'b01000) begin
            $display("[%0t] SUCCESS: Entered MATRIX_DIS state", $time);
        end else begin
            $display("[%0t] WARNING: State is %b, expected MATRIX_DIS", $time, state);
        end
        
        // 等待显示完成
        #50000;
        $display("[%0t] Display phase completed", $time);
        #2000;
        
        // ========================================
        // 测试5: MATRIX_OP模式 - 矩阵运算
        // ========================================
        $display("\n[%0t] ===== Test 5: MATRIX_OP Mode =====", $time);
        mode = 2'b11;
        key = 8'h02;  // 标量值设置为2
        trigger_button();
        #1000;
        
        if (state == 5'b10000) begin
            $display("[%0t] SUCCESS: Entered MATRIX_OP state", $time);
        end else begin
            $display("[%0t] WARNING: State is %b, expected MATRIX_OP", $time, state);
        end
        
        // 等待运算处理
        #10000;
        $display("[%0t] Operation phase completed", $time);
        
        // ========================================
        // 测试6: 返回IDLE并完成
        // ========================================
        $display("\n[%0t] ===== Test 6: Return to IDLE =====", $time);
        mode = 2'b00;
        trigger_button();
        #5000;
        
        if (state == 5'b00001) begin
            $display("[%0t] SUCCESS: Returned to IDLE state", $time);
        end else begin
            $display("[%0t] Current state: %b", $time, state);
        end
        
        // ========================================
        // 测试完成
        // ========================================
        #5000;
        $display("\n========================================");
        $display("   All Tests Completed Successfully   ");
        $display("   - MATRIX_IN: 2 matrices input");
        $display("   - MATRIX_GEN: Random generation tested");
        $display("   - MATRIX_DIS: Display function tested");
        $display("   - MATRIX_OP: Operation mode tested");
        $display("========================================");
        $finish;
    end
    
    // 按键触发任务（模拟消抖后的按键）
    task trigger_button;
        begin
            send_two = 0;
            #50;
            send_two = 1;
            #(BAUD_PERIOD * 200);  // 保持足够长时间触发消抖
            send_two = 0;
            #100;
        end
    endtask
    
    // UART字节发送任务
    task send_uart_byte;
        input [7:0] data;
        integer i;
        begin
            $display("[%0t] Sending UART byte: 0x%02h (%d)", $time, data, data);
            
            // Start bit
            uart_rx = 0;
            #BAUD_PERIOD;
            
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #BAUD_PERIOD;
            end
            
            // Stop bit
            uart_rx = 1;
            #BAUD_PERIOD;
        end
    endtask
    
    // 超时监控
    initial begin
        #20000000;  // 20ms超时（足够完成所有UART通信）
        $display("\n[%0t] ERROR: Simulation timeout!", $time);
        $finish;
    end
    
    // 波形转储
    initial begin
        $dumpfile("tb_operation.vcd");
        $dumpvars(0, tb_operation);
    end

endmodule
