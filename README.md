# 🛗 FPGA Elevator Controller

This project implements an Elevator Control System using Verilog HDL on an Altera DE2 FPGA board. The system features a Finite State Machine (FSM) based controller, UART communication for remote commands, and real-time status display on 7-segment LEDs.

## 📌 Overview

* **Platform**: Altera DE2 Board (Cyclone II)
* **Language**: Verilog HDL
* **Tools**: Quartus II, ModelSim
* **Key Features**:
    * **FSM Control**: Comprehensive logic for moving Up/Down, Door operations, and Emergency stops.
    * **UART Interface**: Remote control and status monitoring via PC serial terminal (PuTTY, etc.).
    * **Debouncing**: Reliable button input processing with a 10ms stability check.
    * **Visual Feedback**: Real-time display of the current floor and status (STOP, UP, DOWN, OPEN, CLOSE).

## 🏗 System Architecture

The system is organized into the following modules:

1.  **`ELEVATOR_TOP.v`**: The top-level module connecting all sub-modules.
2.  **`elevator_controller.v`**: The main logic unit containing the FSM and registers. It handles call scheduling, timer management, and state transitions.
3.  **`UART_RX.v`**: Receives serial data (115200 baud), buffers inputs, and parses commands (e.g., `5UP`, `C3`).
4.  **`UART_TX.v`**: Transmits the elevator's current floor and direction status back to the PC (e.g., `F:01, DIR:STOP`).
5.  **`debouncer.v`**: Eliminates mechanical switch bouncing noise (wait time: 10ms at 50MHz clock).
6.  **`Display_Controller`**: Controls the 7-segment displays to show floor numbers and status text.

## 🔄 Finite State Machine (FSM)

The controller operates based on a specific state diagram:

* **`S_IDLE_STOP`**: Stationary state waiting for calls.
* **`S_MOVING_UP` / `S_MOVING_DOWN`**: Moving towards the target floor.
* **`S_DOOR_OPEN`**: Door opens upon arrival (clears the call request).
* **`S_DWELL`**: Waits for a set time while the door is open.
* **`S_DOOR_CLOSE`**: Door closes before departure.
* **`S_EMG_STOP`**: Emergency stop state triggered by hardware switch.

**Scheduling Logic**:
* The system checks for `any_call_above` and `any_call_below` to determine the next direction.
* **Stop Logic**: Determines if the car should stop at the current floor based on hall calls, car calls, and direction.

## 🎮 Hardware Control (DE2 Board)

The FPGA switches and keys are mapped to specific elevator functions:

| Component | Label | Function | Description |
| :--- | :--- | :--- | :--- |
| **Switch** | `SW17` | **RST_N** | System Reset (Active Low) |
| **Switch** | `SW01` | **EMG_STOP** | Emergency Stop Mode |
| **Switch** | `SW00` | **TX_STOP** | Pause UART Transmission |
| **Button** | `KEY1` | **OPEN** | Hold Door Open |
| **Button** | `KEY2` | **CLOSE** | Force Door Close |
| **LED** | `LEDR17` | **UP** | Indicator for upward movement |
| **LED** | `LEDR6` | **DOWN** | Indicator for downward movement |

## 📡 UART Communication

Connect the DE2 board to a PC to control the elevator remotely.

**Configuration**:
* **Baud Rate**: 115200
* **Data Bits**: 8
* **Stop Bit**: 1
* **Parity**: None

**Command Protocol**:
* **Input (PC -> FPGA)**:
    * `[Floor]UP`: Hall call UP (e.g., `5UP`)
    * `[Floor]DOWN`: Hall call DOWN (e.g., `1DOWN`)
    * `C[Floor]`: Car call (e.g., `C3`)
* **Output (FPGA -> PC)**:
    * Format: `F:[Floor], DIR:[State]`
    * Example: `F:01, DIR:STOP`

## 📂 Simulation & Verification

The project includes test results for:
* **Debouncer**: Verification of signal stability over 10ms.
* **UART**: Verification of start/stop bit timing and data parsing.
* **System Logic**: Verification of floor transitions and FSM states.
