module elevator_display_controller (
    // Inputs
    input [5:0] current_floor,   // 1~32층
    input [1:0] report_dir,      // 00: UP, 01: STOP, 10: DOWN
    
    // Outputs
    output reg [6:0] HEX7_O, //U
    output reg [6:0] HEX6_O, // P
    output      [6:0] HEX5_O,    // 십의 자리
    output      [6:0] HEX4_O,    // 일의 자리
 
 //DOWN STOP 표현
    output reg [6:0] HEX3_O,
    output reg [6:0] HEX2_O,
    output reg [6:0] HEX1_O,
    output reg [6:0] HEX0_O
);
localparam SEG_0 = 7'b1000000;
localparam SEG_1 = 7'b1111001;
localparam SEG_2 = 7'b0100100;
localparam SEG_3 = 7'b0110000;
localparam SEG_4 = 7'b0011001;
localparam SEG_5 = 7'b0010010;
localparam SEG_6 = 7'b0000010;
localparam SEG_7 = 7'b1111000;
localparam SEG_8 = 7'b0000000;
localparam SEG_9 = 7'b0010000;

localparam SEG_U = 7'b1000001;
localparam SEG_P = 7'b0001100;
localparam SEG_D = 7'b0100001;
localparam SEG_O = 7'b1000000;
localparam SEG_W = 7'b0010101;
localparam SEG_N = 7'b0101011;
localparam SEG_S = 7'b0010010;
localparam SEG_T = 7'b0000111;
localparam SEG_BLANK = 7'b1111111;

// HEX5번 4번 01~32 표현
function [6:0] bcd_to_seg;
    input [3:0] bin;
    begin
        case (bin)
            4'd0: bcd_to_seg = SEG_0;
            4'd1: bcd_to_seg = SEG_1;
            4'd2: bcd_to_seg = SEG_2;
            4'd3: bcd_to_seg = SEG_3;
            4'd4: bcd_to_seg = SEG_4;
            4'd5: bcd_to_seg = SEG_5;
            4'd6: bcd_to_seg = SEG_6;
            4'd7: bcd_to_seg = SEG_7;
            4'd8: bcd_to_seg = SEG_8;
            4'd9: bcd_to_seg = SEG_9;
            default: bcd_to_seg = SEG_BLANK;
        endcase
    end
endfunction
// 층수 분리
wire [3:0] floor_tens = current_floor / 10;
 // 0~3
wire [3:0] floor_ones = current_floor % 10;  // 0~9

// 십의 자리 HEX5 (01, 02,~,09)
assign HEX5_O = bcd_to_seg(floor_tens);
// 일의 자리 HEX4
assign HEX4_O = bcd_to_seg(floor_ones);

// 진행 방향 표시 (HEX7~HEX0)
always @(*) begin
    case (report_dir)
        2'b00: begin  // UP
            HEX7_O = SEG_U;
            HEX6_O = SEG_P;
            HEX3_O = SEG_BLANK;
            HEX2_O = SEG_BLANK;
            HEX1_O = SEG_BLANK;
            HEX0_O = SEG_BLANK;
        end
        2'b10: begin  // DOWN
            HEX7_O = SEG_BLANK;
            HEX6_O = SEG_BLANK;
            HEX3_O = SEG_D;
            HEX2_O = SEG_O;
            HEX1_O = SEG_W;
            HEX0_O = SEG_N;
        end
        default: begin  // STOP
            HEX7_O = SEG_BLANK;
            HEX6_O = SEG_BLANK;
            HEX3_O = SEG_S;
            HEX2_O = SEG_T;
            HEX1_O = SEG_O;
            HEX0_O = SEG_P;
        end
    endcase
end

endmodule