import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
import serial
import serial.tools.list_ports
import threading
import re
import time
import queue  

#엘리베이터 층 수 
MAX_FLOOR = 32
START_FLOOR = 1

#GUI 사이즈
CANVAS_WIDTH = 150
CANVAS_HEIGHT = 400
FLOOR_HEIGHT = CANVAS_HEIGHT / (MAX_FLOOR + 1)
CAR_WIDTH = CANVAS_WIDTH * 0.6
SHAFT_X_START = (CANVAS_WIDTH - CAR_WIDTH) / 2
SHAFT_X_END = SHAFT_X_START + CAR_WIDTH

#LED 매트릭스 설정
LED_ROWS = 11
LED_COLS = 7
LED_CELL = 16           #점 사이 간격
LED_MARGIN = 10         #바깥 여백
LED_RADIUS = 5          #점 반지름
LED_BG = "#0c0c0c"
LED_OFF = "#222222"
LED_ON = "#ffa500"      #주황색 LED
LED_OUTLINE = "#4a4a4a"
LED_SPEED_MS = 120      #움직이는 속도(작을수록 빠름)


class ElevatorGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Elevator Controller GUI")
        self.root.geometry("800x650") #켰을때 창크기

        self.serial_port = serial.Serial()
        self.is_connected = False
        self.read_thread = None
        self.gui_queue = queue.Queue()
        #현재 층 상태
        self.current_floor = START_FLOOR

        #LED 상태
        self.dir_state = "STOP"           # "UP" | "DOWN" | "STOP"
        self.led_canvas = None
        self.led_dots = []              
        self.led_anim_job = None
        self.led_anim_frame = 0

        self.create_widgets()
        self.refresh_ports()
        self.draw_elevator_shaft()

        self.set_led_state("STOP")

        #차내콜 키패드 초기화
        self.keypad_expanded = False
        self.keypad_input = ""
        self.build_keypad_panel()
        self.process_queue()

    def create_widgets(self):
        top_frame = ttk.Frame(self.root, padding="10")
        top_frame.pack(fill='x')
        ttk.Label(top_frame, text="포트:").pack(side='left', padx=5)
        self.port_combobox = ttk.Combobox(top_frame, width=15, state='readonly')
        self.port_combobox.pack(side='left', padx=5)
        self.refresh_button = ttk.Button(top_frame, text="새로고침", command=self.refresh_ports)
        self.refresh_button.pack(side='left', padx=5)
        self.connect_button = ttk.Button(top_frame, text="연결", command=self.connect)
        self.connect_button.pack(side='left', padx=5)
        self.disconnect_button = ttk.Button(top_frame, text="연결 해제", command=self.disconnect, state='disabled')
        self.disconnect_button.pack(side='left', padx=5)
        self.status_label = ttk.Label(top_frame, text="연결 안됨", foreground='red', anchor='e')
        self.status_label.pack(side='right', fill='x', expand=True, padx=10)

        #엘리베이터 GUI + LED 방향 표시
        middle_frame = ttk.Frame(self.root, padding="10")
        middle_frame.pack(fill='y', expand=True)
        ttk.Label(middle_frame, text="엘리베이터 현황", font=("Arial", 12)).pack()

        display_frame = ttk.Frame(middle_frame)
        display_frame.pack(pady=10)

        # LED 매트릭스
        self.create_led_panel(display_frame)

        #엘리베이터 샤프트
        self.canvas = tk.Canvas(display_frame, width=CANVAS_WIDTH, height=CANVAS_HEIGHT, bg='lightgrey', highlightthickness=0)
        self.canvas.pack(side='right', padx=(10, 0))

        #입출력 프레임
        bottom_frame = ttk.Frame(self.root, padding="10")
        bottom_frame.pack(fill='both', expand=True)
        #입력
        left_frame = ttk.Frame(bottom_frame, padding="5")
        left_frame.pack(side='left', fill='both', expand=True, padx=10)
        ttk.Label(left_frame, text="명령 입력 (예: 5UP, C3, 1DOWN)").pack(anchor='w')
        self.command_entry = ttk.Entry(left_frame, width=40)
        self.command_entry.pack(fill='x', expand=True, pady=5)
        self.command_entry.bind("<Return>", self.send_command) # 엔터키 바인딩
        self.send_button = ttk.Button(left_frame, text="전송", command=self.send_command, state='disabled')
        self.send_button.pack(anchor='e', pady=5)
        #출력
        right_frame = ttk.Frame(bottom_frame, padding="5")
        right_frame.pack(side='right', fill='both', expand=True, padx=10)
        ttk.Label(right_frame, text="시리얼 출력 로그").pack(anchor='w')
        self.output_text = scrolledtext.ScrolledText(right_frame, height=10, width=50, state='disabled')
        self.output_text.pack(fill='both', expand=True, pady=5)

    #LED 패널 생성/업뎃
    def create_led_panel(self, parent):
        w = LED_COLS * LED_CELL + LED_MARGIN * 2
        h = LED_ROWS * LED_CELL + LED_MARGIN * 2
        self.led_canvas = tk.Canvas(parent, width=w, height=h, bg=LED_BG, highlightthickness=0)
        self.led_canvas.pack(side='left', padx=(0, 10))

        #원 생성
        self.led_dots = []
        for r in range(LED_ROWS):
            row = []
            for c in range(LED_COLS):
                cx = LED_MARGIN + c * LED_CELL
                cy = LED_MARGIN + r * LED_CELL
                oid = self.led_canvas.create_oval(
                    cx - LED_RADIUS, cy - LED_RADIUS, cx + LED_RADIUS, cy + LED_RADIUS,
                    fill=LED_OFF, outline=LED_OUTLINE
                )
                row.append(oid)
            self.led_dots.append(row)

    def set_led_state(self, direction):
        #방향 상태 업데이트 및 제어
        direction = (direction or "STOP").upper()
        if direction in ("IDLE", "HOLD"):
            direction = "STOP"

        if self.led_anim_job:
            self.root.after_cancel(self.led_anim_job)
            self.led_anim_job = None

        self.dir_state = direction
        self.led_anim_frame = 0

        if direction in ("UP", "DOWN"):
            self.animate_led()
        else:
            #STOP - 고정 표시
            pattern = self.get_dash_pattern()
            self.render_led(pattern)

    def animate_led(self):
        if self.dir_state not in ("UP", "DOWN"):
            return
        base = self.get_arrow_pattern(self.dir_state)
        pattern = self.shift_pattern(base, self.led_anim_frame, self.dir_state)
        self.render_led(pattern)
        self.led_anim_frame = (self.led_anim_frame + 1) % LED_ROWS
        self.led_anim_job = self.root.after(LED_SPEED_MS, self.animate_led)

    def render_led(self, pattern_matrix):
        #pattern_matrix1이면 켜짐
        for r in range(LED_ROWS):
            row = pattern_matrix[r]
            for c in range(LED_COLS):
                on = row[c] == '1'
                color = LED_ON if on else LED_OFF
                self.led_canvas.itemconfig(self.led_dots[r][c], fill=color)

    def get_arrow_pattern(self, direction):
        #11x7
        up = [
            "...1...",
            "..111..",
            ".1.1.1.",
            "1111111",
            "...1...",
            "...1...",
            "...1...",
            "...1...",
            "...1...",
            "...1...",
            "...1...",
        ]
        if direction == "UP":
            return up
        else:
            return list(reversed(up))  # DOWN

    def get_dash_pattern(self):
        rows = ["." * LED_COLS for _ in range(LED_ROWS)]
        mid = LED_ROWS // 2
        bar = "." + "1" * (LED_COLS - 2) + "."
        rows[mid] = bar
        return rows

    def shift_pattern(self, base_rows, offset, direction):
        rows = len(base_rows)
        out = []
        for r in range(rows):
            if direction == "UP":
                src = (r + offset) % rows
            else:  # DOWN
                src = (r - offset) % rows
            out.append(base_rows[src])
        return out

    #엘리베이터 GUI 그리기
    def get_floor_y(self, floor):
        return CANVAS_HEIGHT - (floor * FLOOR_HEIGHT)
    def draw_elevator_shaft(self):
        self.canvas.create_rectangle(SHAFT_X_START, 0, SHAFT_X_END, CANVAS_HEIGHT, fill='white')
        for floor in range(1, MAX_FLOOR + 1):
            y = self.get_floor_y(floor)
            self.canvas.create_line(0, y, CANVAS_WIDTH, y, fill='grey')
            self.canvas.create_text(SHAFT_X_START / 2, y - (FLOOR_HEIGHT/2), text=str(floor))
        y_pos = self.get_floor_y(self.current_floor)
        self.elevator_car = self.canvas.create_rectangle(
            SHAFT_X_START, y_pos - FLOOR_HEIGHT, 
            SHAFT_X_END, y_pos, 
            fill='blue', outline='black'
        )
        self.canvas.itemconfig(self.elevator_car)
    def update_elevator_display(self, new_floor):
        if new_floor < 1 or new_floor > MAX_FLOOR: return
        self.current_floor = new_floor
        new_y_pos = self.get_floor_y(new_floor)
        self.canvas.coords(
            self.elevator_car,
            SHAFT_X_START, new_y_pos - FLOOR_HEIGHT,
            SHAFT_X_END, new_y_pos
        )
        self.canvas.update()

    #시리얼 통신
    def refresh_ports(self):
        ports = [port.device for port in serial.tools.list_ports.comports()]
        self.port_combobox['values'] = ports
        if ports:
            self.port_combobox.current(0)

    def connect(self):
        selected_port = self.port_combobox.get()
        if not selected_port:
            messagebox.showerror("오류", "COM 포트를 선택하세요.")
            return
        try:
            self.serial_port = serial.Serial(selected_port, 115200, timeout=1)
            time.sleep(1) 
            self.is_connected = True
            
            #연결 시 큐 초기화
            while not self.gui_queue.empty():
                try: self.gui_queue.get_nowait()
                except queue.Empty: break
            
            self.read_thread = threading.Thread(target=self.read_serial_data, daemon=True)
            self.read_thread.start()
            self.status_label.config(text=f"{selected_port} 연결됨", foreground='green')
            self.connect_button.config(state='disabled')
            self.disconnect_button.config(state='normal')
            self.send_button.config(state='normal')
        except Exception as e:
            messagebox.showerror("연결 실패", str(e))

    def disconnect(self):
        """시리얼 연결을 해제합니다."""
        if self.is_connected:
            self.is_connected = False
            if self.read_thread:
                self.read_thread.join(timeout=1) 
            if self.serial_port.is_open:
                self.serial_port.close()
        
        #큐에 상태 메시지 전송
        self.gui_queue.put(("status", "연결 안됨"))
        #LED STOP
        self.set_led_state("STOP")

    def read_serial_data(self):
        while self.is_connected:
            try:
                if self.serial_port.in_waiting > 0:
                    line = self.serial_port.readline().decode('ascii').strip()
                    if line:
                        self.gui_queue.put(("serial", line))
            except Exception as e:
                if self.is_connected: 
                    #에러 발생 시 큐에 상태 메시지
                    self.gui_queue.put(("status", "연결 끊김 (오류)"))
                break
                
    def process_queue(self):
        try:
            while True:
                #큐에서 작업을 꺼냄
                source, data = self.gui_queue.get_nowait()
                
                if source == "serial":
                    #시리얼 데이터 처리
                    self.handle_received_data(data)
                elif source == "user":
                    #사용자 입력 로그 처리
                    self.display_output(data)
                elif source == "status":
                    #연결 상태 처리
                    if data == "연결 안됨" or data == "연결 끊김 (오류)":
                        self.status_label.config(text=data, foreground='red')
                        self.connect_button.config(state='normal')
                        self.disconnect_button.config(state='disabled')
                        self.send_button.config(state='disabled')

        except queue.Empty:
            pass
        finally:
            self.root.after(100, self.process_queue)

    def handle_received_data(self, data):
        #출력 로그에 표시
        self.display_output(data)
        
        #데이터 파싱 및 엘리베이터 GUI/LED 업데이트
        m = re.search(r"F:(\d+)(?:.*?DIR:(\w+))?", data, re.IGNORECASE)
        if m:
            try:
                floor_num = int(m.group(1))
                # DIR이 없는 경우 None
                dir_word = m.group(2).upper() if m.group(2) else None

                #없으면 층 변화로 추정
                if not dir_word:
                    if floor_num > self.current_floor:
                        dir_word = "UP"
                    elif floor_num < self.current_floor:
                        dir_word = "DOWN"
                    else:
                        dir_word = "STOP"

                self.update_elevator_display(floor_num)
                self.set_led_state(dir_word)
            except Exception as e:
                self.display_output(f"[GUI 파싱 오류] {e}")

    def display_output(self, message):
        self.output_text.config(state='normal') 
        self.output_text.insert(tk.END, message + "\n")
        self.output_text.see(tk.END) 
        self.output_text.config(state='disabled') 

    #우측 확장 키패드
    def build_keypad_panel(self):
        #토글 버튼
        self.expand_btn = ttk.Button(self.root, text="◀", width=2, command=self.toggle_keypad)
        self.expand_btn.place(relx=1.0, rely=0.5, anchor='e')

        #키패드 패널
        self.keypad_width = 230
        self.keypad_frame = tk.Frame(self.root, bg="#121212", bd=2, relief='ridge')

        #상단 헤더(제목 + 닫기 버튼)
        header = tk.Frame(self.keypad_frame, bg="#121212")
        header.pack(fill='x', padx=8, pady=(8, 0))

        title = tk.Label(header, text="차내 호출 패널", bg="#121212", fg="#dddddd",
                         font=("Arial", 11, "bold"))
        title.pack(side='left')

        #확장된 패널 닫기
        self.keypad_close_btn = tk.Button(
            header, text="✕", command=self.close_keypad,
            bg="#1f1f1f", fg="#ffb3b3", bd=0,
            activebackground="#3a3a3a", activeforeground="#ffffff",
            padx=6, pady=2
        )
        self.keypad_close_btn.pack(side='right')

        #입력 디스플레이
        self.keypad_display = tk.Label(
            self.keypad_frame,
            text="",
            anchor='e',
            width=10,
            font=("Arial", 20, "bold"),
            bg="#0c0c0c",
            fg=LED_ON,
            padx=12, pady=10
        )
        self.keypad_display.pack(fill='x', padx=12, pady=(0, 10))

        #버튼 스타일
        def make_btn(parent, text, cmd, bg="#1e1e1e", fg="#ffffff"):
            return tk.Button(
                parent, text=text, command=cmd,
                width=4, height=2,
                bg=bg, fg=fg,
                activebackground="#3a3a3a", activeforeground="#ffffff",
                relief='raised', bd=5,
                highlightthickness=2, highlightbackground="#555555"
            )

        #키배치
        keys = [
            ["7", "8", "9"],
            ["4", "5", "6"],
            ["1", "2", "3"],
            ["del", "0", "enter"],
        ]
        grid = tk.Frame(self.keypad_frame, bg="#121212")
        grid.pack(padx=12, pady=8)

        for r, row in enumerate(keys):
            for c, label in enumerate(row):
                if label.isdigit():
                    btn = make_btn(
                        grid, label,
                        lambda d=label: self.keypad_input_digit(d),
                        bg="#1f1f1f", fg="#000000"
                    )
                elif label == "del":
                    btn = make_btn(
                        grid, "DEL",
                        self.keypad_delete,
                        bg="#4a1f1f", fg="#000000"
                    )
                else:  # enter
                    btn = make_btn(
                        grid, "ENTER",
                        self.keypad_enter,
                        bg="#1f3a1f", fg="#000000"
                    )
                btn.grid(row=r, column=c, padx=6, pady=6, sticky="nsew")

        #그리드 확장성
        for i in range(3):
            grid.columnconfigure(i, weight=1)
        for i in range(4):
            grid.rowconfigure(i, weight=1)
        self.expand_btn.lift()#(초기 상태에선 토글 버튼만 보임)

    def toggle_keypad(self):
        # 접힘 -> 펼침
        if not self.keypad_expanded:
            self.keypad_frame.place(relx=1.0, rely=0.5, anchor='e', width=self.keypad_width)
            #패널이 펼쳐지면 토글 버튼 숨김(키패드 가림 방지)
            self.expand_btn.place_forget()
            self.keypad_expanded = True
        else:
            self.close_keypad()

    def close_keypad(self):
        #X 버튼으로 닫기
        self.keypad_frame.place_forget()
        self.keypad_expanded = False
        #토글 버튼 다시 표시
        self.expand_btn.place(relx=1.0, rely=0.5, anchor='e')
        self.expand_btn.lift()

    def update_keypad_display(self):
        self.keypad_display.config(text=self.keypad_input)

    def keypad_input_digit(self, d):
        #MAX_FLOOR=32 기준
        if len(self.keypad_input) >= 2:
            return
        if self.keypad_input == "" and d == "0":
            self.keypad_input = "0"
        else:
            if self.keypad_input == "0":
                self.keypad_input = d 
            else:
                self.keypad_input += d
        self.update_keypad_display()

    def keypad_delete(self):
        #전체 삭제
        self.keypad_input = ""
        self.update_keypad_display()

    def keypad_enter(self):
        digits = self.keypad_input.strip()
        if not digits:
            return
        try:
            num = int(digits)
        except ValueError:
            messagebox.showwarning("입력 오류", "숫자를 입력하세요.")
            return

        if not (START_FLOOR <= num <= MAX_FLOOR):
            messagebox.showwarning("범위 오류", f"{START_FLOOR} ~ {MAX_FLOOR}층만 호출 가능합니다.")
            return

        #전송: C{digits}
        self.send_car_call(digits)
        #전송 후 표시 초기화
        self.keypad_input = ""
        self.update_keypad_display()

    def send_car_call(self, digits):
        if self.is_connected and self.serial_port.is_open:
            try:
                payload = f"C{digits}"
                self.serial_port.write(payload.encode('ascii') + b'\r')
                self.gui_queue.put(("user", f">> {payload}"))
            except Exception as e:
                self.gui_queue.put(("user", f"[전송 오류] {e}"))
        else:
            messagebox.showwarning("오류", "먼저 시리얼 포트에 연결하세요.")

    def send_command(self, event=None):
        text = self.command_entry.get().strip()
        if not text:
            return

        if not (self.is_connected and self.serial_port.is_open):
            messagebox.showwarning("오류", "먼저 시리얼 포트에 연결하세요.")
            return

        payload = None

        m = re.fullmatch(r'(?:C)?(\d{1,2})', text, re.IGNORECASE)
        if m:
            num = int(m.group(1))
            if not (START_FLOOR <= num <= MAX_FLOOR):
                messagebox.showwarning("범위 오류", f"{START_FLOOR} ~ {MAX_FLOOR}층만 호출 가능합니다.")
                return
            payload = f"C{num}"
        else:
            m2 = re.fullmatch(r'(\d{1,2})(UP|DOWN)', text, re.IGNORECASE)
            if m2:
                num = int(m2.group(1))
                if not (START_FLOOR <= num <= MAX_FLOOR):
                    messagebox.showwarning("범위 오류", f"{START_FLOOR} ~ {MAX_FLOOR}층만 호출 가능합니다.")
                    return
                payload = f"{num}{m2.group(2).upper()}"
            else:
                payload = text.upper()

        try:
            self.serial_port.write(payload.encode('ascii') + b'\r')
            self.gui_queue.put(("user", f">> {payload}"))
        except Exception as e:
            self.gui_queue.put(("user", f"[전송 오류] {e}"))
        finally:
            self.command_entry.delete(0, tk.END)

    def on_closing(self):
        self.disconnect()
        if self.led_anim_job:
            try:
                self.root.after_cancel(self.led_anim_job)
            except Exception:
                pass
            self.led_anim_job = None
        # 큐 처리가 완료될 시간을 약간(110ms) 준다
        self.root.after(110, self.root.destroy)
if __name__ == "__main__":
    root = tk.Tk()
    app = ElevatorGUI(root)
    
    root.protocol("WM_DELETE_WINDOW", app.on_closing)
    
    root.mainloop()
