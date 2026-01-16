module ELEVATOR_TOP (
    // Clock / Reset
    input CLK,
    input RST_N,
    
    // --- TB용 추가 포트 ---
 //   input T_TICK,
 //   input [5:0] CALL_FLOOR,
 //   input CALL_DIR,
 //   input CALL_VALID,
    // --- TB용 추가 포트 끝 ---

    // 버튼 입력 (Active High)
    input BTN_OPEN,
    input BTN_CLOSE,
     
    //KEY안쓰고 SW사용
    input EMG_STOP, // 기존 fpga KEY로 쓰다가 SW로 변경   

//****TB에서 주석 시작****/
    // UART
    input UART_RXD, 
    input BTN_TX_STOP,
    output UART_TXD, 
//    7-Segment
    output [6:0] HEX0,
    output [6:0] HEX1,
    output [6:0] HEX2,
    output [6:0] HEX3,
    output [6:0] HEX4,
    output [6:0] HEX5,
    output [6:0] HEX6,
    output [6:0] HEX7,
//****TB에서 주석 끝****/
     
    // 모터/도어 출력
    output MOTOR_UP,
    output MOTOR_DN,
    output DOOR_OPEN_DRV,
    output DOOR_CLOSE_DRV //TB에서 ,붙이기 
	 
// --- TB용 추가 포트 ---
 //   output [5:0] CURRENT_FLOOR,
 //   output [1:0] CURRENT_DIR
    // --- TB용 추가 포트 끝 ---

);
    wire [5:0] floor_w;
    wire [1:0] dir_w;
     
     
// 버튼 디바운싱
    wire btn_open_db;
    wire btn_close_db;
    wire btn_emg_db;

//****TB에서 주석 시작****/
    wire tx_stop_db; // TB용 주석
//****TB에서 주석 끝****/


//내부에서는 버튼들이 HIGH ACTIVE으로 돌아가고
//FPGA KEY가 low-active라서 TOP에서 신호 반전 처리함
// -> TB는 Active-High이므로 시뮬레이션을 위해 반전(~) 제거

    debouncer db_open (
        .CLK     (CLK),
        .RST_N    (RST_N),
        .btn_in  (~BTN_OPEN),     // .btn_in  (BTN_OPEN), 
        .btn_out (btn_open_db)
    );
    debouncer db_close (
        .CLK     (CLK),
        .RST_N    (RST_N),
        .btn_in  (~BTN_CLOSE),    // .btn_in  (BTN_CLOSE), 
        .btn_out (btn_close_db)
    );
    debouncer db_emg (
        .CLK     (CLK),
        .RST_N    (RST_N),
        .btn_in  (~EMG_STOP),     // .btn_in  (EMG_STOP), 
        .btn_out (btn_emg_db)
    );

    //****TB에서 주석 시작****/
  debouncer db_txstop ( // TB용 주석
 .CLK     (CLK),
 .RST_N    (RST_N),
 .btn_in  (~BTN_TX_STOP),
 .btn_out (tx_stop_db)
 );
 //****TB에서 주석 끝****/   

    elevator_controller i_controller ( 
        .CLK (CLK), 
        .RST_N (RST_N), 
        .BTN_OPEN_db (btn_open_db), 
        .BTN_CLOSE_db (btn_close_db), 
        .EMG_STOP (btn_emg_db), 

        //****TB에서 주석 시작****/
         .UART_RX (UART_RXD), // TB용 주석
         .TX_temp_stop_db(tx_stop_db), // TB용 주석
        .UART_TX (UART_TXD), // TB에서 사용 안 함
        //****TB에서 주석 끝 ****/

        // --- TB용 추가 포트 연결 ---
        //.T_TICK (T_TICK),
        //.CALL_FLOOR (CALL_FLOOR),
        //.CALL_DIR (CALL_DIR),
        //.CALL_VALID (CALL_VALID),
        // --- TB용 추가 포트 연결 끝 ---

        .MOTOR_UP (MOTOR_UP), 
        .MOTOR_DN (MOTOR_DN), 
        .DOOR_OPEN_DRV (DOOR_OPEN_DRV), 
        .DOOR_CLOSE_DRV (DOOR_CLOSE_DRV), 
        .o_current_floor(floor_w), 
        .o_report_dir (dir_w) 
    );
//****TB에서 주석 시작****/
 elevator_display_controller i_display ( 
         .current_floor (floor_w),
         .report_dir    (dir_w),
         .HEX7_O        (HEX7),
         .HEX6_O        (HEX6),
         .HEX5_O        (HEX5),
         .HEX4_O        (HEX4),
         .HEX3_O        (HEX3),
         .HEX2_O        (HEX2),
         .HEX1_O        (HEX1),
         .HEX0_O        (HEX0)
       );
 //****TB에서 주석 ****/

  // --- TB용 출력 연결 ---
   // assign CURRENT_FLOOR = floor_w;
   // assign CURRENT_DIR   = dir_w;
    // --- TB용 출력 연결 끝 ---

endmodule