// ========================================================================
// File: defines.v
// Description: Project-wide constants and definitions
// ========================================================================

`ifndef DEFINES_V
`define DEFINES_V

// --- System Parameters ---
`define MAX_DIM       3'd5      // Max matrix dimension is 5x5 (m, n <= 5)
`define DATA_WIDTH    4         // Matrix element value 0-9 requires 4 bits
`define ADDR_WIDTH    6         // Max elements 5*5 = 25. 6 bits (0-63) is enough.

// --- Operation Type Selection Codes (funSel[2:0]) ---
`define OP_TRANSPOSE  3'b000    // 矩阵转置 (T)
`define OP_ADD        3'b001    // 矩阵加法 (A)
`define OP_SCALARMUL  3'b010    // 标量乘法 (B)
`define OP_MATMUL     3'b011    // 矩阵乘法 (C)
`define OP_CONV       3'b100    // 卷积 (J) - Bonus

`endif // DEFINES_V
