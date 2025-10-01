module vec_mag_csr #(
    parameter COORD_WIDTH = 8,
    parameter APB_ADDR_WIDTH = 12
) (
    // Clock and Reset
    input  logic                      clk,
    input  logic                      rst_n,
    
    // APB Interface
    input  logic                      psel_i,
    input  logic                      penable_i,
    input  logic [APB_ADDR_WIDTH-1:0] paddr_i,
    input  logic                      pwrite_i,
    input  logic [31:0]               pwdata_i,
    output logic [31:0]               prdata_o,
    output logic                      pready_o,
    output logic                      pslverr_o,
    
    // Control signals to vec_mag_core
    output logic                      core_reset_o,
    output logic                      core_aclk_en_o,
    
    // Status signals from vec_mag_core
    input  logic                      core_busy_i,
    input  logic [31:0]               core_data_processed_cnt_i,
    input  logic                      core_overflow_x_i,
    input  logic                      core_overflow_y_i
);

    // Register addresses
    localparam REG_CTRL       = 8'h00;
    localparam REG_STATUS     = 8'h04;
    localparam REG_DATA_COUNT = 8'h08;
    localparam REG_OVERFLOW   = 8'h0C;
    
    // Internal registers
    logic [31:0] control_reg;
    logic [31:0] status_reg;
    logic [31:0] data_count_reg;
    logic [31:0] overflow_reg;
    logic [31:0] prdata_reg;
    
    // Control register bits
    localparam CTRL_RESET_BIT = 0;
    localparam CTRL_CLK_EN_BIT = 1;
    
    // Status register bits
    localparam STATUS_BUSY_BIT = 0;
    
    // Overflow register bits
    localparam OVERFLOW_X_BIT = 0;
    localparam OVERFLOW_Y_BIT = 1;
    
    // APB transaction handling
    logic apb_write;
    logic apb_read;
    logic [7:0] reg_addr;
    
    assign apb_write = psel_i && penable_i && pwrite_i;
    assign apb_read = psel_i && penable_i && !pwrite_i;
    assign reg_addr = paddr_i[7:0];
    
    // Control register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            control_reg <= 32'h0000_0001; // Reset active by default
        end else if (apb_write && (reg_addr == REG_CTRL)) begin
            control_reg <= pwdata_i;
        end
    end
    
    // Status register - read-only from core status
    assign status_reg = {31'b0, core_busy_i};
    
    // Data count register - read-only from core
    assign data_count_reg = core_data_processed_cnt_i;
    
    // Overflow register - sticky bits for overflow detection
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            overflow_reg <= 32'h0;
        end else begin
            // Set overflow bits when detected (sticky)
            if (core_overflow_x_i) 
                overflow_reg[OVERFLOW_X_BIT] <= 1'b1;
            if (core_overflow_y_i)
                overflow_reg[OVERFLOW_Y_BIT] <= 1'b1;
            
            // Clear overflow bits when written with 0
            if (apb_write && (reg_addr == REG_OVERFLOW)) begin
                if (!pwdata_i[OVERFLOW_X_BIT])
                    overflow_reg[OVERFLOW_X_BIT] <= 1'b0;
                if (!pwdata_i[OVERFLOW_Y_BIT])
                    overflow_reg[OVERFLOW_Y_BIT] <= 1'b0;
            end
        end
    end
    
    // APB read data register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prdata_reg <= 32'h0;
        end else if (apb_read) begin
            case (reg_addr)
                REG_CTRL:       prdata_reg <= control_reg;
                REG_STATUS:     prdata_reg <= status_reg;
                REG_DATA_COUNT: prdata_reg <= data_count_reg;
                REG_OVERFLOW:   prdata_reg <= overflow_reg;
                default:        prdata_reg <= 32'h0;
            endcase
        end
    end
    
    assign prdata_o = prdata_reg;
    
    // APB control signals
    assign pready_o = 1'b1;  // Always ready
    assign pslverr_o = 1'b0; // No slave errors
    
    // Core control outputs
    assign core_reset_o = control_reg[CTRL_RESET_BIT];
    assign core_aclk_en_o = control_reg[CTRL_CLK_EN_BIT];

endmodule : vec_mag_csr