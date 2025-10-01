module vec_mag_top #(
    parameter COORD_WIDTH = 8,
    parameter APB_ADDR_WIDTH = 12
) (
    // Global clocks and resets
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
    
    // AXI-Stream Slave Interface
    input  logic signed [4*COORD_WIDTH-1:0] s_axis_tdata,
    input  logic                            s_axis_tvalid,
    input  logic                            s_axis_tlast,
    output logic                            s_axis_tready,
    
    // AXI-Stream Master Interface
    output logic [4*COORD_WIDTH-1:0]        m_axis_tdata,
    output logic                            m_axis_tvalid,
    output logic                            m_axis_tlast,
    input  logic                            m_axis_tready
);

    // Internal signals
    logic                      core_reset;
    logic                      core_aclk_en;
    logic                      core_busy;
    logic [31:0]               core_data_processed_cnt;
    logic                      core_overflow_x;
    logic                      core_overflow_y;
    logic                      gated_clk;
    
    // Clock gating
    assign gated_clk = core_aclk_en ? clk : 1'b0;
    
    // Control module instance
    vec_mag_csr #(
        .COORD_WIDTH(COORD_WIDTH),
        .APB_ADDR_WIDTH(APB_ADDR_WIDTH)
    ) u_vec_mag_csr (
        .clk                        (clk),
        .rst_n                      (rst_n),
        .psel_i                     (psel_i),
        .penable_i                  (penable_i),
        .paddr_i                    (paddr_i),
        .pwrite_i                   (pwrite_i),
        .pwdata_i                   (pwdata_i),
        .prdata_o                   (prdata_o),
        .pready_o                   (pready_o),
        .pslverr_o                  (pslverr_o),
        .core_reset_o               (core_reset),
        .core_aclk_en_o             (core_aclk_en),
        .core_busy_i                (core_busy),
        .core_data_processed_cnt_i  (core_data_processed_cnt),
        .core_overflow_x_i          (core_overflow_x),
        .core_overflow_y_i          (core_overflow_y)
    );
    
    // Core module instance
    vec_mag_core #(
        .COORD_WIDTH(COORD_WIDTH)
    ) u_vec_mag_core (
        .aclk                       (gated_clk),
        .aresetn                    (rst_n),
        .s_axis_tdata               (s_axis_tdata),
        .s_axis_tvalid              (s_axis_tvalid),
        .s_axis_tlast               (s_axis_tlast),
        .s_axis_tready              (s_axis_tready),
        .m_axis_tdata               (m_axis_tdata),
        .m_axis_tvalid              (m_axis_tvalid),
        .m_axis_tlast               (m_axis_tlast),
        .m_axis_tready              (m_axis_tready),
        .core_reset_i               (core_reset),
        .core_bisy_o                (core_busy),
        .core_data_processed_cnt_o  (core_data_processed_cnt),
        .core_overflow_x_o          (core_overflow_x),
        .core_overflow_y_o          (core_overflow_y)
    );

endmodule : vec_mag_top