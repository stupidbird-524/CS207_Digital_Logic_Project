`include "defines.v"

// Simplified and simulation-friendly functions_module
module functions_module (
    input                         clk,
    input                         reset,
    input       [2:0]             funSel,
    input                         funEn,
    input       [4-1:0] scalar_val,

    output reg                    opDone,
    output reg                    unableToOperate,

    input       [4-1:0] A_m, A_n,
    input       [4-1:0] B_m, B_n,

    output reg                    mem_read_en,
    output reg                    mem_write_en,
    output reg [6-1:0]  mem_addr,
    input       [4-1:0] mem_data_in,
    output reg [4-1:0]  mem_data_out
);

    // FSM states
    localparam IDLE      = 4'd0;
    localparam CHECK_DIM = 4'd1;
    localparam INIT      = 4'd2;
    localparam READ_A    = 4'd3;
    localparam READ_B    = 4'd4;
    localparam CALC      = 4'd5;
    localparam WRITE     = 4'd6;
    localparam NEXT_IDX  = 4'd7;
    localparam DONE      = 4'd8;

    reg [3:0] state, next_state;

    // internal registers
    reg [4-1:0] A_data_reg;
    reg [4-1:0] B_data_reg;
    // accumulator width: allow sums of multiple products (safely up to 12 bits)
    localparam ACC_WIDTH = 12;
    reg [ACC_WIDTH-1:0] acc_reg;

    // counters (dimensions max 5 so 3 bits is enough)
    reg [2:0] i_idx, j_idx, k_idx;
    reg [4-1:0] C_m, C_p; // result dimensions

    // Address base
    localparam [`ADDR_WIDTH-1:0] ADDR_BASE_A = `ADDR_WIDTH'd0;
    localparam [`ADDR_WIDTH-1:0] ADDR_BASE_B = `ADDR_WIDTH'd32;
    localparam [`ADDR_WIDTH-1:0] ADDR_BASE_C = `ADDR_WIDTH'd64;

    // helper wires for address calculation (use integers for arithmetic)
    wire [6-1:0] addr_A;
    wire [6-1:0] addr_B;
    wire [6-1:0] addr_C;

    assign addr_A = ADDR_BASE_A + ( (funSel == 3'b011) ? (i_idx * A_n + k_idx) : (i_idx * A_n + j_idx) );
    assign addr_B = ADDR_BASE_B + ( (funSel == 3'b011) ? (k_idx * B_n + j_idx) : (i_idx * B_n + j_idx) );
    assign addr_C = ADDR_BASE_C + (i_idx * C_p + j_idx);

    // Next-state / control logic
    always @(*) begin
        // defaults
        next_state = state;
        mem_read_en = 1'b0;
        mem_write_en = 1'b0;
        mem_addr = {`ADDR_WIDTH{1'b0}};
        mem_data_out = {`DATA_WIDTH{1'b0}};
        opDone = 1'b0;
        unableToOperate = 1'b0;

        case (state)
            IDLE: begin
                if (funEn) next_state = CHECK_DIM;
            end

            CHECK_DIM: begin
                case (funSel)
                    `OP_TRANSPOSE: begin
                        if (A_m == 0 || A_n == 0) unableToOperate = 1'b1;
                        C_m = A_n; C_p = A_m;
                    end
                    `OP_ADD: begin
                        if (A_m != B_m || A_n != B_n) unableToOperate = 1'b1;
                        C_m = A_m; C_p = A_n;
                    end
                    `OP_SCALARMUL: begin
                        if (A_m == 0 || A_n == 0) unableToOperate = 1'b1;
                        C_m = A_m; C_p = A_n;
                    end
                    `OP_MATMUL: begin
                        if (A_n != B_m || A_m == 0 || B_n == 0) unableToOperate = 1'b1;
                        C_m = A_m; C_p = B_n;
                    end
                    default: begin
                        unableToOperate = 1'b1;
                        C_m = 0; C_p = 0;
                    end
                endcase

                if (unableToOperate) next_state = DONE;
                else next_state = INIT;
            end

            INIT: begin
                // initialize counters
                next_state = READ_A;
            end

            READ_A: begin
                mem_read_en = 1'b1;
                mem_addr = addr_A;
                // if op needs B, go read B; else go calculate
                if (funSel == `OP_ADD || funSel == `OP_MATMUL) next_state = READ_B;
                else next_state = CALC;
            end

            READ_B: begin
                mem_read_en = 1'b1;
                mem_addr = addr_B;
                next_state = CALC;
            end

            CALC: begin
                if (funSel == `OP_TRANSPOSE) begin
                    mem_data_out = A_data_reg;
                    mem_write_en = 1'b1;
                    mem_addr = ADDR_BASE_C + (j_idx * C_p + i_idx); // C[j][i] = A[i][j]
                    next_state = NEXT_IDX;
                end else if (funSel == `OP_ADD) begin
                    mem_data_out = A_data_reg + B_data_reg;
                    mem_write_en = 1'b1;
                    mem_addr = addr_C;
                    next_state = NEXT_IDX;
                end else if (funSel == `OP_SCALARMUL) begin
                    mem_data_out = A_data_reg * scalar_val;
                    mem_write_en = 1'b1;
                    mem_addr = addr_C;
                    next_state = NEXT_IDX;
                end else if (funSel == `OP_MATMUL) begin
                    // accumulate product
                    // This cycle we assume A_data_reg and B_data_reg hold the operands
                    // Update acc_reg and if last k then write
                    // mem_write occurs in WRITE state
                    next_state = WRITE; // use WRITE to perform accumulation & possible write
                end else begin
                    next_state = DONE;
                end
            end

            WRITE: begin
                if (funSel == `OP_MATMUL) begin
                    // Accumulate the product for current k
                    // (actual acc update happens in sequential block)
                    if (k_idx + 1 >= A_n) begin
                        // last k, write result
                        mem_write_en = 1'b1;
                        mem_addr = addr_C;
                        mem_data_out = acc_reg[`DATA_WIDTH-1:0];
                        next_state = NEXT_IDX;
                    end else begin
                        // advance inner loop
                        next_state = READ_A;
                    end
                end else begin
                    next_state = NEXT_IDX;
                end
            end

            NEXT_IDX: begin
                // update indices in sequential block; check for completion here
                // For combinational decision, assume sequential will update counters
                // We'll check termination by looking at i_idx and j_idx after update (in sequential)
                if ( (i_idx == C_m - 1) && (j_idx == C_p - 1) ) begin
                    next_state = DONE;
                end else begin
                    next_state = READ_A;
                end
            end

            DONE: begin
                opDone = 1'b1;
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // Sequential updates: registers, reads, writes, counters and accumulator
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            i_idx <= 0; j_idx <= 0; k_idx <= 0;
            A_data_reg <= 0; B_data_reg <= 0; acc_reg <= 0;
            C_m <= 0; C_p <= 0;
            mem_addr <= 0; mem_read_en <= 0; mem_write_en <= 0;
            mem_data_out <= 0; opDone <= 0; unableToOperate <= 0;
        end else begin
            state <= next_state;
            // capture memory read data when a read was requested
            if ((state == READ_A) && mem_read_en) begin
                A_data_reg <= mem_data_in;
            end
            if ((state == READ_B) && mem_read_en) begin
                B_data_reg <= mem_data_in;
            end

            // Accumulate for MatMul: when transitioning from READ_B->CALC/WRITE
            if (state == CALC && funSel == `OP_MATMUL) begin
                // on CALC, A_data_reg and B_data_reg hold current product operands
                acc_reg <= (k_idx == 0) ? (A_data_reg * B_data_reg) : (acc_reg + (A_data_reg * B_data_reg));
            end

            // If in WRITE for matmul and it's last k, the write value is prepared from acc_reg
            if (state == WRITE && funSel == `OP_MATMUL) begin
                // If it's the last k, mem write happens via combinational signals; nothing extra here
            end

            // Update indices when entering NEXT_IDX
            if (state == NEXT_IDX) begin
                // increment j first, then i
                if (j_idx + 1 >= C_p) begin
                    j_idx <= 0;
                    i_idx <= i_idx + 1;
                end else begin
                    j_idx <= j_idx + 1;
                end
                // reset inner loop k for matmul
                k_idx <= 0;
                // reset accumulator for next element
                acc_reg <= 0;
            end

            // Advance inner k when returning to READ_A for matmul after a product
            if ((state == WRITE) && (funSel == `OP_MATMUL)) begin
                if (k_idx + 1 < A_n) begin
                    k_idx <= k_idx + 1;
                end else begin
                    k_idx <= 0;
                end
            end
        end
    end

endmodule