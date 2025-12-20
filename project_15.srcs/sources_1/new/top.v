`timescale 1ns / 1ps

module top #(
    parameter CNT_MAX = 21'd1_999_999,  // 100MHz��20ms����
    parameter CNT_WIDTH = 21            // ������λ������Ӧ
) (
    input  wire clk,                    // 100MHz ʱ��
    input  wire rst_n,      
    input  wire [7:0] key,              // ���뿪������
    input  wire uart_rx,                // ����UART RX
    output wire uart_tx,                // ����UART TX
    output reg [4:0] state,             // ��ʾ����״̬
    input  uart_tx_rst_n,               // UART���͸�λ
    input  uart_rx_rst_n,               // UART���ո�λ
    input  send_one,                    // �����ش������η���
    input  send_two,                    // ȷ��/����/չʾ/���㰴��
    input  wire [1:0] mode,             // ģʽѡ��
    output reg input_error,             // ��������־��LED������
    output uart_tx_work,
    output uart_rx_work,
    output work
);

// ===== �����ź����� =====
assign work = rst_n;
assign uart_rx_work = uart_rx_rst_n;
assign uart_tx_work = uart_tx_rst_n;

// ===== ״̬������ =====
localparam IDLE       = 5'b00001;
localparam MATRIX_IN  = 5'b00010;
localparam MATRIX_GEN = 5'b00100;
localparam MATRIX_DIS = 5'b01000;
localparam MATRIX_OP  = 5'b10000;

// ===== UART����ģ��ʵ���� =====
wire [7:0] rx_data;
wire rx_done;
uart_rx #(
    .CLK_FREQ(100_000_000),
    .BAUD_RATE(115200)
) uart_rx_inst (
    .clk(clk),
    .rst_n(uart_rx_rst_n),
    .rx(uart_rx),
    .rx_data(rx_data),
    .rx_done(rx_done)
);

// ===== ���ʹ����߼���send_one�����أ�=====
reg send_one_d1, send_one_d2;
always @(posedge clk or negedge uart_tx_rst_n) begin
    if (!uart_tx_rst_n) begin
        send_one_d1 <= 1'b0;
        send_one_d2 <= 1'b0;
    end else begin 
        send_one_d1 <= send_one;
        send_one_d2 <= send_one_d1;
    end
end
wire send_flag = ~send_one_d1 & send_one_d2;

// ===== send_two�����߼���20ms��=====
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

// ===== config_managerģ��ʵ���� =====
wire [2:0] max_per_type;
wire config_changed;
config_manager config_manager_inst (
    .clk(clk),
    .rst_n(rst_n),
    .dip_sw(key[1:0]),           // ʹ�ò��뿪�ص�3λ
    .max_per_type(max_per_type),
    .config_changed(config_changed)
);

// ===== �洢ģ�鸴λ�źţ����ñ仯ʱ��λ��=====
wire storage_rst_n = rst_n && !config_changed;

// ===== storageģ���ź����� =====
wire storage_wr_done;
wire [3:0] storage_wr_matrix_id;
wire [2:0] storage_q_rows;
wire [2:0] storage_q_cols;
wire [99:0] storage_q_data;
wire storage_q_valid;
wire [3:0] storage_total_matrices;
wire [124:0] storage_matrix_info_flat; 

// ===== ��������ģ���ź����� =====
wire [2:0] matrix_rows;
wire [2:0] matrix_cols;
wire [99:0] matrix_data_flat;
wire [4:0] data_index;
wire input_rows_done;
wire input_cols_done;
wire input_data_done;
wire need_restart;
wire error_latched;
wire dimension_error;
wire element_error;
wire en_matrix_in = (state == MATRIX_IN);

// ===== Gen����ģ���ź����� =====
wire gen_wr_en;
wire [2:0] gen_wr_rows;
wire [2:0] gen_wr_cols;
wire [99:0] gen_wr_data;
wire [3:0] gen_wr_matrix_id;
wire gen_wr_done;
wire gen_param_valid;
wire gen_input_complete;
wire gen_done;
wire [3:0] gen_count;
wire gen_error;
wire [2:0] gen_error_code;
wire gen_error_latched;
// ===== Operation_Process_Unit信号声明 =====
wire opu_error_led;
wire [3:0] opu_cnt_display;
wire opu_calc_start;
wire opu_sel_reset;
wire [2:0] opu_status_code;

// ===== functions_module信号声明 =====
wire func_opDone;
wire func_unableToOperate;
wire func_mem_read_en;
wire func_mem_write_en;
wire [5:0] func_mem_addr;
wire [3:0] func_mem_data_out;
reg [3:0] func_mem_data_in;
// ���Ӿ��������дʹ��?
wire matrix_in_wr_en = (state == MATRIX_IN) && input_data_done && !error_latched;

// ===== Displayģ���ź����� =====
wire display_done;
wire [4:0] disp_state;
wire display_query_en;
wire [3:0] display_query_id;
wire display_tx_start;
wire [7:0] display_tx_data;
wire en_display = (state == MATRIX_DIS);

// ===== ����չ���Ĵ������� =====
// matrix_in_wr_en չ��
reg [1:0] matrix_in_wr_cnt;
reg [2:0] matrix_in_rows_latched;
reg [2:0] matrix_in_cols_latched;
reg [99:0] matrix_in_data_latched;

// gen_wr_done չ��
reg [1:0] gen_wr_cnt;
reg [2:0] gen_rows_latched;
reg [2:0] gen_cols_latched;
reg [99:0] gen_data_latched;

// storage_wr_done չ��
reg [1:0] wr_done_cnt;

// storage_q_valid չ��
reg [1:0] q_valid_cnt;
reg [2:0] q_rows_latched;
reg [2:0] q_cols_latched;
reg [99:0] q_data_latched;

// ===== չ������źŶ���? =====
wire matrix_in_wr_en_wide = (matrix_in_wr_cnt > 0);
wire gen_wr_en_wide = (gen_wr_cnt > 0);
wire storage_wr_done_wide = (wr_done_cnt > 0);
wire storage_q_valid_wide = (q_valid_cnt > 0);

// ===== storageģ���·ѡ������ʹ��չ������źţ�=====
// д�ӿڶ�·ѡ��
wire storage_wr_en = matrix_in_wr_en_wide || gen_wr_en_wide;
wire [2:0] storage_wr_rows = matrix_in_wr_en_wide ? matrix_in_rows_latched : gen_rows_latched;
wire [2:0] storage_wr_cols = matrix_in_wr_en_wide ? matrix_in_cols_latched : gen_cols_latched;
wire [99:0] storage_wr_data = matrix_in_wr_en_wide ? matrix_in_data_latched : gen_data_latched;

// ===== Gen����ģ��ʹ�� =====
wire en_gen = (state == MATRIX_GEN);

// ===== Gen����ģ��ʵ���� =====
gen #(
    .CLK_FREQ(100_000_000),
    .BAUD_RATE(115200),
    .SEND_END_MS(50),
    .SUPPORT_MODE(1),           // ֧��ģʽ����
    .MAX_MATRICES(12),
    .MAX_ELEMENTS(25),
    .RAND_SEED(32'h87654321)
) gen_inst (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_gen),                // MATRIX_GEN״̬ʱʹ��
    .rx_done(rx_done),
    .rx_data(rx_data),
    
    // �����storage�ӿ�
    .wr_en(gen_wr_en),
    .wr_rows(gen_wr_rows),
    .wr_cols(gen_wr_cols),
    .wr_data(gen_wr_data),
    .wr_matrix_id(gen_wr_matrix_id),
    .wr_done(gen_wr_done),
    
    // ״̬���?
    .param_valid(gen_param_valid),
    .input_complete(gen_input_complete),
    .gen_done(gen_done),
    .gen_count(gen_count),
    .error(gen_error),
    .error_code(gen_error_code),
    .error_latched(gen_error_latched)
);

// ������ѯ�ӿڶ�·ѡ��
wire storage_query_en = display_query_en;
wire [3:0] storage_query_id = display_query_id;

// ===== storageģ��ʵ���� =====
storage #(
    .MAX_MATRICES(12)
) storage_inst (
    .clk(clk),
    .rst_n(storage_rst_n),
    .max_per_type(max_per_type),
    
    // д�ӿ�
    .wr_en(storage_wr_en),
    .wr_rows(storage_wr_rows),
    .wr_cols(storage_wr_cols),
    .wr_data(storage_wr_data),
    .wr_done(storage_wr_done),
    .wr_matrix_id(storage_wr_matrix_id),
    
    // ������ѯ�ӿ�
    .query_en(storage_query_en),
    .query_id(storage_query_id),
    .q_rows(storage_q_rows),
    .q_cols(storage_q_cols),
    .q_data(storage_q_data),
    .q_valid(storage_q_valid),
    
    // ͳ����Ϣ
    .total_matrices(storage_total_matrices),
    .matrix_info_flat(storage_matrix_info_flat)
);

// ===== ��������ģ��ʵ���� =====
matrix_in #(
    .CLK_FREQ(100_000_000),
    .BAUD_RATE(115200),
    .SEND_END_MS(50)
) matrix_in_inst (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_matrix_in),
    .rx_done(rx_done),
    .rx_data(rx_data),
    .matrix_rows(matrix_rows),
    .matrix_cols(matrix_cols),
    .matrix_data_flat(matrix_data_flat),
    .data_index(data_index),
    .input_rows_done(input_rows_done),
    .input_cols_done(input_cols_done),
    .input_data_done(input_data_done),
    .dimension_error(dimension_error),
    .element_error(element_error),
    .need_restart(need_restart),
    .error_latched(error_latched)
);
// ===== UART����ģ���ź� =====
wire tx_busy;
// ===== Displayģ��ʵ���� =====
matrix_display #(
    .CLK_FREQ(100_000_000),
    .BAUD_RATE(115200),
    .MAX_MATRICES(12)  
) display_inst (
    .clk(clk),
    .rst_n(rst_n),
    
    // ���ƽӿ�
    .display_en(en_display),
   
    // ������ѯ�ӿ� - ʹ��չ������źź���������?
    .query_en(display_query_en),
    .query_id(display_query_id),
    .q_rows(q_rows_latched),
    .q_cols(q_cols_latched),
    .q_data(q_data_latched),
    .q_valid(storage_q_valid_wide),
    
    // ͳ����Ϣ�ӿ�
    .total_matrices(storage_total_matrices),
    .matrix_info_flat(storage_matrix_info_flat),
    
    // UART���ͽӿ�
    .uart_tx_start(display_tx_start),
    .uart_tx_data(display_tx_data),
    .uart_tx_busy(tx_busy),
    
    // ״̬���?
    .display_done(display_done),
    .disp_state(disp_state[3:0])  // 只连接低4�?
);



// ===== UART���Ͷ�·ѡ���� =====
wire uart_tx_start_sel = (state == MATRIX_DIS) ? display_tx_start : send_flag;
wire [7:0] uart_tx_data_sel = (state == MATRIX_DIS) ? display_tx_data : key;

// ===== UART����ģ��ʵ���� =====
uart_tx #(
    .CLK_FREQ(100_000_000),
    .BAUD_RATE(115200)
) uart_tx_inst (
    .clk(clk),
    .rst_n(uart_tx_rst_n),
    .tx_start(uart_tx_start_sel),
    .tx_data(uart_tx_data_sel),
    .tx(uart_tx),
    .tx_busy(tx_busy)
);
// ===== Operation_Process_Unit模块实例�? =====
Operation_Process_Unit #(
    .CLK_FREQ(100_000_000)
) opu_inst (
    .clk(clk),
    .rst_n(rst_n),
    .confirm_btn(key_flag),              // 使用消抖后的按键标志
    .op_code(mode[0]),                   // 使用mode的最低位作为运算�?
    .matA_row({5'b0, storage_q_rows}),   // 扩展�?8�?
    .matA_col({5'b0, storage_q_cols}),   // 扩展�?8�?
    .matB_row({5'b0, storage_q_rows}),   // 扩展�?8�?
    .matB_col({5'b0, storage_q_cols}),   // 扩展�?8�?
    .config_en(1'b0),                    // 暂时禁用配置
    .config_val(4'd10),                  // 默认10�?
    .error_led(opu_error_led),
    .cnt_display(opu_cnt_display),
    .calc_start(opu_calc_start),
    .sel_reset(opu_sel_reset),
    .status_code(opu_status_code)
);

// ===== functions_module模块实例�? =====
functions_module func_inst (
    .clk(clk),
    .reset(~rst_n),                      // functions_module使用高电平复�?
    .funSel(key[7:6]),                  // 使用mode作为功能选择
    .funEn(opu_calc_start),              // 使用OPU的calc_start启动计算
    .scalar_val(key[5:2]),               // 使用key的低4位作为标量�??
    .A_m({1'b0, storage_q_rows}),        // 扩展�?4�?
    .A_n({1'b0, storage_q_cols}),        // 扩展�?4�?
    .B_m({1'b0, storage_q_rows}),        // 扩展�?4�?
    .B_n({1'b0, storage_q_cols}),        // 扩展�?4�?
    .opDone(func_opDone),
    .unableToOperate(func_unableToOperate),
    .mem_read_en(func_mem_read_en),
    .mem_write_en(func_mem_write_en),
    .mem_addr(func_mem_addr),
    .mem_data_in(func_mem_data_in),
    .mem_data_out(func_mem_data_out)
);

// ===== �?单的内存数据输入逻辑（需要根据实际存储模块调整）=====
always @(func_mem_read_en or func_mem_addr) begin
    func_mem_data_in = 4'b0;  // 默认值，�?要根据实际情况连接到存储模块
end

// ===== ����չ���߼� =====
// 1. matrix_in_wr_en չ��
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        matrix_in_wr_cnt <= 2'b00;
        matrix_in_rows_latched <= 3'b0;
        matrix_in_cols_latched <= 3'b0;
        matrix_in_data_latched <= 100'b0;
    end else begin
        // ���ԭ�? matrix_in_wr_en ����
        if (matrix_in_wr_en) begin
            // ��������
            matrix_in_rows_latched <= matrix_rows;
            matrix_in_cols_latched <= matrix_cols;
            matrix_in_data_latched <= matrix_data_flat;
            // ����չ��������
            matrix_in_wr_cnt <= 2'b10;  // չ��2����
        end else if (matrix_in_wr_cnt > 0) begin
            // �ݼ�������
            matrix_in_wr_cnt <= matrix_in_wr_cnt - 1'b1;
        end
    end
end

// 2. gen_wr_done չ����gen_integrated��wr_done��
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        gen_wr_cnt <= 2'b00;
        gen_rows_latched <= 3'b0;
        gen_cols_latched <= 3'b0;
        gen_data_latched <= 100'b0;
    end else begin
        // ���ԭ�? gen_wr_done ����
        if (gen_wr_done) begin
            // ��������
            gen_rows_latched <= gen_wr_rows;
            gen_cols_latched <= gen_wr_cols;
            gen_data_latched <= gen_wr_data;
            // ����չ��������
            gen_wr_cnt <= 2'b10;  // չ��2����
        end else if (gen_wr_cnt > 0) begin
            // �ݼ�������
            gen_wr_cnt <= gen_wr_cnt - 1'b1;
        end
    end
end

// 3. storage_wr_done չ��
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_done_cnt <= 2'b00;
    end else begin
        // ���ԭ�? storage_wr_done ����
        if (storage_wr_done) begin
            // ����չ��������
            wr_done_cnt <= 2'b10;  // չ��2����
        end else if (wr_done_cnt > 0) begin
            // �ݼ�������
            wr_done_cnt <= wr_done_cnt - 1'b1;
        end
    end
end

// 4. storage_q_valid չ��
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        q_valid_cnt <= 2'b00;
        q_rows_latched <= 3'b0;
        q_cols_latched <= 3'b0;
        q_data_latched <= 100'b0;
    end else begin
        // ���ԭ�? storage_q_valid ����
        if (storage_q_valid) begin
            // �����ѯ���
            q_rows_latched <= storage_q_rows;
            q_cols_latched <= storage_q_cols;
            q_data_latched <= storage_q_data;
            // ����չ��������
            q_valid_cnt <= 2'b10;  // չ��2����
        end else if (q_valid_cnt > 0) begin
            // �ݼ�������
            q_valid_cnt <= q_valid_cnt - 1'b1;
        end
    end
end

// ===== ���������������matrix_in��gen_integrated����=====
reg [CNT_WIDTH-1:0] err_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        input_error <= 1'b0;
        err_cnt <= {CNT_WIDTH{1'b0}};
    end else begin
        // ���matrix_in��gen_integratedģ��Ĵ���?
        // ���ִ��󲻿���ͬʱ��������Ϊ����ģʽ��ͬʱ����
        if (error_latched || gen_error_latched) begin
            // ��⵽����������?1�����÷���������
            err_cnt <= {CNT_WIDTH{1'b0}};
            input_error <= 1'b1;
        end else begin
            // �޴����ӳ�20ms�����㣨����ë�̣�
            if (err_cnt < CNT_MAX) begin
                err_cnt <= err_cnt + 1'b1;
            end else begin
                input_error <= 1'b0;
            end
        end
    end
end

// ===== ״̬���߼� =====
reg [4:0] next_state;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

always @(*) begin
    next_state = state;
    case (state)
        IDLE: begin
            if (key_flag) begin
                case (mode)
                    2'b00: next_state = MATRIX_IN;
                    2'b01: next_state = MATRIX_GEN;
                    2'b10: next_state = MATRIX_DIS;
                    2'b11: next_state = MATRIX_OP;
                    default: next_state = IDLE;
                endcase
            end
        end
        
        MATRIX_IN: begin
            // ����������ɺ��Զ��ص�IDLE
            if (matrix_in_wr_en) begin
                next_state = IDLE;
            end
            // ���߰��˳����ص�IDLE
            else if (key_flag && (mode != 2'b00)) begin
                next_state = IDLE;
            end
        end
        
        MATRIX_GEN: begin
            // ������ɺ�ص�IDLE
            if (gen_done) begin
                next_state = IDLE;
            end
            // ���߰��˳����ص�IDLE
            else if (key_flag && (mode != 2'b01)) begin
                next_state = IDLE;
            end
        end
        
        MATRIX_DIS: begin
            // չʾ��ɺ�ص�IDLE
            if (display_done) begin
                next_state = IDLE;
            end
            // ���߰��˳����ص�IDLE
            else if (key_flag && (mode != 2'b10)) begin
                next_state = IDLE;
            end
        end
        
        MATRIX_OP: begin
            // ����ģ������ź��ж�?
            // ���߰��˳����ص�IDLE
            if (key_flag && (mode != 2'b11)) begin
                next_state = IDLE;
            end
        end
        
        default: next_state = IDLE;
    endcase
end

endmodule
