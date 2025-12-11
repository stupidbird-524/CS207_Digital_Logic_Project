  `timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/10 21:33:20
// Design Name: 
// Module Name: top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module top #(
    parameter CNT_MAX = 21'd1_999_999,  // 100MHz时钟→20ms防抖（不变）
    parameter CNT_WIDTH = 21            // 计数器位宽自适应（不变）
)  (
    input  wire clk,           // 100MHz 时钟
    input  wire rst_n,      
    input  wire [7:0] key,  // 拨码开关输入
    input  wire uart_rx,       // 从电脑来的 UART RX
    output wire uart_tx,       // 发到电脑的 UART TX
    output  reg [4:0] state,      //显示功能状态
    input uart_tx_rst_n,   //uart发送复位
    input uart_rx_rst_n,   //使能uart复位
    input send_one, //检测上升沿，有一个上升沿就发送一次数据
    input send_two,
    input wire [1:0] mode,
    output input_error,
    output uart_tx_work,
    output uart_rx_work,
    output work
);
assign work=rst_n;
    // ===== UART 接收部分 =====
    wire [7:0] rx_data;
    wire rx_done;
    

assign uart_rx_work = uart_rx_rst_n;
    uart_rx #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) uart_rx_inst (
        .clk(clk),
        .rst_n( uart_rx_rst_n  ),
        .rx(uart_rx),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );

    // ===============================
    // UART 周期性发送逻辑
    // ===============================
    //reg [22:0] send_cnt;   // 对应约 50ms (100MHz * 0.05 = 5_000_000)
   // reg send_flag;
   /* 
    always @(posedge clk or negedge uart_tx_en_n) begin
        if(!uart_tx_en_n) begin
            send_cnt <= 0;
            send_flag <= 0;
        end else if (send_cnt < 23'd5_000_000) begin
            send_cnt <= send_cnt + 1;
            send_flag <= 0;
        end else if (!tx_busy) begin
            send_cnt <= 0;
            send_flag <= 1;  // 每隔 50ms 触发一次发送
        end else begin
            send_flag <= 0;
        end
    end
    */
    
    reg send_one_d1, send_one_d2;
    always @(posedge clk or negedge uart_tx_rst_n) begin
         if(!uart_tx_rst_n) begin
            send_one_d1 <= 1'b0;
            send_one_d2 <= 1'b0;
         end
         else begin 
            send_one_d1 <= send_one;
            send_one_d2 <= send_one_d1;
         end
    end
    wire send_flag; 
    assign send_flag = ~send_one_d1 & send_one_d2;

      reg [CNT_WIDTH-1:0] cnt_20ms;
      reg key_flag;
      reg key_sync1, key_sync2;      
  
      
      always @(posedge clk or negedge uart_tx_rst_n) begin
          if (!uart_tx_rst_n) begin
              key_sync1 <= 1'b0;  
              key_sync2 <= 1'b0;
          end else begin
              key_sync1 <= send_two;
              key_sync2 <= key_sync1;  
          end
      end
  
      
      always @(posedge clk or negedge uart_tx_rst_n) begin
          if (!uart_tx_rst_n) begin
              cnt_20ms <= {CNT_WIDTH{1'b0}};  
          end else if (key_sync2 == 1'b0) begin  
              cnt_20ms <= {CNT_WIDTH{1'b0}};
          end else if (cnt_20ms < CNT_MAX) begin  
              cnt_20ms <= cnt_20ms + 1'b1;
          end else begin
              cnt_20ms <= cnt_20ms;  
          end
      end
  
      
      always @(posedge clk or negedge uart_tx_rst_n) begin
          if (!uart_tx_rst_n) begin
              key_flag <= 1'b0;
          end else if (cnt_20ms == CNT_MAX - 1'b1) begin  
              key_flag <= 1'b1;
          end else begin
              key_flag <= 1'b0;
          end
      end
      
      
      
     

     
    
    assign uart_tx_work = uart_tx_rst_n;

    uart_tx #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) uart_tx_inst (
        .clk(clk),
        .rst_n( uart_tx_rst_n),
        .tx_start(send_flag),
        .tx_data(key),   // 发送当前拨码状态
        .tx(uart_tx),
        .tx_busy(tx_busy)
    );

    // ===== LED 显示接收到的数据 =====
    
    
     localparam IDLE       = 5'b00001;  // Main menu
    localparam MATRIX_IN  = 5'b00010;  // Matrix input
    localparam MATRIX_GEN = 5'b00100;  // Matrix generation
    localparam MATRIX_DIS = 5'b01000;  // Matrix display
    localparam MATRIX_OP  = 5'b10000;  // Matrix operation

       // 声明用于矩阵输入功能的信号
    reg [2:0] matrix_rows;      // 矩阵行数
    reg [2:0] matrix_cols;      // 矩阵列数
    reg [3:0] matrix_data [24:0]; // 存储矩阵元素(最多 5x5=25个元素)
    reg [4:0] data_index;      // 当前正在输入的元素索引
    reg matrix_valid;           // 矩阵是否有效（通过所有检查）

    reg input_rows_done;
    reg input_cols_done;
    reg input_data_done;

    reg [7:0] current_input;

     // 错误标志
    reg dimension_error;
    reg element_error;
    assign input_error = dimension_error | element_error;

    reg [4:0] next_state;

    // UART message to send
    

    always @(posedge clk or negedge rst_n ) begin
        if (!rst_n) begin
            state <= IDLE;
            
            
        end else begin
            state <= next_state;
            
        end
    end

    always @(*) begin
    next_state=state;
       case (state)
            IDLE: begin
                if (key_flag) begin
                  case (mode)
                    2'b00: next_state = MATRIX_IN;  // '1'
                    2'b01: next_state = MATRIX_GEN; // '2'
                    2'b10: next_state = MATRIX_DIS; // '3'
                    2'b11: next_state = MATRIX_OP;  // '4'
                    default: next_state = IDLE;
                  endcase
                end
            end
            MATRIX_IN: begin
                // 读取行
                if(!input_rows_done)begin
                    if(rx_done)begin
                        current_input <= rx_data;
                        if(rx_data > 0 && rx_data < 6)begin
                            matrix_rows <= rx_data;
                            input_rows_done <= 1;
                        end
                        else begin
                            dimension_error <= 1;
                        end
                    end
                    next_state = MATRIX_IN;
                 end
                // 读取列
                else if(!input_cols_done)begin
                    if(rx_done)begin
                        current_input <= rx_data;
                        if(rx_data > 0 && rx_data < 6)begin
                            matrix_cols <= rx_data;
                            input_cols_done <= 1;
                        end
                        else begin
                            dimension_error <= 1;
                        end
                    end
                next_state = MATRIX_IN;
                end
                else if(!input_data_done)begin
                    if(rx_done)begin
                        current_input <= rx_data;

                        if(rx_data > -1 && rx_data < 10)begin

                            matrix_data[data_index] <= rx_data;

                            if(data_index < 25)
                                data_index <= data_index+1;

                            if(data_index == matrix_cols*matrix_rows)
                                input_data_done <= 1;
                        // next_state = IDLE;
                        end
                        else begin
                            element_error <= 1;
                        end

                    end

                next_state = MATRIX_IN;
                end                
            end              
            

            MATRIX_GEN: begin
                // Implement Matrix Generation and Storage logic here
                  next_state=MATRIX_GEN;
               
           end

            MATRIX_DIS: begin
                // Implement Matrix Display logic here
                  next_state=MATRIX_DIS;
                                               
            end

            MATRIX_OP: begin
                // Implement Matrix Operation logic here
                  next_state=MATRIX_OP;
                                               
                  
                
            end

            default: next_state = IDLE;
        endcase
    end

 

endmodule