//C1~C32
//1UP~32UP
//1DOWN~32DOWN
//ex) C5 > CARcall = 1, FLOOR = 5
//12UP > HALLup = 1, FLOOR = 12
//ASD > ERR = 1

//putty 설정
// Terminal > local echo (Force on)
// Connection > Serial (115200 8 1 N N) *꼭 Flow control None처리

module UART_RX(
    input RX,
    input CLK,
    input RST_N,

    output reg [5:0] FLOOR,
    output reg HALLup, //UP
    output reg HALLdown, //DOWN
    output reg CARcall, //차내콜
    output reg ERR //ERR:CMD
);

parameter CLKRATE = 10'd434;
parameter HALFCLK = 10'd217;

localparam IDLE = 3'd0; //대기
localparam START = 3'd1; //비트 감지
localparam DATA = 3'd2; //데이터 수신
localparam STOP = 3'd3; //stop bit 확인

// 레지스터
reg [2:0] rx_state; //UART 현재 상태
reg [9:0] clk_cnt; 
reg [2:0] bit_cnt; //수신 받고 있는 비트순서
reg [7:0] rx_byte;// 수신 받는 1바이트
reg rx_done; //완료 플래그

reg [7:0] rx_buffer [0:7]; // 문자 저장 버퍼
reg [2:0] rx_buffer_idx; //버퍼위치
reg rx_buffer_rdy; //한줄 완료 플래그

reg [2:0] cmd_len; //명령어 길이 
reg [5:0] parsed_floor_num; //층 임시 저장

reg [3:0] parsed_len;//10, 1의 자리 1 or 2
reg [7:0] parsed_digit1, parsed_digit0; //10의 자리, 1의자리


//Reset + FSM
always @(posedge CLK or negedge RST_N) begin
    if (!RST_N) begin
        rx_state <= IDLE;
        clk_cnt <= 10'd0;
        bit_cnt <= 3'd0;
        rx_byte <= 8'd0;
        rx_done <= 1'b0;
        rx_buffer_idx <= 3'd0;
        rx_buffer_rdy <= 1'b0;
        cmd_len <= 3'd0;
        HALLup <= 1'b0;
        HALLdown <= 1'b0;
        CARcall <= 1'b0;
        ERR <= 1'b0;
        FLOOR <= 6'd0;
    end else begin
        rx_done <= 1'b0;
        rx_buffer_rdy <= 1'b0;
        HALLup <= 1'b0;
        HALLdown <= 1'b0;
        CARcall <= 1'b0;
        ERR <= 1'b0;
        
        case (rx_state)
            IDLE: begin //시작비트 감지되면 START로
                if (RX == 1'b0) begin
                    rx_state <= START;
                    clk_cnt <= 10'd0;
                end
            end
            START: begin 
                if (clk_cnt == HALFCLK) begin //비트 중간에 0체크
                    if (RX == 1'b0) begin
                        rx_state <= DATA;
                        clk_cnt <= 10'd0;
                        bit_cnt <= 3'd0;
                    end else begin
                        rx_state <= IDLE; //시작비트 오류면 IDLE로
                    end
                end else clk_cnt <= clk_cnt + 1'b1;
            end
            DATA: begin
                if (clk_cnt == CLKRATE - 1) begin
                    clk_cnt <= 10'd0;
                    rx_byte[bit_cnt] <= RX;//LSB부터 저장함
                    if (bit_cnt == 3'd7)
                        rx_state <= STOP; //8비트 다 모이면 STOP으로 
                    else
                        bit_cnt <= bit_cnt + 1'b1;
                end else clk_cnt <= clk_cnt + 1'b1;
            end
            STOP: begin
                if (clk_cnt == CLKRATE - 1) begin
                    if (RX == 1'b1) rx_done <= 1'b1; //STOP bit 1체크 후 끝냄
                    rx_state <= IDLE;
                    clk_cnt <= 10'd0;
                end else clk_cnt <= clk_cnt + 1'b1;
            end
        endcase

        if (rx_done) begin //입력 받은 데이터 버퍼에 저장
            if (rx_byte == 8'h0D) begin  // CR (Enter)
                rx_buffer_rdy <= 1'b1;
                cmd_len <= rx_buffer_idx;
                rx_buffer_idx <= 3'd0;
            end else if (rx_buffer_idx < 3'd7) begin
                rx_buffer[rx_buffer_idx] <= rx_byte;
                rx_buffer_idx <= rx_buffer_idx + 1'b1;
            end
        end

        if (rx_buffer_rdy) begin
            parsed_floor_num = 6'd0; //값 초기화
            
            //CAR (Cx or Cxx) ex : C1, C32
            if (rx_buffer[0] == 8'h43) begin  //앞자리 'C' 체크
                parsed_len = (cmd_len - 1) - 3'd1 + 1'd1; // 숫자 길이 체크
                
                if (parsed_len == 1) begin
                    parsed_digit0 = rx_buffer[3'd1] - 8'd48; // start_idx = 1
                    if (parsed_digit0 <= 9)
                        parsed_floor_num = parsed_digit0;
                end else if (parsed_len == 2) begin
                    parsed_digit1 = rx_buffer[3'd1] - 8'd48;     // start_idx = 1
                    parsed_digit0 = rx_buffer[3'd1 + 1] - 8'd48; // start_idx + 1
                    if (parsed_digit1 <= 9 && parsed_digit0 <= 9)
                        parsed_floor_num = (parsed_digit1 * 10) + parsed_digit0;
                end
                if (parsed_floor_num < 1 || parsed_floor_num > 32)
                    parsed_floor_num = 6'd0; // 유효하지 않으면 0

                if (parsed_floor_num >= 1 && parsed_floor_num <= 32) begin
                    CARcall <= 1'b1;
                    FLOOR <= parsed_floor_num;
                end else ERR <= 1'b1;


            // UP (xUP or xxUP) ex: 1UP, 32UP
            end else if (cmd_len >= 3 && 
                         rx_buffer[cmd_len-2] == 8'h55 && // 'U'
                         rx_buffer[cmd_len-1] == 8'h50) begin // 'P'
                            //UP확인 되면 아래 진행
                parsed_len = (cmd_len - 3) - 3'd0 + 1'd1; // len = end_idx - start_idx + 1
                
                if (parsed_len == 1) begin
                    parsed_digit0 = rx_buffer[3'd0] - 8'd48; // start_idx = 0
                    if (parsed_digit0 <= 9)
                        parsed_floor_num = parsed_digit0;
                end else if (parsed_len == 2) begin
                    parsed_digit1 = rx_buffer[3'd0] - 8'd48;     // start_idx = 0
                    parsed_digit0 = rx_buffer[3'd0 + 1] - 8'd48; // start_idx + 1
                    if (parsed_digit1 <= 9 && parsed_digit0 <= 9)
                        parsed_floor_num = (parsed_digit1 * 10) + parsed_digit0;
                end
                if (parsed_floor_num < 1 || parsed_floor_num > 32)
                    parsed_floor_num = 6'd0; // 유효하지 않으면 0
                
                if (parsed_floor_num >= 1 && parsed_floor_num <= 32) begin
                    HALLup <= 1'b1;
                    FLOOR <= parsed_floor_num;
                end else ERR <= 1'b1;


            // DOWN (xDOWN or xxDOWN) ex: 1DOWN, 32DOWN
            end else if (cmd_len >= 5 && 
                         rx_buffer[cmd_len-4] == 8'h44 && // 'D'
                         rx_buffer[cmd_len-3] == 8'h4F && // 'O'
                         rx_buffer[cmd_len-2] == 8'h57 && // 'W'
                         rx_buffer[cmd_len-1] == 8'h4E) begin // 'N'
                        //DOWN 확인되면 아래 진행

                parsed_len = (cmd_len - 5) - 3'd0 + 1'd1; // len = end_idx - start_idx + 1
                if (parsed_len == 1) begin
                    parsed_digit0 = rx_buffer[3'd0] - 8'd48; 
                    if (parsed_digit0 <= 9)
                        parsed_floor_num = parsed_digit0;
                end else if (parsed_len == 2) begin
                    parsed_digit1 = rx_buffer[3'd0] - 8'd48;     
                    parsed_digit0 = rx_buffer[3'd0 + 1] - 8'd48; 
                    if (parsed_digit1 <= 9 && parsed_digit0 <= 9)
                        parsed_floor_num = (parsed_digit1 * 10) + parsed_digit0;
                end
                if (parsed_floor_num < 1 || parsed_floor_num > 32)
                    parsed_floor_num = 6'd0; // 유효하지 않으면 0

                if (parsed_floor_num >= 1 && parsed_floor_num <= 32) begin
                    HALLdown <= 1'b1;
                    FLOOR <= parsed_floor_num;
                end else ERR <= 1'b1;

            end else ERR <= 1'b1; //위에 다 해당하지 않으면 잘못된 문자 입력 -> ERR:CMD 출력
        end
    end
end

endmodule