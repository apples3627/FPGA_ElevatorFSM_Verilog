module debouncer (
    input CLK,
    input RST_N,
    input btn_in,   
    output reg btn_out 
);
    parameter CLK_FREQ = 50_000_000;
    // 10ms(50MHz * 0.01)
    parameter DB_TARGET = 500_000; 

    reg [19:0] db_cnt;
    reg btn_sync1, btn_sync2, btn_stable;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            btn_sync1 <= 0;
            btn_sync2 <= 0;
            btn_stable <= 0;
            db_cnt <= 0;
            btn_out <= 0;
        end else begin
            btn_sync1 <= btn_in;
            btn_sync2 <= btn_sync1;
            // 상태 변경 감지 및 카운터
            if (btn_sync2 != btn_stable) begin
                db_cnt <= db_cnt + 20'b1; // 상태가 다르면 카운트 시작
            
                if (db_cnt == DB_TARGET - 1) begin
                    btn_stable <= btn_sync2; 
                    db_cnt <= 0;
                end
            end else begin
                db_cnt <= 0; // 상태가 같으면 카운터 리셋
            end

            //출력
            btn_out <= btn_stable;
        end
    end

endmodule