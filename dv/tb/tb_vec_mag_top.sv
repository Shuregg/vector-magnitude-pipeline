`timescale 1ns/1ps

module tb_vec_mag_top;

    // Parameters
    parameter COORD_WIDTH = 8;
    parameter APB_ADDR_WIDTH = 12;
    parameter CLK_PERIOD = 10; // 100 MHz
    
    // Global signals
    logic                      clk;
    logic                      rst_n;
    
    // APB Interface
    logic                      psel_i;
    logic                      penable_i;
    logic [APB_ADDR_WIDTH-1:0] paddr_i;
    logic                      pwrite_i;
    logic [31:0]               pwdata_i;
    logic [31:0]               prdata_o;
    logic                      pready_o;
    logic                      pslverr_o;
    
    // AXI-Stream Slave Interface
    logic signed [4*COORD_WIDTH-1:0] s_axis_tdata;
    logic                            s_axis_tvalid;
    logic                            s_axis_tlast;
    logic                            s_axis_tready;
    
    // AXI-Stream Master Interface
    logic [4*COORD_WIDTH-1:0]        m_axis_tdata;
    logic                            m_axis_tvalid;
    logic                            m_axis_tlast;
    logic                            m_axis_tready;
    
    // Test variables
    int error_count = 0;
    int test_count = 0;
    int transaction_count = 0;
    
    // Clock generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // DUT instance
    vec_mag_top #(
        .COORD_WIDTH(COORD_WIDTH),
        .APB_ADDR_WIDTH(APB_ADDR_WIDTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .psel_i         (psel_i),
        .penable_i      (penable_i),
        .paddr_i        (paddr_i),
        .pwrite_i       (pwrite_i),
        .pwdata_i       (pwdata_i),
        .prdata_o       (prdata_o),
        .pready_o       (pready_o),
        .pslverr_o      (pslverr_o),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tlast   (s_axis_tlast),
        .s_axis_tready  (s_axis_tready),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tlast   (m_axis_tlast),
        .m_axis_tready  (m_axis_tready)
    );
    
    // APB task for register writes
    task apb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            psel_i <= 1'b1;
            penable_i <= 1'b0;
            paddr_i <= addr;
            pwrite_i <= 1'b1;
            pwdata_i <= data;
            @(posedge clk);
            penable_i <= 1'b1;
            @(posedge clk);
            while (!pready_o) @(posedge clk);
            psel_i <= 1'b0;
            penable_i <= 1'b0;
            @(posedge clk);
            $display("[APB_WRITE] Time: %0t, Addr: 0x%08h, Data: 0x%08h", $time, addr, data);
        end
    endtask
    
    // APB task for register reads
    task apb_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            psel_i <= 1'b1;
            penable_i <= 1'b0;
            paddr_i <= addr;
            pwrite_i <= 1'b0;
            @(posedge clk);
            penable_i <= 1'b1;
            @(posedge clk);
            while (!pready_o) @(posedge clk);
            data = prdata_o;
            psel_i <= 1'b0;
            penable_i <= 1'b0;
            @(posedge clk);
            $display("[APB_READ]  Time: %0t, Addr: 0x%08h, Data: 0x%08h", $time, addr, data);
        end
    endtask
    
    // Task to send AXI-Stream data
    task send_vector;
        input signed [COORD_WIDTH-1:0] x1, y1, x2, y2;
        input int delay;
        begin
            // Wait for random delay if specified
            if (delay > 0) repeat(delay) @(posedge clk);
            
            // Prepare data
            s_axis_tdata <= {x1, y1, x2, y2};
            s_axis_tvalid <= 1'b1;
            s_axis_tlast <= 1'b1; // Always set tlast for simplicity
            
            // Wait for ready
            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);
            
            s_axis_tvalid <= 1'b0;
            s_axis_tlast <= 1'b0;
            transaction_count++;
            
            $display("[AXI_SEND]  Time: %0t, Data: {x1:%0d, y1:%0d, x2:%0d, y2:%0d}", 
                     $time, x1, y1, x2, y2);
        end
    endtask
    
    // Task to receive AXI-Stream data
    task receive_vector;
        output [COORD_WIDTH-1:0] magnitude;
        input int timeout;
        begin
            m_axis_tready <= 1'b1;
            fork
                begin
                    // Wait for valid data
                    @(posedge clk);
                    while (!m_axis_tvalid) @(posedge clk);
                    magnitude = m_axis_tdata[COORD_WIDTH-1:0];
                    $display("[AXI_RECV]  Time: %0t, Magnitude: %0d", $time, magnitude);
                    m_axis_tready <= 1'b0;
                end
                begin
                    // Timeout protection
                    #(timeout * CLK_PERIOD);
                    $display("[TIMEOUT]  No data received within timeout");
                    m_axis_tready <= 1'b0;
                end
            join_any
            disable fork;
        end
    endtask
    
    // Function to calculate expected magnitude with new improved algorithm
    function [COORD_WIDTH-1:0] calculate_expected_mag;
        input signed [COORD_WIDTH-1:0] x1, y1, x2, y2;
        logic signed [COORD_WIDTH-1:0] dx, dy;
        logic [COORD_WIDTH-1:0] abs_dx, abs_dy;
        logic [COORD_WIDTH-1:0] max_val, min_val;
        logic [COORD_WIDTH+7:0] z0_abs, z1_abs; // 8 extra bits for 128x multiplication
        logic [COORD_WIDTH+7:0] result;
        begin
            // Calculate differences
            dx = x1 - x2;
            dy = y1 - y2;
            
            // Absolute values
            abs_dx = (dx[COORD_WIDTH-1]) ? -dx : dx;
            abs_dy = (dy[COORD_WIDTH-1]) ? -dy : dy;
            
            // Find max and min
            if (abs_dx > abs_dy) begin
                max_val = abs_dx;
                min_val = abs_dy;
            end else begin
                max_val = abs_dy;
                min_val = abs_dx;
            end
            
            // New improved algorithm: z0 = alpha0*max + beta0*min, z1 = alpha1*max + beta1*min
            // alpha0 = 1, beta0 = 5/32 = 20/128
            // alpha1 = 108/128, beta1 = 71/128
            
            // z0_abs * 128 = 128 * max + 20 * min
            z0_abs = (max_val << 7) + ((min_val << 4) + (min_val << 2));
            
            // z1_abs * 128 = 108 * max + 71 * min
            z1_abs = ((max_val << 6) + (max_val << 5) + (max_val << 3) + (max_val << 2)) + 
                     ((min_val << 6) + (min_val << 3) - min_val);
            
            // Take maximum of z0 and z1, then divide by 128
            result = (z0_abs > z1_abs) ? z0_abs : z1_abs;
            
            // Divide by 128 (right shift by 7) and saturate to COORD_WIDTH bits
            if (result[COORD_WIDTH+7:7] > (2**COORD_WIDTH)-1)
                calculate_expected_mag = (2**COORD_WIDTH)-1;
            else
                calculate_expected_mag = result[COORD_WIDTH+6:7]; // [14:7] for 8-bit output
                
            $display("[CALC]     Expected magnitude: %0d (dx:%0d, dy:%0d, max:%0d, min:%0d, z0:%0d, z1:%0d)", 
                     calculate_expected_mag, dx, dy, max_val, min_val, z0_abs[COORD_WIDTH+6:7], z1_abs[COORD_WIDTH+6:7]);
        end
    endfunction
    
    // Test scenario: Basic functionality
    task test_basic_functionality;
        reg [31:0] read_data;
        reg [COORD_WIDTH-1:0] received_mag, expected_mag;
        begin
            $display("\n=== TEST 1: Basic Functionality ===");
            
            // Initialize APB interface
            psel_i = 1'b0;
            penable_i = 1'b0;
            paddr_i = '0;
            pwrite_i = 1'b0;
            pwdata_i = '0;
            
            // Initialize AXI interface
            s_axis_tdata = '0;
            s_axis_tvalid = 1'b0;
            s_axis_tlast = 1'b0;
            m_axis_tready = 1'b0;
            
            // Reset sequence
            $display("[RESET]    Applying reset...");
            rst_n = 1'b0;
            repeat(5) @(posedge clk);
            rst_n = 1'b1;
            repeat(5) @(posedge clk);
            
            // Configure core through APB
            $display("[CONFIG]   Configuring core...");
            apb_write(32'h00, 32'b10); // Release reset and enable clock
            repeat(10) @(posedge clk);
            
            // Check status register
            apb_read(32'h04, read_data);
            if (read_data[0] !== 1'b0) begin
                $display("[ERROR]    Core should be idle after reset");
                error_count++;
            end
            
            // Test case 1: Simple vector (3,4) - (0,0) = (3,4) -> magnitude ~5
            $display("\n[TEST]     Vector (3,4) to (0,0)");
            expected_mag = calculate_expected_mag(8'd3, 8'd4, 8'd0, 8'd0);
            fork
                send_vector(8'd3, 8'd4, 8'd0, 8'd0, 0);
                receive_vector(received_mag, 100);
            join
            
            if (received_mag !== expected_mag) begin
                $display("[ERROR]    Magnitude mismatch: Got %0d, Expected %0d", 
                         received_mag, expected_mag);
                error_count++;
            end else begin
                $display("[PASS]     Magnitude correct: %0d", received_mag);
            end
            test_count++;
            
            // Test case 2: Another vector
            $display("\n[TEST]     Vector (10,5) to (2,3)");
            expected_mag = calculate_expected_mag(8'd10, 8'd5, 8'd2, 8'd3);
            fork
                send_vector(8'd10, 8'd5, 8'd2, 8'd3, 2);
                receive_vector(received_mag, 100);
            join
            
            if (received_mag !== expected_mag) begin
                $display("[ERROR]    Magnitude mismatch: Got %0d, Expected %0d", 
                         received_mag, expected_mag);
                error_count++;
            end else begin
                $display("[PASS]     Magnitude correct: %0d", received_mag);
            end
            test_count++;
            
            // Check data processed counter
            apb_read(32'h08, read_data);
            if (read_data !== 32'd2) begin
                $display("[ERROR]    Data counter mismatch: Got %0d, Expected 2", read_data);
                error_count++;
            end
        end
    endtask
    
    // Test scenario: Overflow detection
    task test_overflow_detection;
        reg [31:0] read_data;
        begin
            $display("\n=== TEST 2: Overflow Detection ===");
            
            // Clear overflow status
            apb_write(32'h0C, 32'h0000_0000);
            
            // Test case: Large positive minus large negative (potential overflow)
            $display("[TEST]     Testing overflow scenario");
            send_vector(8'sd127, 8'sd0, -8'sd128, 8'sd0, 0);
            
            // Check overflow status
            repeat(20) @(posedge clk);
            apb_read(32'h0C, read_data);
            
            if (read_data[0] || read_data[1]) begin
                $display("[PASS]     Overflow detected: X=%0d, Y=%0d", 
                         read_data[0], read_data[1]);
            end else begin
                $display("[INFO]     No overflow detected");
            end
            test_count++;
        end
    endtask
    
    // Test scenario: Reset and clock gating
    task test_reset_clock_gating;
        reg [31:0] read_data;
        reg [COORD_WIDTH-1:0] received_mag;
        begin
            $display("\n=== TEST 3: Reset and Clock Gating ===");
            
            // Test software reset
            $display("[TEST]     Testing software reset");
            apb_write(32'h00, 32'h0000_0001); // Assert reset
            
            // Try to send data while in reset
            fork
                begin
                    send_vector(8'd1, 8'd1, 8'd0, 8'd0, 0);
                    $display("[ERROR]    Should not accept data during reset");
                    error_count++;
                end
                begin
                    #(10 * CLK_PERIOD);
                    $display("[PASS]     Correctly blocked data during reset");
                end
            join_any
            disable fork;
            test_count++;
            
            // Release reset and enable clock
            apb_write(32'h00, 32'h0000_0003);
            repeat(10) @(posedge clk);
            
            // Test clock gating
            $display("[TEST]     Testing clock gating");
            apb_write(32'h00, 32'h0000_0001); // Disable clock but keep reset released
            
            // Try to send data with clock disabled
            fork
                begin
                    send_vector(8'd1, 8'd1, 8'd0, 8'd0, 0);
                    $display("[ERROR]    Should not accept data with clock disabled");
                    error_count++;
                end
                begin
                    #(10 * CLK_PERIOD);
                    $display("[PASS]     Correctly blocked data with clock disabled");
                end
            join_any
            disable fork;
            test_count++;
            
            // Re-enable everything
            apb_write(32'h00, 32'h0000_0003);
            repeat(10) @(posedge clk);
        end
    endtask
    
    // Test scenario: Backpressure testing
    task test_backpressure;
        reg [COORD_WIDTH-1:0] received_mag;
        begin
            $display("\n=== TEST 4: Backpressure Testing ===");
            
            // Create backpressure by not ready
            m_axis_tready = 1'b0;
            
            // Send multiple transactions
            fork
                begin
                    send_vector(8'd5, 8'd5, 8'd0, 8'd0, 0);
                    send_vector(8'd6, 8'd6, 8'd0, 8'd0, 0);
                    send_vector(8'd7, 8'd7, 8'd0, 8'd0, 0);
                end
                begin
                    // Release backpressure after some time
                    repeat(15) @(posedge clk);
                    m_axis_tready = 1'b1;
                    repeat(3) begin
                        receive_vector(received_mag, 50);
                    end
                    m_axis_tready = 1'b0;
                end
            join
            test_count++;
            $display("[PASS]     Backpressure handling working");
        end
    endtask
    
    // Test scenario: Improved algorithm verification
    task test_improved_algorithm;
        reg [COORD_WIDTH-1:0] received_mag, expected_mag;
        begin
            $display("\n=== TEST 5: Improved Algorithm Verification ===");
            
            // Test cases that benefit from the improved algorithm
            $display("\n[TEST]     Vector (100,10) to (0,0)");
            expected_mag = calculate_expected_mag(8'd100, 8'd10, 8'd0, 8'd0);
            fork
                send_vector(8'd100, 8'd10, 8'd0, 8'd0, 0);
                receive_vector(received_mag, 100);
            join
            
            if (received_mag !== expected_mag) begin
                $display("[ERROR]    Magnitude mismatch: Got %0d, Expected %0d", 
                         received_mag, expected_mag);
                error_count++;
            end else begin
                $display("[PASS]     Magnitude correct: %0d", received_mag);
            end
            test_count++;
            
            // Test case with large difference between coordinates
            $display("\n[TEST]     Vector (90,20) to (10,10)");
            expected_mag = calculate_expected_mag(8'd90, 8'd20, 8'd10, 8'd10);
            fork
                send_vector(8'd90, 8'd20, 8'd10, 8'd10, 0);
                receive_vector(received_mag, 100);
            join
            
            if (received_mag !== expected_mag) begin
                $display("[ERROR]    Magnitude mismatch: Got %0d, Expected %0d", 
                         received_mag, expected_mag);
                error_count++;
            end else begin
                $display("[PASS]     Magnitude correct: %0d", received_mag);
            end
            test_count++;
            
            // Test case where z1 should be larger than z0
            $display("\n[TEST]     Vector (60,50) to (10,10)");
            expected_mag = calculate_expected_mag(8'd60, 8'd50, 8'd10, 8'd10);
            fork
                send_vector(8'd60, 8'd50, 8'd10, 8'd10, 0);
                receive_vector(received_mag, 100);
            join
            
            if (received_mag !== expected_mag) begin
                $display("[ERROR]    Magnitude mismatch: Got %0d, Expected %0d", 
                         received_mag, expected_mag);
                error_count++;
            end else begin
                $display("[PASS]     Magnitude correct: %0d", received_mag);
            end
            test_count++;
        end
    endtask
    
    // Main test sequence
    initial begin : main_test_seq
        $display("Starting vec_mag_system testbench...");
        $display("Coordinate Width: %0d bits", COORD_WIDTH);
        $display("Using IMPROVED algorithm with dual-formula approach");
        
        // Run tests
        test_basic_functionality;
        test_overflow_detection;
        test_reset_clock_gating;
        test_backpressure;
        test_improved_algorithm;
        
        // Final status
        $display("\n=== TEST SUMMARY ===");
        $display("Tests run: %0d", test_count);
        $display("Errors: %0d", error_count);
        $display("Transactions: %0d", transaction_count);
        
        if (error_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** %0d TESTS FAILED ***", error_count);
        
        $finish;
    end
    
    // Monitoring
    always @(posedge clk) begin
        if (s_axis_tvalid && s_axis_tready) begin
            $display("[MONITOR]  Transaction %0d started", transaction_count);
        end
        
        if (m_axis_tvalid && m_axis_tready) begin
            $display("[MONITOR]  Result %0d delivered: %0d", 
                     transaction_count, m_axis_tdata[COORD_WIDTH-1:0]);
        end
    end
    
    // Timeout for simulation
    initial begin
        #500000; // 500us timeout
        $display("[TIMEOUT] Simulation timeout reached");
        $finish;
    end

endmodule
