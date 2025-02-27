//
// video_cond.sv
//
// Copyright (c) 2023 Alexey Melnikov
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

module video_cond
(
	input             clk,

	input             vdp_hclk1,
	input             vdp_de_h,
	input             vdp_de_v,
	input             vdp_intfield,
	input             vdp_m2,
	input             vdp_m5,
	input             vdp_rs1,

	input       [7:0] r_in,
	input       [7:0] g_in,
	input       [7:0] b_in,
	input             hs_in,
	input             vs_in,

	input             pal,
	input             border_en,
	input             h40corr,
	input             blender,

	output reg [11:0] arx,
	output reg [11:0] ary,
	
	output reg        ce_pix,
	output reg        interlace,
	output reg        f1,

	output      [7:0] r_out,
	output      [7:0] g_out,
	output      [7:0] b_out,
	output            hs_out,
	output            vs_out,
	output            hbl_out,
	output            vbl_out
);

reg   [1:0] res_h = 0; // 248/256/320/320cor
reg   [1:0] res_v = 0; // 192/224/240

wire [11:0] arxt[16] = '{/* 248 */ 31,186,124,0, /* 256 */ 32,192,128,0, /* 320 */ 32,192,128,0, /* 320cor */ 32,30,4,0};
wire [11:0] aryt[16] = '{/* 248 */ 7,49,35,0, /* 256 */ 7,49,35,0, /* 320 */ 7,49,35,0, /* 320cor */ 7, 7,1,0};

always @(posedge clk) begin
	arx <= ~border_en ? arxt[{res_h+(res_h[1]&h40corr),res_v}] : pal ? 12'd40 : 12'd4;
	ary <= ~border_en ? aryt[{res_h+(res_h[1]&h40corr),res_v}] : pal ? 12'd11 : 12'd1;
end

reg hs_d;
always @(posedge clk) hs_d <= hs_in;

wire hs_begin = hs_d & ~hs_in;
wire hs_end   = ~hs_d & hs_in;

reg        hs_clean;
reg [12:0] hcnt;
always @(posedge clk) begin
	reg [12:0] hs_width;

	hcnt <= hcnt + 1'd1;

	if(hs_begin & (hcnt[12] | vde_nobrd)) begin
		hcnt <= 0;
		hs_clean <= 0;
	end
	if(hs_end & vde_nobrd) hs_width <= hcnt;
	if(hcnt == hs_width) hs_clean <= 1;
end

always @(posedge clk) begin
	reg vdp_hclk1_d;
	vdp_hclk1_d <= vdp_hclk1;
	ce_pix <= ~vdp_hclk1_d & vdp_hclk1;
end

reg vde_brd, vde_nobrd;
reg hde_brd;
always @(posedge clk) begin
	reg        pal_r;
	reg  [8:0] vcnt;
	reg  [8:0] vbl_s, vbl_e;
	reg  [8:0] vbl_start, vbl_end;
	reg [12:0] hbl_start, hbl_end;

	if(hs_end) vcnt <= vcnt + 1'd1;
	if(~vs_in) begin
		vcnt <= 0;
		pal_r <= pal;
		if(vcnt) begin
			f1 <= vdp_intfield;
			interlace <= f1 ^ vdp_intfield;
		end
	end

	vbl_s     <= pal_r ? 9'd47  : 9'd20;
	vbl_e     <= pal_r ? 9'd286 : 9'd259;

	vbl_start <= res_v[1] ? vbl_s : res_v[0] ? (vbl_s+9'd8) : (vbl_s+9'd21);
	vbl_end   <= res_v[1] ? vbl_e : res_v[0] ? (vbl_e-9'd8) : (vbl_e-9'd27);

	hbl_start <= res_h[1] ? 13'((55    )*20) : 13'((53    )*20);
	hbl_end   <= res_h[1] ? 13'((55+280)*20) : 13'((53+280)*20);

	vde_brd   <= pal_r ? (vcnt >= 22 && vcnt < 310) : (vcnt >= 20 && vcnt < 259);
	vde_nobrd <= (vcnt >= vbl_start && vcnt <= vbl_end);
	hde_brd   <= (hcnt >= hbl_start && hcnt <= hbl_end);
end

always @(posedge clk) begin
	reg [8:0] pcnt;
	reg [1:0] tmp_h;
	reg       vde_d;

	if(~vs_in) begin
		res_v <= ~vdp_m5 ? 2'd0 : ~vdp_m2 ? 2'd1 : 2'd2;
		res_h <= tmp_h;
	end

	if(vdp_de_h & ce_pix) pcnt <= pcnt + 1'd1;

	if(hs_begin) begin
		pcnt <= 0;
		vde_d <= vde_nobrd;
		if(~vde_d && vde_nobrd && pcnt) tmp_h <= (pcnt > 300) ? 2'd2 : (pcnt > 252) ? 2'd1 : 2'd0;
	end
end

wire vbl = ~(border_en ? vde_brd : vde_nobrd);
wire hbl = ~(border_en ? hde_brd : vdp_de_h);

cofi coffee
(
	.clk(clk),
	.pix_ce(ce_pix),
	.enable(blender),

	.hblank(hbl),
	.vblank(vbl),
	.hs(hs_clean),
	.vs(vs_in),
	.red(r_in),
	.green(g_in),
	.blue(b_in),

	.hblank_out(hbl_out),
	.vblank_out(vbl_out),
	.hs_out(hs_out),
	.vs_out(vs_out),
	.red_out(r_out),
	.green_out(g_out),
	.blue_out(b_out)
);


endmodule
