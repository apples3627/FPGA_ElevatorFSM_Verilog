module elevator_controller (
input CLK,
input RST_N,
input BTN_OPEN_db,
input BTN_CLOSE_db,
input EMG_STOP,

//TB 작동 시 주석 
input UART_RX, // TB용 주석
input TX_temp_stop_db, // TB용 주석
output UART_TX, 
//TB 작동 시 주석 끝

// --- TB용 추가 포트 ---
//input        T_TICK,       // 1초 시뮬레이션 틱
//input [5:0]  CALL_FLOOR,   // TB 호출 층
//input        CALL_DIR,     // TB 호출 방향 (1=UP, 0=DOWN)
//input        CALL_VALID,   // TB 호출 유효 펄스
// --- TB용 추가 포트 끝 ---

output reg MOTOR_UP,
output reg MOTOR_DN,
output reg DOOR_OPEN_DRV,
output reg DOOR_CLOSE_DRV,
output [5:0] o_current_floor,
output [1:0] o_report_dir
);
//******************************
     //TB 작동 시 주석 
     //******************************
localparam TICK         = 32'd50_000_000; //  TB에서는 T_TICK 사용
 localparam BAUD_RATE         = 115200; 
//******************************
     //TB 작동 시 주석 
     //******************************
     
     
//문 열림 1초 + 정차 3초 + 닫힘 1초 = 5초
//TB에서 "* TICK" 지우기!!
localparam DOOR_TIME         = 1*TICK; 
localparam DWELL_TIME        = 3*TICK; 
localparam FLOOR_TRAVEL_TIME = 2*TICK; 
//TB에서 "* TICK" 지우기!!


localparam MIN_FLOOR         = 1;
localparam MAX_FLOOR         = 32;
localparam FLOOR_BITS        = 6;
localparam START_FLOOR       = 6'd1;


localparam S_IDLE_STOP    = 4'd0;
localparam S_DOOR_OPEN    = 4'd1; //문열림
localparam S_DWELL        = 4'd2;
localparam S_DOOR_CLOSE   = 4'd3; //문 닫힘
localparam S_MOVING_UP    = 4'd4;
localparam S_MOVING_DOWN  = 4'd5; //아래로 이동
localparam S_EMG_STOP     = 4'd6;

localparam DIR_UP   = 2'b00;
localparam DIR_STOP = 2'b01;
localparam DIR_DOWN = 2'b10;

reg [FLOOR_BITS-1:0] current_floor;
reg [3:0] state, next_state;
reg [31:0] timer;
reg [1:0] current_dir;
reg [1:0] report_dir;
reg [3:0]  saved_state;
reg [31:0] saved_timer;
reg [3:0]  resume_state;
reg        resume_pending;
reg [1:0] next_dir;

//타이머 로드 제어
reg        timer_load_req_c;
reg [31:0] timer_load_value_c;
reg close_req;

reg [MAX_FLOOR:MIN_FLOOR] hall_up_calls; //홀 업 호출
reg [MAX_FLOOR:MIN_FLOOR] hall_down_calls;
reg [MAX_FLOOR:MIN_FLOOR] car_calls; //차내콜


//****TB에서 주석 시작****/
wire [FLOOR_BITS-1:0] rx_floor; //RX로 수신 받은 층수 // TB용 주석
wire rx_hall_up, rx_hall_down, rx_car_call, rx_err_pulse; // TB용 주석

reg  tx_err_req; //TX로 보낼 에러플래그 // TB용 주석


 //UART 연결 // TB용 주석
 UART_RX i_uart_rx (
 .CLK(CLK), .RST_N(RST_N), .RX(UART_RX),
 .FLOOR(rx_floor), .HALLup(rx_hall_up), .HALLdown(rx_hall_down),
 .CARcall(rx_car_call), .ERR(rx_err_pulse)
 );
 UART_TX i_uart_tx (
 .CLK(CLK), .RST_N(RST_N), .FLOOR(current_floor),
 .DIR(report_dir), .ERR(tx_err_req), .TX(UART_TX), .TX_temp_stop(TX_temp_stop_db)
 );
//****TB에서 주석 끝****/

//동시 콜 들어왔을 때 어떤 콜 해제할지 제어용
reg clr_hall_up_c, clr_hall_down_c;
//상태 저장 + 기본 로직
always @(posedge CLK or negedge RST_N) begin
integer k;
if (!RST_N) begin
    state           <= S_IDLE_STOP;
    current_floor   <= START_FLOOR;
    timer           <= 32'd0;
    current_dir     <= DIR_STOP;
    hall_up_calls   <= 'b0;
    hall_down_calls <= 'b0;
    car_calls       <= 'b0;
	 
	 //****TB에서 주석 시작 ****/
    tx_err_req      <= 1'b0; 
    //****TB에서 주석 끝****/
	 
	 
    saved_state     <= S_IDLE_STOP;
    saved_timer     <= 32'd0;
    resume_state    <= S_IDLE_STOP;
    resume_pending  <= 1'b0;
    close_req       <= 1'b0;
	 
end else begin

    if (EMG_STOP) begin
        // EMG 진입 시 현재 상태/타이머 저장
        if (state != S_EMG_STOP) begin
            saved_state <= state;
            saved_timer <= timer;
        end
        state          <= S_EMG_STOP;
        current_dir    <= DIR_STOP;
        resume_pending <= 1'b0;   // EMG 유지 중에는 복귀 예약 해제
        close_req      <= 1'b0;
    end else begin
        state <= next_state;
        // 방향 체크
       current_dir <= next_dir;

       // 타이머 리셋/증가 + EMG 상태 시 로드
       if (state != next_state) begin
           if (timer_load_req_c)
               timer <= timer_load_value_c;
           else
               timer <= 32'd0;
       end else begin
           


           //****TB에서 주석 시작****/
            case (state)
                S_MOVING_UP, S_MOVING_DOWN, S_DOOR_OPEN, S_DOOR_CLOSE:
                    timer <= timer + 1; 
                S_DWELL: begin
                    if (BTN_OPEN_db) timer <= 32'd0; 
                    else              timer <= timer + 1; 
                end
                default: timer <= 32'd0; 
            endcase
           //****TB에서 주석 시작****/

          //****TB에서 주석 해제****/
      //     case (state)
      //         S_MOVING_UP, S_MOVING_DOWN, S_DOOR_OPEN, S_DOOR_CLOSE: begin
      //             if (T_TICK) timer <= timer + 1;
      //         end
      //         S_DWELL: beginf
      //             if (BTN_OPEN_db) timer <= 32'd0; 
      //             else if (T_TICK) timer <= timer + 1;
      //         end
      //         default: timer <= 32'd0; 
      //     endcase
       //****TB에서 주석 해제 ****/
       
		 end
        // EMG_STOP 해제 후: S_EMG_STOP -> S_IDLE_STOP 복귀 예약
        if (state == S_EMG_STOP && next_state == S_IDLE_STOP) begin
            resume_state   <= saved_state;
            if (saved_state == S_DOOR_OPEN  ||
                saved_state == S_DOOR_CLOSE ||
                saved_state == S_DWELL      ||
                saved_state == S_MOVING_UP  ||
                saved_state == S_MOVING_DOWN) begin
             
                resume_pending <= 1'b1;
            end else begin
                resume_pending <= 1'b0;
            end
        end
        if (state == S_IDLE_STOP && resume_pending && next_state == resume_state) begin
            resume_pending <= 1'b0;
        end

        // 닫힘 요청
        if (state == S_DOOR_OPEN || state == S_DWELL) begin
            if (BTN_OPEN_db)       close_req <= 1'b0;
            else if (BTN_CLOSE_db) close_req <= 1'b1;
        end
        if (next_state == S_DOOR_CLOSE) close_req <= 1'b0;

        // 층수 이동 (이동 완료 시 한 층 이동)
        if (state == S_MOVING_UP && next_state == S_IDLE_STOP && current_floor < MAX_FLOOR)
            current_floor <= current_floor + 1'd1;
        if (state == S_MOVING_DOWN && next_state == S_IDLE_STOP && current_floor > MIN_FLOOR)
            current_floor <= current_floor - 1'd1;

        //****TB에서 주석 시작****/
         //UART 수신 받고 호출 방향 등록
         if (rx_hall_up   && rx_floor >= MIN_FLOOR && rx_floor <= MAX_FLOOR) hall_up_calls[rx_floor]   <= 1'b1; 
         if (rx_hall_down && rx_floor >= MIN_FLOOR && rx_floor <= MAX_FLOOR) hall_down_calls[rx_floor] <= 1'b1; 
         if (rx_car_call  && rx_floor >= MIN_FLOOR && rx_floor <= MAX_FLOOR) car_calls[rx_floor]       <= 1'b1; 
         //오류 확인
         if (rx_err_pulse) tx_err_req <= 1'b1; 
         else              tx_err_req <= 1'b0; 
         //****TB에서 주석 끝****/

    //   //****TB에서 주석 해제****/
    //   if (CALL_VALID && CALL_FLOOR >= MIN_FLOOR && CALL_FLOOR <= MAX_FLOOR) begin
    //       car_calls[CALL_FLOOR] <= 1'b1; // FSM이 car_call을 참조하므로 TB콜을 car_call로도 등록
    //       if (CALL_DIR == 1'b1) begin // 1 = UP 
    //           hall_up_calls[CALL_FLOOR] <= 1'b1;
    //       end else begin // 0 = DOWN
    //           hall_down_calls[CALL_FLOOR] <= 1'b1;
    //       end
    //   end
        //****TB에서 주석 해제 ****/


        //문 열릴 때 현재 층 호출 제거
        if (next_state == S_DOOR_OPEN && state != S_DOOR_OPEN) begin
            car_calls[current_floor] <= 1'b0;
            if (clr_hall_up_c)   hall_up_calls[current_floor]   <= 1'b0;
            if (clr_hall_down_c) hall_down_calls[current_floor] <= 1'b0;
        end
    end
end



end

//상태 결정 로직
always @(*) begin
reg stop_here; //현재 층에서 정지?


//Call_in은 한 방향만 체크
//any_call은 위아래 두 방향 모두 체크
reg call_in_dir_up; //위로 가는 콜 더 있는지?s
reg call_in_dir_down; //아래
reg any_call_above; //현재 층 위로 콜 더있는지?
reg any_call_below; //아래

integer i;

reg [FLOOR_BITS-1:0] closest_call_above; //가장 가까운 위층 콜
reg [FLOOR_BITS-1:0] closest_call_below; // 아래
reg [FLOOR_BITS-1:0] dist_up; //현재 층에서 가장 가까운 위층 콜
reg [FLOOR_BITS-1:0] dist_down;
reg is_highest_call; //현재 층이 최상층 콜인지 확인
reg is_lowest_call; 


stop_here = 1'b0;
call_in_dir_up = 1'b0;
call_in_dir_down = 1'b0;
any_call_above = 1'b0;
any_call_below = 1'b0;
closest_call_above = current_floor;
closest_call_below = current_floor;

timer_load_req_c   = 1'b0;
timer_load_value_c = 32'd0;

// 동시 콜 해제 값
clr_hall_up_c   = 1'b0;
clr_hall_down_c = 1'b0;

//위/아래 호출 탐색
for (i = MIN_FLOOR; i <= MAX_FLOOR; i = i + 1) begin
    if (i > current_floor) begin
    //위층
        if (hall_up_calls[i] || hall_down_calls[i] || car_calls[i]) begin
            any_call_above = 1'b1;
            if (closest_call_above == current_floor) closest_call_above = i;
            else if (i < closest_call_above) closest_call_above = i;
        end
        if (hall_up_calls[i] || car_calls[i]) call_in_dir_up = 1'b1;
    end else if (i < current_floor) begin
    
    //아래층
        if (hall_up_calls[i] || hall_down_calls[i] || car_calls[i]) begin
            any_call_below = 1'b1;
            if (closest_call_below == current_floor) closest_call_below = i;
            else if (i > closest_call_below) closest_call_below = i;
        end
        if (hall_down_calls[i] || car_calls[i]) call_in_dir_down = 1'b1;
    end
end

// 고층 / 저층 호출 판단
is_highest_call = (hall_up_calls[current_floor] || hall_down_calls[current_floor] || car_calls[current_floor]) && !any_call_above;
is_lowest_call  = (hall_up_calls[current_floor] || hall_down_calls[current_floor] || car_calls[current_floor]) && !any_call_below;

// 현재 층 정지 조건
stop_here = (car_calls[current_floor]) ||
            (hall_up_calls[current_floor] && current_dir != DIR_DOWN) ||
            (hall_down_calls[current_floor] && current_dir != DIR_UP) ||
            (current_dir == DIR_UP && is_highest_call) ||
            (current_dir == DIR_DOWN && is_lowest_call) ||
            (current_dir == DIR_STOP && (hall_up_calls[current_floor] || hall_down_calls[current_floor]));
next_dir = current_dir;
next_state    = state;
MOTOR_UP      = 1'b0;
MOTOR_DN    = 1'b0;
DOOR_OPEN_DRV = 1'b0;
DOOR_CLOSE_DRV= 1'b0;

//FSM
case (state)
S_IDLE_STOP: begin
            if (resume_pending) begin
                next_state = resume_state; //저장한 곳 이동
                
                if (resume_state == S_MOVING_UP)
                    next_dir = DIR_UP;
                else if (resume_state == S_MOVING_DOWN)
                    next_dir = DIR_DOWN;
                else
                    next_dir = DIR_STOP; // 문 열림/DWELL 등으로 복귀 시

                if (resume_state == S_DOOR_OPEN || resume_state == S_DOOR_CLOSE) begin
                    timer_load_req_c   = 1'b1;
                    timer_load_value_c = 32'd0; //0초부터
                end else if (resume_state == S_DWELL ||
                             resume_state == S_MOVING_UP ||
                             resume_state == S_MOVING_DOWN) begin
                    // DWELL/이동은 남은 시간부터
                    timer_load_req_c   = 1'b1;
                    timer_load_value_c = saved_timer;
                end
            
            end else if (stop_here) begin //현재 층에 호출있으면 문 열음
                next_state = S_DOOR_OPEN;
               
            
            end else if (current_dir == DIR_UP) begin // 위로 가던 중
                if (any_call_above) begin //위에 어떤 콜이든 있으면 계속 상승
                    next_state = S_MOVING_UP;
                    
                end else if (any_call_below) begin // 위에 콜이 없으면 아래 콜 확인 후 하강
                    next_state = S_MOVING_DOWN;
                    next_dir   = DIR_DOWN; //방향 전환
                end else begin
                    next_dir = DIR_STOP; //모든 콜이 없으면 정지
                end

            end else if (current_dir == DIR_DOWN) begin // 아래로 가던 중
                if (any_call_below) begin //아래에 어떤 콜이든 있으면 계속 하강
                    next_state = S_MOVING_DOWN;
                    
                end else if (any_call_above) begin // 아래 콜이 없으면 위 콜 확인 후 상승
                    next_state = S_MOVING_UP;
                    next_dir   = DIR_UP; //방향 전환
                end else begin
                    next_dir = DIR_STOP; //모든 콜이 없으면 정지
                end

            end else begin // current_dir == DIR_STOP (완전 정지 상태)
                if (any_call_above && !any_call_below) begin
                    next_state = S_MOVING_UP; 
                    next_dir   = DIR_UP; //방향 설정
                end else if (!any_call_above && any_call_below) begin
                    next_state = S_MOVING_DOWN;
                    next_dir   = DIR_DOWN; // 방향 설정
                end else if (any_call_above && any_call_below) begin
                    // 가까운 쪽으로 이동
                    dist_up   = closest_call_above - current_floor;
                    dist_down = current_floor - closest_call_below;
                    if (dist_up <= dist_down) begin // 같으면 위로
                        next_state = S_MOVING_UP;
                        next_dir   = DIR_UP; // 방향 설정
                   end else begin
						  next_state = S_MOVING_DOWN;
                    next_dir   = DIR_DOWN; //방향 설정
                    end
                end
                // (else: 아무 호출도 없으면 IDLE, DIR_STOP 유지
            end
        end

    S_MOVING_UP: begin
        MOTOR_UP = 1'b1; //32층 or 2초 지나면 IDLE
		  next_dir = DIR_UP;
        if (current_floor >= MAX_FLOOR || timer >= FLOOR_TRAVEL_TIME - 1)
            next_state = S_IDLE_STOP;
    end

    S_MOVING_DOWN: begin
        MOTOR_DN = 1'b1; //1층 or 2초
		  next_dir = DIR_DOWN;
        if (current_floor <= MIN_FLOOR || timer >= FLOOR_TRAVEL_TIME - 1)
            next_state = S_IDLE_STOP;
    end

    // 열림 1초 보장, 그 전에는 닫힘 명령 무시
    S_DOOR_OPEN: begin
        DOOR_OPEN_DRV = 1'b1;
        if (timer >= DOOR_TIME - 1) begin
            if (close_req || BTN_CLOSE_db) next_state = S_DOOR_CLOSE; // 1초 후 대기 스킵 후 즉시 닫힘으로
            else                           next_state = S_DWELL;      // DWELL state로 넘어감 3초
        end
    end

    // 정차 3초, 닫힘 버튼 눌리면 즉시 닫힘으로
    S_DWELL: begin
        DOOR_OPEN_DRV = 1'b1;
        if (BTN_OPEN_db) begin
            next_state = S_DOOR_OPEN;                // 오픈버튼 눌려있으면 계속 열어둠
        end else if (BTN_CLOSE_db || close_req) begin
            next_state = S_DOOR_CLOSE;           // 닫힘버튼 눌려서 DOOR CLOSE로 넘어감
        end else if (timer >= DWELL_TIME - 1) begin
            next_state = S_DOOR_CLOSE;           // 3초 후 자동으로 닫힘
        end
    end

    S_DOOR_CLOSE: begin
        DOOR_CLOSE_DRV = 1'b1;
        if (BTN_OPEN_db) next_state = S_DOOR_OPEN;               // 닫히기 전에 open 눌리면 OPEN으로
        else if (timer >= DOOR_TIME - 1) next_state = S_IDLE_STOP; //1초 지나면 끝
    end

    S_EMG_STOP: begin
	 next_dir = DIR_STOP;
        if (!EMG_STOP) next_state = S_IDLE_STOP; // EMG_STOP 해제되면 일단 IDLE로
    end
endcase

//Elevator 진행 방향 전송용
case (state)
    S_MOVING_UP:   report_dir = DIR_UP;
    S_MOVING_DOWN: report_dir = DIR_DOWN;
    default:       report_dir = DIR_STOP;
endcase

// 문 오픈 진입 시, 현재 층 홀 콜 해제 관련
if (state != S_DOOR_OPEN && next_state == S_DOOR_OPEN) begin
    // 현재 층의 홀 콜 상태
    reg at_up, at_dn;
    at_up = hall_up_calls[current_floor]; //올라가는 거 체크
    at_dn = hall_down_calls[current_floor]; 

    if (at_up || at_dn) begin
        if (at_up && at_dn) begin
            // 동시 콜 
            if (current_dir == DIR_UP) begin
                if (any_call_above) begin
                    // 위로 더 갈 콜이 있으면 UP만 해제
                    clr_hall_up_c   = 1'b1;
                    clr_hall_down_c = 1'b0;
                end else begin
                    // 전환점이면 둘 다 해제 
                    clr_hall_up_c   = 1'b1;
                    clr_hall_down_c = 1'b1;
                end
            end else if (current_dir == DIR_DOWN) begin
                if (any_call_below) begin
                    // 아래로 더 갈 콜이 있으면 DOWN만 해제
                    clr_hall_up_c   = 1'b0;
                    clr_hall_down_c = 1'b1;
                end else begin
                    // 전환점이면 둘 다 해제
                    clr_hall_up_c   = 1'b1;
                    clr_hall_down_c = 1'b1;
                end
            end else begin
                // 멈춰있는 상태
                if (any_call_above && !any_call_below) begin
                    clr_hall_up_c   = 1'b1;
                    clr_hall_down_c = 1'b0;
                end else if (!any_call_above && any_call_below) begin
                    clr_hall_up_c   = 1'b0;
                    clr_hall_down_c = 1'b1;
                end else if (any_call_above && any_call_below) begin
                    dist_up   = closest_call_above - current_floor;
                    dist_down = current_floor - closest_call_below;
                    if (dist_up < dist_down) begin
                        clr_hall_up_c   = 1'b1; clr_hall_down_c = 1'b0;
                    end else begin
                        clr_hall_up_c   = 1'b0; clr_hall_down_c = 1'b1;
                    end
                end else begin
                    // 주변 추가 콜이 없으면 둘 다 해제
                    clr_hall_up_c   = 1'b1;
                    clr_hall_down_c = 1'b1;
                end
            end
        end else begin
            // 단일 콜이면 해당 콜만 해제
            clr_hall_up_c   = at_up;
            clr_hall_down_c = at_dn;
        end
    end
end

// 모터/문 충돌 방지
if (MOTOR_UP && MOTOR_DN) begin
    MOTOR_UP = 1'b0;
    MOTOR_DN = 1'b0;
end
if (DOOR_OPEN_DRV && DOOR_CLOSE_DRV) begin
    DOOR_OPEN_DRV = 1'b0;
    DOOR_CLOSE_DRV = 1'b0;
end
if (DOOR_OPEN_DRV || state == S_DWELL || state == S_DOOR_OPEN) begin
    MOTOR_UP = 1'b0;
    MOTOR_DN = 1'b0;
end

end

//현재 층, 이동방향 전송
assign o_current_floor = current_floor;
assign o_report_dir    = report_dir;

endmodule