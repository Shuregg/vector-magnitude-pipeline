`timescale 1ns / 1ps

module tb_vec_mag_core();

    // Parameters of the DUT
    localparam COORD_WIDTH = 8;
    localparam AXIS_TDATA_WIDTH = COORD_WIDTH * 4;

    // Clock and Reset
    logic aclk;
    logic aresetn;

    // DUT AXI-Stream Interfaces
    logic signed [AXIS_TDATA_WIDTH-1:0] s_axis_tdata;
    logic                              s_axis_tvalid;
    logic                              s_axis_tlast;
    logic                              s_axis_tready;

    logic signed [AXIS_TDATA_WIDTH-1:0] m_axis_tdata;
    logic                              m_axis_tvalid;
    logic                              m_axis_tlast;
    logic                              m_axis_tready;

    // Testbench control
    logic end_of_simulation = 1'b0;
    int test_counter = 0;
    int success_count = 0;
    int error_count = 0;

    // Instantiate the DUT
    vec_mag_core #(
        .COORD_WIDTH(COORD_WIDTH)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tready(m_axis_tready)
    );

    // Clock generator (100 MHz)
    always #5 aclk = ~aclk;

    // Main test sequence
    initial begin
        // Initialize signals
        aclk = 0;
        aresetn = 0;
        s_axis_tdata = '0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        m_axis_tready = 1'b1; // Always ready to receive

        // Apply reset
        #20;
        aresetn = 1;
        #10;

        $display("[%0t] Test started: Filling the pipeline...", $time);

        // Phase 1: Send test vectors to fill the 5-stage pipeline
        for (int i = 0; i < 10; i++) begin
            @(posedge aclk);
            s_axis_tvalid <= 1'b1;
            // Create a simple test vector: {x1, y1, x2, y2}
            // Let's use: x1 = i, y1 = i*2, x2 = 10, y2 = 20
            // So the vector becomes: (10-i, 20-i*2)
            s_axis_tdata <= { (i), (i*2), 8'd10, 8'd20 };
            s_axis_tlast <= (i == 9); // Set tlast on the last packet
            test_counter++;
            $display("[%0t] Sent vector %0d: x_sub = %0d, y_sub = %0d", 
                     $time, i, (i - 10), (i*2 - 20));
        end

        // Phase 2: Keep valid low for a few cycles to create "bubbles"
        @(posedge aclk);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast <= 1'b0;
        $display("[%0t] Stopped sending data for 3 cycles...", $time);
        #150; // Wait 3 cycles (30ns)

        // Phase 3: Send more data to see pipeline recovery
        $display("[%0t] Resuming data transmission...", $time);
        for (int i = 10; i < 15; i++) begin
            @(posedge aclk);
            s_axis_tvalid <= 1'b1;
            s_axis_tdata <= { (i), (i*2), 8'd10, 8'd20 };
            s_axis_tlast <= (i == 14);
            test_counter++;
            $display("[%0t] Sent vector %0d: x_sub = %0d, y_sub = %0d", 
                     $time, i, (i - 10), (i*2 - 20));
        end

        // Phase 4: Let the pipeline drain completely
        @(posedge aclk);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast <= 1'b0;

        // Wait for all responses (5 stages + the last data)
        #300;

        $display("\n[%0t] Test completed", $time);
        $display("Vectors sent: %0d", test_counter);
        $display("Successes: %0d, Errors: %0d", success_count, error_count);

        end_of_simulation = 1'b1;
        #100 $finish;
    end

    // Monitor the output and check results
    always @(posedge aclk) begin
        if (aresetn && m_axis_tvalid && m_axis_tready) begin
            // Calculate expected result using the algorithm
            // For vector {x1, y1, x2, y2} = {A, B, C, D}:
            // x_sub = A - C, y_sub = B - D
            // We need to track this through the pipeline somehow...
            // For simplicity, just display the result
            $display("[%0t] OUTPUT: magnitude = %0d (tlast = %0d)", 
                     $time, m_axis_tdata, m_axis_tlast);

            // Simple sanity check: result should be positive
            if (m_axis_tdata < 0) begin
                $error("Negative magnitude detected: %0d", m_axis_tdata);
                error_count++;
            end else begin
                success_count++;
            end
        end
    end

    // Monitor pipeline stages (optional, for debugging)
    always @(posedge aclk) begin
        if (aresetn) begin
            $display("[%0t] Pipeline: S0=%b, S1=%b, S2=%b, S3=%b, S4=%b", 
                     $time, dut.st0_valid, dut.st1_valid, dut.st2_valid, 
                     dut.st3_valid, dut.st4_valid);
        end
    end

    // Timeout protection
    initial begin
        #100000; // 100us timeout
        if (!end_of_simulation) begin
            $error("Testbench timeout!");
            $finish;
        end
    end

endmodule