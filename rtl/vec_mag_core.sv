module vec_mag_core #(
	COORD_WIDTH=8
) (
	input  logic aclk,
	input  logic aresetn,

	// AXI-Stream Slave Interface
	input  logic signed [4*COORD_WIDTH-1:0]	s_axis_tdata,	// tdata == {x1, y1, x2, y2}
	input  logic								s_axis_tvalid,
	input  logic								s_axis_tlast,
	output logic								s_axis_tready,

	// AXI-Stream Master Interface
	output logic [4*COORD_WIDTH-1:0]			m_axis_tdata,
	output logic								m_axis_tvalid,
	output logic								m_axis_tlast,
	input  logic								m_axis_tready,

	// Control Signals
	input  logic								core_reset_i,
	// input  logic								core_mode_i,

	// Status signals
	output logic								core_bisy_o,
	output logic		[31:0]					core_data_processed_cnt_o,
	output logic								core_overflow_x_o,
	output logic								core_overflow_y_o
);

	// Local parameters
	localparam AXIS_TDATA_WIDTH = COORD_WIDTH * 4;
	localparam COEFF_BASE = 128;
	localparam COEFF_BASE_CLOG2 = $clog2(COEFF_BASE);

	localparam ALPHA0_MUL_128 = 1 * COEFF_BASE;			// alpha0 = 1; alpha0 * 128 = 128.
	localparam BETA0_MUL_128 = 5/32 * COEFF_BASE;		// beta0 = 5/32 = 20/128; beta * 128 = 20.
	localparam ALPHA1_MUL_128 = 108/128 * COEFF_BASE;	// alpha1 = 108/128; alpha1 * 128 = 108.
	localparam BETA1_MUL_128 = 71/128 * COEFF_BASE;		// beta1 = 71/128; beta1 * 128 = 71.

	// Control and Status signals
	logic resetn_combined;
	logic x1_sign;
	logic x2_sign;
	logic y1_sign;
	logic y2_sign;
 	logic x_sub_sign;
	logic y_sub_sign;
	logic [ 4:0] busy_shift_reg;
	logic [31:0] data_processed_cnt;

	assign resetn_combined = aresetn && (~core_reset_i);

	assign core_overflow_x_o = (x1_sign ^ x2_sign) && (x1_sign ^ x_sub_sign);
	assign core_overflow_y_o = (y1_sign ^ y2_sign) && (y1_sign ^ y_sub_sign);

	assign core_data_processed_cnt_o = data_processed_cnt;

	// Busy logic
	always_ff @(posedge aclk) begin : busy_shift_reg_logic
    	if (!resetn_combined) begin
			busy_shift_reg <= 5'b0;
    	end else begin
			busy_shift_reg <= {busy_shift_reg[3:0], s_axis_tvalid && s_axis_tready};
		end
	end
	assign core_bisy_o = (busy_shift_reg != 5'b0);

	// Stage 1 registers
	logic signed [COORD_WIDTH-1:0]	st1_x_sub;
	logic signed [COORD_WIDTH-1:0]	st1_y_sub;
	logic							st1_valid;

	// Stage 2 registers
	logic [COORD_WIDTH-1:0]	st2_x_abs;
	logic [COORD_WIDTH-1:0]	st2_y_abs;
	logic					st2_valid;

	// Stage 3 registers
	logic [COORD_WIDTH-1:0] st3_max;
	logic [COORD_WIDTH-1:0] st3_min;
	logic					st3_valid;

	// Stage 4 registers
	logic [COORD_WIDTH+COEFF_BASE_CLOG2-1:0] st4_z0_abs;
	logic [COORD_WIDTH+COEFF_BASE_CLOG2-1:0] st4_z1_abs;
	logic						 			 st4_valid;

	// Stage 5 registers
	logic [COORD_WIDTH+COEFF_BASE_CLOG2-1:0] st5_max;
	logic						 			 st5_valid;

	// Simple tready implementation
	assign s_axis_tready = !s_axis_tvalid || m_axis_tready;

	// Assigning output signals & buses
	// True result = st5_max / 128
	assign m_axis_tdata	 = st5_max[COORD_WIDTH+COEFF_BASE_CLOG2-1:COEFF_BASE_CLOG2];
	assign m_axis_tvalid = st5_valid;
	assign m_axis_tlast	 = 1'b1;

	// -------------------------------------------------------------------------
	// -- Stage 1: Converting 2 points to a single point (radius-vector)
	// -------------------------------------------------------------------------
	// x = (x1 - x2); y = (y1 - y2)
	always_ff @(posedge aclk) begin : stage_1
		if(!resetn_combined) begin
			st1_x_sub <= 0;
			st1_y_sub <= 0;
			st1_valid <= 1'b0;
		end else begin
			if(!s_axis_tvalid) begin
				st1_x_sub <= 0;
				st1_y_sub <= 0;
				st1_valid <= 1'b0;
	 			x1_sign <= 0;
	 			x2_sign <= 0;
	 			y1_sign <= 0;
	 			y2_sign <= 0;
				x_sub_sign <= 0;
				y_sub_sign <= 0;
			end
			else if(s_axis_tready) begin
				`ifndef DEVELOPER_WIP 
					st1_x_sub <= $signed(s_axis_tdata[(4*COORD_WIDTH-1):(3*COORD_WIDTH)]) - $signed(s_axis_tdata[(2*COORD_WIDTH-1):(1*COORD_WIDTH)]);
					st1_y_sub <= $signed(s_axis_tdata[(3*COORD_WIDTH-1):(2*COORD_WIDTH)]) - $signed(s_axis_tdata[(1*COORD_WIDTH-1):(0*COORD_WIDTH)]);
					st1_valid <= s_axis_tvalid;

	 				x1_sign <= s_axis_tdata[4*COORD_WIDTH-1];
	 				x2_sign <= s_axis_tdata[2*COORD_WIDTH-1];
	 				y1_sign <= s_axis_tdata[3*COORD_WIDTH-1];
	 				y2_sign <= s_axis_tdata[1*COORD_WIDTH-1];
					x_sub_sign <= st1_x_sub[COORD_WIDTH-1];
					y_sub_sign <= st1_y_sub[COORD_WIDTH-1];
				`else
					// TODO 0 - handle vector with 2 points (p1 = {x1, y1}; p2 = {x2, y2}); 1 - handle a radius-vector (with p1 = {0, 0}) 
					case(core_mode_i)	
						0: begin
							st1_x_sub <= s_axis_tdata[(4*COORD_WIDTH-1):(3*COORD_WIDTH)] - s_axis_tdata[(2*COORD_WIDTH-1):(1*COORD_WIDTH)];
							st1_y_sub <= s_axis_tdata[(3*COORD_WIDTH-1):(2*COORD_WIDTH)] - s_axis_tdata[(1*COORD_WIDTH-1):(0*COORD_WIDTH)];
							st1_valid <= s_axis_tvalid;
						end
						1: begin
							st1_x_sub <= 
						end
					endcase
				`endif
			end
		end
	end

	// -------------------------------------------------------------------------
	// -- Stage 2: Calculation absolute value of subtraction (x = |x|; y = |y|)
	// -------------------------------------------------------------------------
	always_ff @(posedge aclk) begin : stage_2
		if(!resetn_combined) begin
			st2_x_abs <= 0;
			st2_y_abs <= 0;
			st2_valid <= 1'b0;
		end else begin
			if(st1_valid) begin
				st2_x_abs <= st1_x_sub[COORD_WIDTH-1] ? -st1_x_sub : st1_x_sub;
				st2_y_abs <= st1_y_sub[COORD_WIDTH-1] ? -st1_y_sub : st1_y_sub;
			end
			st2_valid <= st1_valid;
		end
	end

	// -------------------------------------------------------------------------
	// -- Stage 3: Finding 'max' and 'min'
	// -------------------------------------------------------------------------
	always_ff @(posedge aclk) begin : stage_3
		if(!resetn_combined) begin
			st3_max	  <= 0;
			st3_min	  <= 0;
			st3_valid <= 1'b0;
		end else begin
			if(st2_valid) begin
				if(st2_x_abs > st2_y_abs) begin
					st3_max <= st2_x_abs;
					st3_min <= st2_y_abs;
				end else begin
					st3_max <= st2_y_abs;
					st3_min <= st2_x_abs;
				end
			end
			st3_valid <= st2_valid;
		end
	end

	// -------------------------------------------------------------------------
	// -- Stage 4: Calculation of |z0| and |z1|.
	// -------------------------------------------------------------------------
	// |z0| = alpha0 * max + beta0 * min;
	// |z1| = alpha1 * max + beta1 * min.

	always_ff @(posedge aclk) begin : stage_4
		if(!resetn_combined) begin
			st4_z0_abs	<= 0;
			st4_z1_abs	<= 0;
			st4_valid	<= 0;
		end else begin
			if(st3_valid) begin
				// |z0| * 128 = 128 * max + 20 * min = 128 * max + (16 + 4) * min
				st4_z0_abs <= (st3_max << COEFF_BASE_CLOG2) + ((st3_min << 4) + (st3_min << 2));

				// |z1| * 128 = 108 * max + 71 * min = (64 + 32 + 8 + 4) * max + (64 + 8 - 1) * min
				st4_z1_abs <= ((st3_max << 6) + (st3_max << 5) + (st3_max << 3) + (st3_max << 2)) + ((st3_min << 6) + (st3_min << 3) - 1);
			end
			st4_valid	<= st3_valid;
		end
	end

	// -------------------------------------------------------------------------
	// -- Stage 5: Find max of |z0| and |z1|.
	// -------------------------------------------------------------------------
	always_ff @(posedge aclk) begin : stage_5
		if(!resetn_combined) begin
			st5_max	  <= 0;
			st5_valid <= 1'b0;
			data_processed_cnt <= 32'b0;
		end else begin
			if(st4_valid) begin
				st5_max <= (st4_z0_abs > st4_z1_abs) ? st4_z0_abs : st4_z1_abs;
				data_processed_cnt++;
			end
			st5_valid <= st4_valid;
		end
	end

endmodule : vec_mag_core
