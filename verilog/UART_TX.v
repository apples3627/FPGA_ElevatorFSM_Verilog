module UART_TX (
output reg TX,
input [5:0] FLOOR,    // 1~32
input [1:0] DIR,      // 00: UP, 01: STOP, 10: DOWN
input ERR,
input CLK,
input RST_N,
input TX_temp_stop    // 1이면 전송 일시정지
);

parameter CLKRATE = 16'd434;
parameter T_TICK  = 26'd50_000_000;

reg [25:0] sec_counter;
reg one_sec_tick; 

//카운터
always @(posedge CLK or negedge RST_N) begin
if (!RST_N) begin
sec_counter   <= 26'd0;
one_sec_tick  <= 1'b0;
end else if (sec_counter >= T_TICK - 1) begin
sec_counter   <= 26'd0;
one_sec_tick  <= 1'b1;
end else begin
sec_counter   <= sec_counter + 1'b1;
one_sec_tick  <= 1'b0;
end
end

//bit 전송 타이밍 신호
reg [15:0] cnt;
reg tick;
always @(posedge CLK or negedge RST_N) begin
if (!RST_N) begin
cnt  <= 16'd0;
tick <= 1'b0;
end else if (cnt >= CLKRATE - 1) begin
cnt  <= 16'd0;
tick <= 1'b1;
end else begin
cnt  <= cnt + 1'b1;
tick <= 1'b0;
end
end

// 메시지 버퍼 및 상태
reg [7:0] msg [0:31];//메시지 버퍼
reg [5:0] len; //메시지 길이
reg [5:0] msg_idx; //문자 번호
reg [3:0] bit_idx; // 비트 번호
reg tx_busy; //전송 중 체크 플래그

//TX_temp_stop 감지되면 일시정지 
reg abort_req;

reg [7:0] floor_tens;
reg [7:0] floor_ones;


always @(posedge CLK or negedge RST_N) begin
if (!RST_N) begin
TX       <= 1'b1;
tx_busy  <= 1'b0;
msg_idx  <= 6'd0;
bit_idx  <= 4'd0;
len      <= 6'd0;
abort_req<= 1'b0;
end else begin
// TX 일시정지 감지: 전송 중이면 현재 바이트 끝나면 중단
if (TX_temp_stop && tx_busy)
abort_req <= 1'b1;

    // ERR 메시지 전송, 일시정지 중에는 에러메시지 전송 안하게 만듬
    if (ERR && !tx_busy && !TX_temp_stop) begin
        msg[0]  <= "E";
        msg[1]  <= "R"; msg[2]  <= "R"; msg[3]  <= ":";
        msg[4]  <= "C"; msg[5]  <= "M";
        msg[6]  <= "D";
        msg[7]  <= "\r"; msg[8] <= "\n"; //CRLF
        len     <= 6'd9;    //ERR:CMD 7자 + \r\n 2자 = 9글자
        tx_busy <= 1'b1;
        msg_idx <= 6'd0;
        bit_idx <= 4'd0;
    end
    // 기본 상태, 1초마다 전송하고 TX_temp_stop하면 전송 멈춤
    else if (!ERR && one_sec_tick && !tx_busy && !TX_temp_stop) begin
        //층 수 표현 01~32
        floor_tens = (FLOOR / 10) + 8'd48;
        floor_ones = (FLOOR % 10) + 8'd48;

        //기본 구조
        msg[0]  <= "F";
        msg[1]  <= ":";
        msg[2]  <= floor_tens;
        msg[3]  <= floor_ones;
        msg[4]  <= ",";
        msg[5]  <= "D";
        msg[6]  <= "I";
        msg[7]  <= "R";
        msg[8]  <= ":";

        case(DIR)
            2'b00: begin // UP
                msg[9]  <= "U";
                msg[10] <= "P";
                msg[11] <= "\r";
                msg[12] <= "\n";
                len     <= 6'd13;
            end
            2'b01: begin // STOP
                msg[9]  <= "S";
                msg[10] <= "T";
                msg[11] <= "O";
                msg[12] <= "P";
                msg[13] <= "\r";
                msg[14] <= "\n";
                len     <= 6'd15;
            end
            2'b10: begin // DOWN
                msg[9]  <= "D";
                msg[10] <= "O";
                msg[11] <= "W";
                msg[12] <= "N";
                msg[13] <= "\r";
                msg[14] <= "\n";
                len     <= 6'd15;
            end
            default: begin //출력될 일 없음
                msg[9]  <= "?";
                msg[10] <= "\r";
                msg[11] <= "\n";
                len     <= 6'd12;
            end
        endcase

        tx_busy <= 1'b1;
        msg_idx <= 6'd0;
        bit_idx <= 4'd0;
    end

    // UART 비트 송신
    if (tick) begin
        if (tx_busy) begin
            case (bit_idx)
                4'd0:  TX <= 1'b0; // Start bit 0
                4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8:
                       TX <= msg[msg_idx][bit_idx-1];
                4'd9:  TX <= 1'b1;  // Stop bit 1
                default: TX <= 1'b1;
            endcase

            if (bit_idx == 4'd9) begin
                bit_idx <= 4'd0; //10비트 확인되면 초기화

                // 일시정지 요청 시 현재 바이트 종료 후 즉시 중단
                if (abort_req) begin
                    tx_busy   <= 1'b0;
                    abort_req <= 1'b0;
                end else if (msg_idx < len - 1) begin
                    msg_idx <= msg_idx + 1'b1;
                end else begin
                    tx_busy <= 1'b0; //문자 전부 전송 후 0으로 초기화
                end
            end else begin
                bit_idx <= bit_idx + 1'b1;
            end
        end else begin
            TX <= 1'b1;
            // 일시정지 해제 시를 대비해 abort_req 초기화
            if (!TX_temp_stop)
                abort_req <= 1'b0;
        end
    end
end
end
endmodule
