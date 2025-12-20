`timescale 1ns / 1ps

module tb_top;

  // 信号声明
  reg clk;
  reg rst_n;
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

  // 内部信号
  reg [7:0] tx_data;
  reg tx_en;

  // 实例化待测模块 (top)
  top #(
    .CNT_MAX(21'd1_999_999),
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

  // 时钟生成
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100MHz 时钟周期 = 10ns
  end

  // 仿真初始化
  initial begin
    // 初始化信号
    rst_n = 0;
    key = 8'h00;
    uart_rx = 1; // 空闲状态为高电平
    uart_tx_rst_n = 0;
    uart_rx_rst_n = 0;
    send_one = 0;
    send_two = 0;
    mode = 2'b00;
    tx_data = 8'h00;
    tx_en = 0;

    // 复位
    #10 rst_n = 1;
    uart_tx_rst_n = 1;
    uart_rx_rst_n = 1;

    // 选择 MATRIX_IN 状态
    mode = 2'b00;
    send_two = 1;
    #20 send_two=0;

    // 等待状态切换
    #100;

    // 发送行数 (例如 3)
    send_uart_byte(3);
    #100;

    // 发送列数 (例如 4)
    send_uart_byte(4);
    #100;

    // 发送矩阵数据 (例如 12 个元素)
    send_uart_byte(1);
    #100;
    send_uart_byte(2);
    #100;
    send_uart_byte(3);
    #100;
    send_uart_byte(4);
    #100;
    send_uart_byte(5);
    #100;
    send_uart_byte(6);
    #100;
    send_uart_byte(7);
    #100;
    send_uart_byte(8);
    #100;
    send_uart_byte(9);
    #100;
    send_uart_byte(0);
    #100;
    send_uart_byte(1);
    #100;
    send_uart_byte(2);
    #100;
    // 结束仿真
    #1000 $finish;
  end

  // UART 发送任务
  task send_uart_byte;
    input [7:0] data;
    integer i;

    begin
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

  // 时序参数
  localparam CLK_FREQ = 100_000_000;
  localparam BAUD_RATE = 115200;
  localparam BAUD_PERIOD = 1000000000 / BAUD_RATE; // 纳秒
endmodule