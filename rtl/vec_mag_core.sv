localparam AXIS_TDATA_WIDTH = COORD_WIDTH * 4;
localparam COEFF_BASE = 32;
localparam COEFF_BASE_CLOG2 = $clog2(COEFF_BASE);

localparam ALPHA_MUL_32 = 1 * COEFF_BASE;	// alpha = 1; alpha*32 = 32.
localparam BETA_MUL_32 = 5/32 * COEFF_BASE;	// beta = 5/32; beta*32 = 5.

module vec_mag_core #(
	COORD_WIDTH=8
) (
	input  logic aclk,
	input  logic aresetn,

	// AXI-Stream Slave Interface
	input  logic signed [AXIS_TDATA_WIDTH-1:0]	s_axis_tdata,	// tdata == {x1, y1, x2, y2}
	input  logic								s_axis_tvalid,
	input  logic								s_axis_tlast,
	output logic								s_axis_tready,

	// AXI-Stream Master Interface
	output logic signed [AXIS_TDATA_WIDTH-1:0]	m_axis_tdata,
	output logic								m_axis_tvalid,
	output logic								m_axis_tlast,
	input  logic								m_axis_tready
);
	// Stage 0 registers
	logic [AXIS_TDATA_WIDTH-1:0] st0_data;
	logic						 st0_valid;

	// Stage 1 registers
	logic [COORD_WIDTH-1:0] st1_x_sub;
	logic [COORD_WIDTH-1:0] st1_y_sub;
	logic					st1_valid;

	// Stage 2 registers
	logic [COORD_WIDTH-1:0] st2_x_abs;
	logic [COORD_WIDTH-1:0] st2_y_abs;
	logic					st2_valid;

	// Stage 3 registers
	logic [COORD_WIDTH-1:0] st3_max;
	logic [COORD_WIDTH-1:0] st3_min;
	logic					st3_valid;

	// Stage 4 registers
	logic [COORD_WIDTH+COEFF_BASE_CLOG2-1:0] st4_max;
	logic						 			 st4_valid;

	// Simple tready implementation
	assign s_axis_tready = !s_axis_tvalid || m_axis_tready;

	// Assigning output signals & buses
	assign m_axis_tdata	 = st4_max[COORD_WIDTH+COEFF_BASE_CLOG2-1:COEFF_BASE_CLOG2];
	assign m_axis_tvalid = st4_valid;
	assign m_axis_tlast	 = 1'b1;

	always_ff @(posedge aclk) begin : stage_0
		if(!aresetn) begin
			st0_data  <= 0;
			st0_valid <= 1'b0;
		end else if(s_axis_tready) begin
			st0_data  <= s_axis_tdata;
			st0_valid <= s_axis_tvalid;
		end
	end

	always_ff @(posedge aclk) begin : stage_1
		if(!aresetn) begin
			st1_x_sub <= 0;
			st1_y_sub <= 0;
			st1_valid <= 1'b0;
		end else begin
			if(!st0_valid) begin
				st1_x_sub <= 0;
				st1_y_sub <= 0;
				st1_valid <= 1'b0;
			end else begin
				st1_x_sub <= st0_data[(4*COORD_WIDTH-1):(3*COORD_WIDTH)] - st0_data[(1*COORD_WIDTH-1):(0*COORD_WIDTH)];
				st1_y_sub <= st0_data[(3*COORD_WIDTH-1):(2*COORD_WIDTH)] - st0_data[(2*COORD_WIDTH-1):(1*COORD_WIDTH)];
				st1_valid <= st0_valid;
			end
		end
	end

	always_ff @(posedge aclk) begin : stage_2
		if(!aresetn) begin
			st2_x_abs <= 0;
			st2_y_abs <= 0;
			st2_valid <= 1'b0;
		end else begin
			if(!st1_valid) begin
				st2_x_abs <= 0;
				st2_y_abs <= 0;
				st2_valid <= 1'b0;
			end else begin
				st2_x_abs <= st1_x_sub[COORD_WIDTH-1] ? -st1_x_sub : st1_x_sub;
				st2_y_abs <= st1_y_sub[COORD_WIDTH-1] ? -st1_y_sub : st1_y_sub;
				st2_valid <= st1_valid;
			end
		end
	end

	always_ff @(posedge aclk) begin : stage_3
		if(!aresetn) begin
			st3_max	  <= 0;
			st3_min	  <= 0;
			st3_valid <= 1'b0;
		end else begin
			if(!st2_valid) begin
				st3_max	  <= 0;
				st3_min	  <= 0;
				st3_valid <= 1'b0;
			end else begin
				if(st2_x_abs > st2_y_abs) begin
					st3_max <= st2_x_abs;
					st3_min <= st2_y_abs;
				end else begin
					st3_max <= st2_y_abs;
					st3_min <= st2_x_abs;
				end
				st3_valid <= st0_valid;
			end
		end
	end

	always_ff @(posedge aclk) begin : stage_4
		if(!aresetn) begin
			st4_max	  <= 0;
			st4_valid <= 1'b0;
		end else begin
			if(!st3_valid) begin
				st4_max	  <= 0;
				st4_valid <= 1'b0;
			end else begin
				`ifdef DEVELOPER_WIP
				if((st3_max << COEFF_BASE_CLOG2) > (st3_max + ((st3_min << 2) + st3_min)))
					st4_max <= (st3_max << COEFF_BASE_CLOG2);
				else
					st4_max <= (st3_max + ((st3_min << 2) + st3_min));
				`else
				st4_max <= (st3_max + ((st3_min << 2) + st3_min));
				`endif
				st4_valid <= st3_valid;
			end
		end
	end

endmodule : vec_mag_core