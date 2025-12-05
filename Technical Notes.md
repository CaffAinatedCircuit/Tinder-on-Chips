# Dating in Silicon – Technical Notes

> Obsidian note summarizing the architecture, design goals, and concepts exercised by the **Dating in Silicon** FPGA project.

---

## Overview

This project implements a toy “social” system on an FPGA where multiple compute nodes (“persons”) work on scheduled tasks and, when free, attempt to “date” each other through a structured set of hardware protocols. At its core, it is a **multi-agent SoC micro-architecture** that stresses scheduling, inter-node communication, error monitoring, and simplified thermal modeling. FPGAs are a natural fit for this kind of architecture exploration because they support parallel, fine-grained control over scheduling, routing, and on-chip monitoring logic.[arxiv](https://arxiv.org/pdf/2304.03044.pdf)​

The design is fully RTL-driven in Verilog-2001, with flattened buses for multi-node signals, making it compatible with typical industrial flows and simulators such as Vivado xSim.[semanticscholar](https://www.semanticscholar.org/paper/2fe16f01c975f6fe93bf28b2970ab29d33aabadf)​

---

## Architectural Blocks

<img src="images/Arch.png" alt="Simulation Waveform" width="800"/>
### Top-level: `silicon_dating_top`

- Parameters:
    
    - `N_NODES`: number of person nodes.
        
    - `ID_W`: width of node IDs.
        
    - `PREF_W`: width of preference vectors.
        
- Responsibilities:
    
    - Instantiates:
        
        - `task_master`
            
        - `cupid_core`
            
        - `wormhole_fabric`
            
        - `person_node[0..N_NODES-1]`
            
    - Routes:
        
        - Task signals: `task_valid`, `task_alt_rate`, `task_done`.
            
        - Dating control: `free_to_cupid`, `dating_busy`, `couple_locked`.
            
        - Flattened config/telemetry buses between nodes and Cupid.
            
        - Wormhole data buses between nodes and fabric.
            
<img src="images/wave_synthesis.png" alt="Simulation Waveform" width="800"/>
### Task Master: `task_master`

- Emulates a **global OS-like scheduler**:
    
    - Periodically issues tasks to each node.
        
    - Uses a global counter plus per-node offsets to stagger issue times.
        
    - Uses `task_alt_rate` to alternate between “short” and “long” jobs, thus modulating **load and idle time** per node.
        
- Conceptually tests:
    
    - Interaction between **workload scheduling** and cooperative behavior (dating).
        
    - How imbalance (one node busy, partner idle) can trigger relationship breakups.
        

### Matchmaker: `cupid_core`

- Central policy engine that:
    
    - Watches node states (`free_from_node`, `dating_busy_from_node`, `couple_locked_from_node`).
        
    - Consumes telemetry:
        
        - `clk_est` (effective clock “personality”).
            
        - `temp_est` (temperature proxy).
            
        - `latency_est` (abstract “distance” on the interconnect).
            
        - `error_counters`, `node_dating_status`.
            
    - Picks pairs using simple compatibility heuristics:
        
        - Both nodes must be free and not already coupled.
            
        - Latency difference must be below a threshold.
            
        - Temperature or other heuristics can be mixed in.
            
    - Assigns:
        
        - `partner_id_to_node` for each node.
            
        - `initiator_flag_to_node` to declare one node initiator.
            
        - `route_dst_id` so the wormhole fabric knows where to send packets.
            
- Also:
    
    - Records breakup reasons (`PRE_FAIL`, `DATE_FAIL`, `ERROR_BREAK`).
        
    - Can be extended to learn from history for future pairings (e.g., avoiding toxic pairs).
        

### Communication Fabric: `wormhole_fabric`

- Implements a **simple single-clock routing network**:
    
    - Each node exposes:
        
        - `wh_tx_data`, `wh_tx_valid`, `wh_tx_ready`.
            
        - `wh_rx_data`, `wh_rx_valid`, `wh_rx_ready`.
            
    - Data width: `DATA_W = ID_W + PREF_W` (ID + preference vector).
        
    - Uses `route_dst_id` from Cupid to decide the destination node for each source packet.
        
- Concepts:
    
    - Basic **wormhole-style routing** (one word at a time, direct mapping).
        
    - Backpressure via `*_ready`/`*_valid` handshakes.
        
    - Structure is deliberately written to be replaceable by:
        
        - A proper **asynchronous FIFO-based fabric** for realistic clock-domain crossing experiments.[ieeexplore.ieee](https://ieeexplore.ieee.org/document/10533170/)
        - 

<img src="images/wave_synthesis.png" alt="Simulation Waveform" width="800"/>

### Person Nodes: `person_node`

- Each node encapsulates:
    
    - A **work FSM**:
        
        - Starts jobs when `task_valid` is high and node is not dating/coupled.
            
        - Counts cycles for short/long jobs, asserts `task_done` at completion.
            
    - A **dating FSM**:
        
        - States: `IDLE`, `PRE_SEND`, `PRE_RECV`, `DATING`, `COUPLED`.
            
        - Uses Cupid’s `partner_id_cupid` and `pair_valid_cupid` to start pre-dating.
            
        - As initiator:
            
            - Sends `{MY_ID, my_pref}` through wormhole.
                
        - As responder:
            
            - Receives `{ID, pref}`, XORs it with own `my_pref`, computes popcount.
                
            - If preferences too different, sets `PRE_FAIL` and returns to `IDLE`.
                
        - If pre-date is successful:
            
            - Enters `DATING`.
                
            - Tracks:
                
                - `dating_cnt` (how long they’ve been together).
                    
                - `free_wait_cnt` (to model one partner idling too long while the other works).
                    
                - `error_counters` (incremented when temp/latency rules are violated).
                    
            - Breakup conditions:
                
                - Load imbalance (long free_wait).
                    
                - Too many errors (e.g., hot/cold or latency incompatibility).
                    
            - Success condition:
                
                - Survive `DATE_LEN` cycles without breakup → set `couple_locked`.
                    
    - Telemetry generation:
        
        - `clk_est`: simple static offset per node, as a proxy for local timing characteristics.
            
        - `temp_est`: increments when working or dating, decrements when idle (toy thermal model).
            
        - `latency_est`: pseudo-distance; could be wired to NoC metrics in future.
            
        - `error_counters`: hardware-friendly “quality-of-relationship” score.
            

---

## Digital Design and Architecture Concepts Covered

### 1. Scheduling and Resource Management

- **Task-level scheduling:**
    
    - Centralized scheduler issuing periodically staggered jobs.
        
    - Models real SoC firmware/RTOS behavior where compute units alternate between load and idle.
        
- **Workload interference with cooperation:**
    
    - Breakup due to free_wait models cases where one core is heavily loaded while another sits idle—useful for thinking about **fair scheduling and co-scheduling policies**.
        

### 2. Communication and Handshaking

- **Credit-style ready/valid handshake**:
    
    - Between persons and wormhole, ensuring safe single-word transfers.
        
- **Routing and addressing:**
    
    - Use of IDs and routing tables (`route_dst_id_flat`) to steer packets.
        
- Future extension:
    
    - Drop-in replacement with multi-hop, buffered NoC or asynchronous FIFOs.
        

### 3. Clocking, Thermal Behavior, and Reliability

- Even in the simplified single-clock prototype, the project:
    
    - Separates conceptual `clk_task` and `clk_async` domains to prepare for true multi-clock expansions.
        
    - Encourages thinking about **clock-domain crossing (CDC)** and how async FIFOs are used to safely bridge unrelated clocks.[ieeexplore.ieee](https://ieeexplore.ieee.org/document/10533170/)​
        
- Thermal modeling:
    
    - Simple `temp_est` counter mimics dynamic thermal behavior and its impact on protocol success.
        
- Reliability:
    
    - Error counters emulate link quality and protocol robustness.
        
    - Breakup on “signal issues” mimics CRC/BER thresholds in real digital links.
        

### 4. State Machines and Protocol Design

- Each `person_node` contains:
    
    - A cleanly separable **work FSM** and **dating FSM**.
        
    - An explicit “pre-date” phase for preference exchange and compatibility check.
        
- `cupid_core` implements:
    
    - A **multi-agent matching policy** over arrays of node state and telemetry.
        
    - Simple heuristic scoring (latency and temp rules) that can be upgraded to more sophisticated metrics.
        

### 5. Verification and Story-driven Testbench

- The testbench:
    
    - Uses hierarchical references to internal flattened buses.
        
    - Monitors events and prints a **human-readable narrative**: lobby entries, date starts, breakups, thermal warnings, end-of-day summary.
        
- This demonstrates:
    
    - How to use `$display` and state-diff logic to build **semantic monitors** that tell a story instead of just dumping numbers.
        
    - A pattern you can reuse for more serious designs where you want logs that read like protocol traces or transaction histories, not just bit flips.
        

---

## Test bench
The testbench acts like a narrator sitting on top of the RTL, watching key signals and printing a story as the simulation runs.[acm](https://dl.acm.org/doi/pdf/10.1145/3622805)
A Picture speaks 1000 words​
<img src="images/TB explained.png" alt="Testbench" width="800"/>
### What the testbench does

- **Drives clock and reset:**  
    It creates a 100 MHz `clk` and a reset pulse, then starts the design running under `xsim` for 1000 ns.
    
- **Instantiates the DUT:**  
    It brings up `silicon_dating_top` with `task_master`, `cupid_core`, `wormhole_fabric`, and four `person_node` instances connected exactly as in your RTL.
    
- **Monitors internal signals via hierarchy:**  
    Using `uut.free_to_cupid`, `uut.pair_valid_to_node`, `uut.dating_busy`, `uut.couple_locked`, flattened partner IDs, and temperature fields, it compares the current values to their previous values every clock and detects events like:
    
    - A node becoming free and entering the lobby.
        
    - Cupid issuing a `pair_valid` with a new partner.
        
    - A node entering `dating_busy`.
        
    - A breakup reason appearing in `node_dating_status_flat`.
        
    - A node’s `temp_est` crossing the “hot” threshold.
        
- **Prints a human-readable log:**  
    On each detected event, it calls `$display` with a time-stamped sentence (e.g. “Node 0 has left the lobby and gone on a date with Node 1” or “Node 3 is running hot at temp=90 while dating. Sparks are literally flying.”), turning low‑level signal transitions into the continuous story you pasted.
    
- **Ends the run cleanly:**  
    After 1 µs simulated time, it prints a final line summarizing the number of coupled nodes (from `debug_leds`) and calls `$finish`, which is what Vivado reports at the end of the log.
```
Starting static elaboration
Completed static elaboration
Starting simulation data flow analysis
Completed simulation data flow analysis
Time Resolution for simulation is 1ps
Compiling module xil_defaultlib.task_master
Compiling module xil_defaultlib.cupid_core_default
Compiling module xil_defaultlib.wormhole_fabric_default
Compiling module xil_defaultlib.person_node_default
Compiling module xil_defaultlib.person_node(ID=1)
Compiling module xil_defaultlib.person_node(ID=2)
Compiling module xil_defaultlib.person_node(ID=3)
Compiling module xil_defaultlib.silicon_dating_top_default
Compiling module xil_defaultlib.tb_silicon_dating_story
Compiling module xil_defaultlib.glbl
Built simulation snapshot tb_silicon_dating_story_behav
INFO: [USF-XSim-69] 'elaborate' step finished in '2' seconds
INFO: [USF-XSim-4] XSim::Simulate design
INFO: [USF-XSim-61] Executing 'SIMULATE' step in 'C:/Users/RISHIK NAIR/Downloads/To-do/Silicon_dating/Silicon_dating.sim/sim_1/behav/xsim'
INFO: [USF-XSim-98] *** Running xsim
   with args "tb_silicon_dating_story_behav -key {Behavioral:sim_1:Functional:tb_silicon_dating_story} -tclbatch {tb_silicon_dating_story.tcl} -log {simulate.log}"
INFO: [USF-XSim-8] Loading simulator feature
Vivado Simulator 2018.2
Time resolution is 1 ps
source tb_silicon_dating_story.tcl
# set curr_wave [current_wave_config]
# if { [string length $curr_wave] == 0 } {
#   if { [llength [get_objects]] > 0} {
#     add_wave /
#     set_property needs_save false [current_wave_config]
#   } else {
#      send_msg_id Add_Wave-1 WARNING "No top level signals found. Simulator will start without a wave window. If you want to open a wave window go to 'File->New Waveform Configuration' or type 'create_wave_config' in the TCL console."
#   }
# }
# run 1000ns
Time 50000: The silicon city awakens. 4 nodes are ready for work and maybe love.
Time 55000: Node 0 finishes its task and walks into the dating lobby (free_to_cupid=1).
Time 55000: Node 1 finishes its task and walks into the dating lobby (free_to_cupid=1).
Time 55000: Node 2 finishes its task and walks into the dating lobby (free_to_cupid=1).
Time 55000: Node 3 finishes its task and walks into the dating lobby (free_to_cupid=1).
Time 65000: Cupid whispers to Node 0: 'How about you meet Node 1?' (pair_valid).
Time 65000: Cupid whispers to Node 1: 'How about you meet Node 0?' (pair_valid).
Time 75000: Node 0 has left the lobby and gone on a date with Node 1.
Time 75000: Node 1 has left the lobby and gone on a date with Node 0.
Time 85000: Cupid whispers to Node 2: 'How about you meet Node 3?' (pair_valid).
Time 85000: Cupid whispers to Node 3: 'How about you meet Node 2?' (pair_valid).
Time 95000: Node 2 has left the lobby and gone on a date with Node 3.
Time 95000: Node 3 has left the lobby and gone on a date with Node 2.
Time 245000: Signal issues: Node 1 sees too many errors while talking to Node 0. They call it off.
Time 255000: Node 1 finishes its task and walks into the dating lobby (free_to_cupid=1).
Time 265000: Signal issues: Node 3 sees too many errors while talking to Node 2. They call it off.
Time 275000: Node 3 finishes its task and walks into the dating lobby (free_to_cupid=1).
Time 285000: Cupid whispers to Node 1: 'How about you meet Node 3?' (pair_valid).
Time 285000: Cupid whispers to Node 3: 'How about you meet Node 1?' (pair_valid).
Time 295000: Node 1 has left the lobby and gone on a date with Node 3.
Time 295000: Node 3 has left the lobby and gone on a date with Node 1.
Time 315000: Signal issues: Node 0 sees too many errors while talking to Node 1. They call it off.
Time 325000: Node 0 finishes its task and walks into the dating lobby (free_to_cupid=1).
Time 355000: Node 1 finishes its task and walks into the dating lobby (free_to_cupid=1).
Time 355000: Signal issues: Node 2 sees too many errors while talking to Node 3. They call it off.
Time 365000: Node 2 finishes its task and walks into the dating lobby (free_to_cupid=1).
Time 365000: Cupid whispers to Node 0: 'How about you meet Node 1?' (pair_valid).
Time 365000: Cupid whispers to Node 1: 'How about you meet Node 0?' (pair_valid).
Time 375000: Node 0 has left the lobby and gone on a date with Node 1.
Time 375000: Node 1 has left the lobby and gone on a date with Node 0.
Time 435000: Node 0 finishes its task and walks into the dating lobby (free_to_cupid=1).
Time 605000: Node 3 is running hot at temp=71 while dating. Sparks are literally flying.
Time 615000: Node 2 finishes its task and walks into the dating lobby (free_to_cupid=1).
Time 615000: Node 3 is running hot at temp=72 while dating. Sparks are literally flying.
Time 625000: Cupid whispers to Node 0: 'How about you meet Node 2?' (pair_valid).
Time 625000: Cupid whispers to Node 2: 'How about you meet Node 0?' (pair_valid).
Time 625000: Node 3 is running hot at temp=73 while dating. Sparks are literally flying.
Time 635000: Node 0 has left the lobby and gone on a date with Node 2.
Time 635000: Node 2 has left the lobby and gone on a date with Node 0.
Time 635000: Node 3 is running hot at temp=74 while dating. Sparks are literally flying.
Time 645000: Node 3 is running hot at temp=75 while dating. Sparks are literally flying.
Time 655000: Node 3 is running hot at temp=76 while dating. Sparks are literally flying.
Time 665000: Node 1 is running hot at temp=71 while dating. Sparks are literally flying.
Time 665000: Node 3 is running hot at temp=77 while dating. Sparks are literally flying.
Time 675000: Node 1 is running hot at temp=72 while dating. Sparks are literally flying.
Time 675000: Node 3 is running hot at temp=78 while dating. Sparks are literally flying.
Time 685000: Node 0 finishes its task and walks into the dating lobby (free_to_cupid=1).
Time 685000: Node 1 is running hot at temp=73 while dating. Sparks are literally flying.
Time 685000: Node 2 is running hot at temp=71 while dating. Sparks are literally flying.
Time 685000: Node 3 is running hot at temp=79 while dating. Sparks are literally flying.
Time 695000: Node 1 is running hot at temp=74 while dating. Sparks are literally flying.
Time 695000: Node 2 is running hot at temp=72 while dating. Sparks are literally flying.
Time 695000: Node 3 is running hot at temp=80 while dating. Sparks are literally flying.
Time 705000: Node 1 is running hot at temp=75 while dating. Sparks are literally flying.
Time 705000: Node 2 is running hot at temp=73 while dating. Sparks are literally flying.
Time 705000: Node 3 is running hot at temp=81 while dating. Sparks are literally flying.
Time 715000: Node 1 is running hot at temp=76 while dating. Sparks are literally flying.
Time 715000: Node 2 is running hot at temp=74 while dating. Sparks are literally flying.
Time 715000: Node 3 is running hot at temp=82 while dating. Sparks are literally flying.
Time 725000: Node 1 is running hot at temp=77 while dating. Sparks are literally flying.
Time 725000: Node 2 is running hot at temp=75 while dating. Sparks are literally flying.
Time 725000: Node 3 is running hot at temp=83 while dating. Sparks are literally flying.
Time 735000: Node 1 is running hot at temp=78 while dating. Sparks are literally flying.
Time 735000: Node 2 is running hot at temp=76 while dating. Sparks are literally flying.
Time 735000: Node 3 is running hot at temp=84 while dating. Sparks are literally flying.
Time 745000: Node 1 is running hot at temp=79 while dating. Sparks are literally flying.
Time 745000: Node 2 is running hot at temp=77 while dating. Sparks are literally flying.
Time 745000: Node 3 is running hot at temp=85 while dating. Sparks are literally flying.
Time 755000: Node 1 is running hot at temp=80 while dating. Sparks are literally flying.
Time 755000: Node 2 is running hot at temp=78 while dating. Sparks are literally flying.
Time 755000: Node 3 is running hot at temp=86 while dating. Sparks are literally flying.
Time 765000: Node 1 is running hot at temp=81 while dating. Sparks are literally flying.
Time 765000: Node 2 is running hot at temp=79 while dating. Sparks are literally flying.
Time 765000: Node 3 is running hot at temp=87 while dating. Sparks are literally flying.
Time 775000: Node 1 is running hot at temp=82 while dating. Sparks are literally flying.
Time 775000: Node 2 is running hot at temp=80 while dating. Sparks are literally flying.
Time 775000: Node 3 is running hot at temp=88 while dating. Sparks are literally flying.
Time 785000: Node 1 is running hot at temp=83 while dating. Sparks are literally flying.
Time 785000: Node 2 is running hot at temp=81 while dating. Sparks are literally flying.
Time 785000: Node 3 is running hot at temp=89 while dating. Sparks are literally flying.
Time 795000: Node 1 is running hot at temp=84 while dating. Sparks are literally flying.
Time 795000: Node 2 is running hot at temp=82 while dating. Sparks are literally flying.
Time 795000: Node 3 is running hot at temp=90 while dating. Sparks are literally flying.
Time 805000: Node 1 is running hot at temp=85 while dating. Sparks are literally flying.
Time 805000: Node 2 is running hot at temp=83 while dating. Sparks are literally flying.
Time 805000: Node 3 is running hot at temp=91 while dating. Sparks are literally flying.
Time 815000: Node 1 is running hot at temp=86 while dating. Sparks are literally flying.
Time 815000: Node 2 is running hot at temp=84 while dating. Sparks are literally flying.
Time 815000: Node 3 is running hot at temp=92 while dating. Sparks are literally flying.
Time 825000: Node 1 is running hot at temp=87 while dating. Sparks are literally flying.
Time 825000: Node 2 is running hot at temp=85 while dating. Sparks are literally flying.
Time 825000: Node 3 is running hot at temp=93 while dating. Sparks are literally flying.
Time 835000: Node 1 is running hot at temp=88 while dating. Sparks are literally flying.
Time 835000: Node 2 is running hot at temp=86 while dating. Sparks are literally flying.
Time 835000: Node 3 is running hot at temp=94 while dating. Sparks are literally flying.
Time 845000: Node 1 is running hot at temp=89 while dating. Sparks are literally flying.
Time 845000: Node 2 is running hot at temp=87 while dating. Sparks are literally flying.
Time 845000: Node 3 is running hot at temp=95 while dating. Sparks are literally flying.
Time 855000: Node 1 is running hot at temp=90 while dating. Sparks are literally flying.
Time 855000: Node 2 is running hot at temp=88 while dating. Sparks are literally flying.
Time 855000: Node 3 is running hot at temp=96 while dating. Sparks are literally flying.
Time 865000: Node 1 is running hot at temp=91 while dating. Sparks are literally flying.
Time 865000: Node 2 is running hot at temp=89 while dating. Sparks are literally flying.
Time 865000: Node 3 is running hot at temp=97 while dating. Sparks are literally flying.
Time 875000: Node 1 is running hot at temp=92 while dating. Sparks are literally flying.
Time 875000: Node 2 is running hot at temp=90 while dating. Sparks are literally flying.
Time 875000: Node 3 is running hot at temp=98 while dating. Sparks are literally flying.
Time 885000: Node 1 is running hot at temp=93 while dating. Sparks are literally flying.
Time 885000: Node 2 is running hot at temp=91 while dating. Sparks are literally flying.
Time 885000: Node 3 is running hot at temp=99 while dating. Sparks are literally flying.
Time 895000: Node 1 is running hot at temp=94 while dating. Sparks are literally flying.
Time 895000: Node 2 is running hot at temp=92 while dating. Sparks are literally flying.
Time 895000: Node 3 is running hot at temp=100 while dating. Sparks are literally flying.
Time 905000: Node 1 is running hot at temp=95 while dating. Sparks are literally flying.
Time 905000: Node 2 is running hot at temp=93 while dating. Sparks are literally flying.
Time 905000: Node 3 is running hot at temp=100 while dating. Sparks are literally flying.
Time 915000: Node 1 is running hot at temp=96 while dating. Sparks are literally flying.
Time 915000: Node 2 is running hot at temp=94 while dating. Sparks are literally flying.
Time 915000: Node 3 is running hot at temp=100 while dating. Sparks are literally flying.
Time 925000: Node 1 is running hot at temp=97 while dating. Sparks are literally flying.
Time 925000: Node 2 is running hot at temp=95 while dating. Sparks are literally flying.
Time 925000: Node 3 is running hot at temp=100 while dating. Sparks are literally flying.
Time 935000: Node 1 is running hot at temp=98 while dating. Sparks are literally flying.
Time 935000: Node 2 is running hot at temp=96 while dating. Sparks are literally flying.
Time 935000: Node 3 is running hot at temp=100 while dating. Sparks are literally flying.
Time 945000: Node 1 is running hot at temp=99 while dating. Sparks are literally flying.
Time 945000: Node 2 is running hot at temp=97 while dating. Sparks are literally flying.
Time 945000: Node 3 is running hot at temp=100 while dating. Sparks are literally flying.
Time 955000: Node 1 is running hot at temp=100 while dating. Sparks are literally flying.
Time 955000: Node 2 is running hot at temp=98 while dating. Sparks are literally flying.
Time 955000: Node 3 is running hot at temp=100 while dating. Sparks are literally flying.
Time 965000: Node 1 is running hot at temp=100 while dating. Sparks are literally flying.
Time 965000: Node 2 is running hot at temp=99 while dating. Sparks are literally flying.
Time 965000: Node 3 is running hot at temp=100 while dating. Sparks are literally flying.
Time 975000: Node 1 is running hot at temp=100 while dating. Sparks are literally flying.
Time 975000: Node 2 is running hot at temp=100 while dating. Sparks are literally flying.
Time 975000: Node 3 is running hot at temp=100 while dating. Sparks are literally flying.
Time 985000: Node 1 is running hot at temp=100 while dating. Sparks are literally flying.
Time 985000: Node 2 is running hot at temp=100 while dating. Sparks are literally flying.
Time 985000: Node 3 is running hot at temp=100 while dating. Sparks are literally flying.
Time 995000: Node 1 is running hot at temp=100 while dating. Sparks are literally flying.
Time 995000: Node 2 is running hot at temp=100 while dating. Sparks are literally flying.
Time 995000: Node 3 is running hot at temp=100 while dating. Sparks are literally flying.
Time 1000000: The workday in silicon city ends. Final couples count on debug LEDs = 0.
$finish called at time : 1 us : File "C:/Users/RISHIK NAIR/Downloads/To-do/Silicon_dating/Silicon_dating.srcs/sim_1/new/tb_silicon_dating_story.v" Line 217
INFO: [USF-XSim-96] XSim completed. Design snapshot 'tb_silicon_dating_story_behav' loaded.
INFO: [USF-XSim-97] XSim simulation ran for 1000ns
launch_simulation: Time (s): cpu = 00:00:02 ; elapsed = 00:00:05 . Memory (MB): peak = 1011.797 ; gain = 2.035
```
## Code explained

Below is a human‑readable explanation of the main RTL pieces in the “Dating in Silicon” project, plus the ideology behind each block. You can paste this section straight into an Obsidian note.

---

### Task master – making everyone “busy enough”


```verilog

module task_master #(parameter N_NODES = 4 )
( input clk_global,
input rst_n,    
output reg [N_NODES-1:0]  task_valid,    
output reg [N_NODES-1:0]  task_alt_rate,    
input      [N_NODES-1:0]  task_done,    
input      [N_NODES-1:0]  couple_locked );     
reg [15:0] cnt;    
integer i;    
... endmodule
```

- **What it does:**
    
    - Maintains a global counter `cnt`.
        
    - Periodically asserts `task_valid[i]` for each node `i`, with `task_alt_rate[i]` toggling between “short” and “long” jobs.
        
    - Looks at `task_done` to know when nodes finish and at `couple_locked` to slightly bias load away from nodes that are already “in a relationship”.
        
- **Ideology:**  
    This module is the “company” in silicon city. Everyone has a job; dating can only happen when nodes are free. By staggering jobs and varying length, it naturally creates **phases of contention and idle time** where Cupid can step in. It’s also how you inject controlled stress to see how relationships respond to load imbalance.
    

---

## Person node – worker plus romantic finite state machine



```verilog

module person_node #(parameter ID = 0, 
parameter ID_W = 4, 
parameter PREF_W = 8,    
parameter DATE_LEN = 64 )
(input clk_task,
input clk_async,    
input rst_n,    
// task ports...    // cupid ports...    // telemetry ports...    // wormhole ports... );
```

- **What it does (work side):**
    
    - On `task_valid`, if not currently dating or coupled, starts a local work counter.
        
    - Uses `task_alt_rate` to choose job length (short vs long), then pulses `task_done` when the counter reaches zero.
        
    - Exposes `free_to_cupid` whenever it is _not_ working, _not_ dating, and _not_ coupled.
        
- **What it does (dating side):**
    
    - Internal FSM: `IDLE → PRE_SEND / PRE_RECV → DATING → COUPLED`.
        
    - On `pair_valid_cupid`:
        
        - Latches `partner_id_cupid`, decides whether to send or receive first based on `is_initiator`.
            
        - Sends `{MY_ID, my_pref}` over the wormhole, or waits to receive partner’s packet.
            
    - Computes XOR of preference vectors and popcount; if distance is too large → **pre‑date breakup** (`PRE_FAIL`).
        
    - In `DATING`:
        
        - Counts how long the date lasts (`dating_cnt`).
            
        - Tracks if only one side is working for too long (`free_wait_cnt`) → breakup for “work–life imbalance”.
            
        - Increments `error_counters` when hot/cold or latency constraints are violated, breaking up if too many errors.
            
        - If they survive `DATE_LEN` cycles → raise `couple_locked` and enter `S_COUPLED`.
            
- **Ideology:**  
    Each node is a **mini agent**: a worker, a partner, and a thermometer. The FSM is where the metaphor becomes hardware:
    
    - XOR preference check ≈ “are our interests compatible?”
        
    - Error‑driven breakup ≈ “our link is too noisy / out of spec.”
        
    - `DATE_LEN` threshold ≈ “we’ve stress‑tested this pair long enough to trust it.”  
        This lets you explore cooperative behavior, stability, and failure modes with a single, compact FSM.
        

---

## Cupid core – centralized matchmaker and policy brain



```verilog

module cupid_core #(parameter N_NODES = 4, parameter ID_W = 4 )
(input clk_global,    
input rst_n,    
input [N_NODES-1:0] free_from_node, 
input [N_NODES-1:0] dating_busy_from_node,    
input [N_NODES-1:0]  couple_locked_from_node,    
input [N_NODES*16-1:0] node_clk_est_flat,    
input [N_NODES*8 -1:0] node_temp_est_flat,    
input [N_NODES*8 -1:0] node_latency_est_flat,    
input [N_NODES*8 -1:0] node_error_ctr_flat,    
input [N_NODES*4 -1:0] node_dating_status_flat,    
output reg [N_NODES*ID_W-1:0] partner_id_to_node_flat,    
output reg [N_NODES-1:0] pair_valid_to_node,
output reg [N_NODES-1:0] initiator_flag_to_node,    
output reg [N_NODES*4-1:0] breakup_reason_to_node_flat,
output reg [N_NODES*ID_W-1:0] route_dst_id_flat ); 
```

- **What it does:**
    
    - Unpacks flattened buses into per‑node structures (`node_clk_est[i]`, `node_temp_est[i]`, etc.).
        
    - Scans for two **free, non‑coupled** nodes whose `latency_est` values are close enough.
        
    - For a chosen pair `(i, j)`:
        
        - Writes `partner_id_to_node_flat` for both.
            
        - Asserts `pair_valid_to_node[i]` and `[j]`.
            
        - Picks one as initiator.
            
        - Sets `route_dst_id` so the wormhole knows where to send date packets.
            
    - Watches `node_dating_status_flat` to record breakup reasons and, in future, to influence policy.
        
- **Ideology:**  
    `cupid_core` is a **central policy engine**. Instead of a random pairing, it uses latency and (optionally) temp and error stats as a crude “compatibility function.” This is where you can plug in more advanced logic:
    
    - Avoid pairs with a history of repeated errors.
        
    - Prefer “opposites” by temperature or role.
        
    - Bias toward under‑tested links to improve coverage.  
        It’s effectively a run‑time pairing scheduler over agents, which is a nice mental model for adaptive resource managers in bigger SoCs.
        


---

## Wormhole fabric – tiny on‑chip dating subway


```verilog

module wormhole_fabric #(parameter N_NODES = 4, parameter ID_W = 4,parameter PREF_W  = 8 )
( input clk_global,    
input rst_n,    
input  [N_NODES*(ID_W+PREF_W)-1:0] src_data_flat,    
input  [N_NODES-1:0] src_valid,    
output reg [N_NODES-1:0] src_ready,    
output reg [N_NODES*(ID_W+PREF_W)-1:0] dst_data_flat,    
output reg [N_NODES-1:0] dst_valid,    
input  [N_NODES-1:0] dst_ready,
input  [N_NODES*ID_W-1:0]  route_dst_id_flat );
```

- **What it does:**
    
    - Treats each node as a source and destination of one‑word packets `{ID, pref}`.
        
    - Unpacks the flattened arrays into `src_data[i]` and `route_dst_id[i]`.
        
    - For each `i` where `src_valid[i]` is high and the destination slot is free:
        
        - Copies `src_data[i]` to `dst_data[route_dst_id[i]]`.
            
        - Asserts `dst_valid[route_dst_id[i]]` and `src_ready[i]`.
            
    - Uses `dst_ready` to know when a node has consumed its incoming packet.
        
- **Ideology:**  
    This is a **minimal wormhole crossbar**: one flit per transfer, single clock domain. It’s intentionally simple but structured like something you can later mutate into:
    
    - A genuine multi‑hop NoC.
        
    - An asynchronous FIFO network for real CDC experiments.  
        Conceptually, it’s the **underground tunnel** where nodes privately exchange their pref
---

## Testbench – turning behaviour into a story

```verilog

module tb_silicon_dating_story;     
// clock/reset, DUT instantiation ...    
// helper functions get_partner_id, get_status, get_temp ...    
initial begin @(posedge rst_n);        
$display("Time %0t: The silicon city awakens...", $time);        
forever begin @(posedge clk);            
// monitor free_to_cupid, pair_valid, dating_busy, couple_locked, 
// temp_est, and node_dating_status_flat...        
end    
end 
endmodule
```

- **What it does:**
    
    - Generates clock and reset, instantiates `silicon_dating_top`.
        
    - Uses **hierarchical access** (`uut.*`) plus helper functions to decode flattened buses into per‑node views.
        
    - On any interesting transition (node becomes free, receives a pair, starts dating, reports a breakup reason, crosses a temperature threshold), it prints a narrative `$display` message with timestamp.
        
    - Stops after 1 µs, printing the final number of couples via `debug_leds`.
        
    
- **Ideology:**  
    The testbench is a **semantic monitor**: instead of dumping raw waves, it translates signal changes into human‑readable events. That makes it much easier to debug pairing logic, state machine edges, and timing of breakups, and it doubles as documentation of the protocol behaviour. It’s essentially a scripted “observer” for your small multi‑agent system.
    
---

Together, these pieces turn a conventional FPGA design (FSMs, routers, schedulers) into a playful micro‑society where you can study scheduling, communication, error handling, and simple “policies” under a memorable metaphor.
## Extension Ideas

- **True multi-clock CDC:**  
    Attach per-node PLLs and replace the wormhole with proper Gray-coded asynchronous FIFOs so that pre-dating truly crosses clock domains and you can run CDC checks and timing analysis on real async logic.[ieeexplore.ieee](https://ieeexplore.ieee.org/document/10533170/)​
    
- **Learning Cupid:**  
    Add a small scoring table in `cupid_core` that:
    
    - Rewards successful long dates.
        
    - Penalizes repeated breakups.
        
    - Learns which pairs are stable and biases future matches accordingly.
        
- **Spatial/NoC realism:**
    
    - Let `latency_est` reflect actual hop counts in a simple NoC.
        
    - Explore how topology (ring, mesh) affects who can date stably.
        
- **Aging and fault-injection:**
    
    - Gradually increase error rates on certain node pairs to emulate aging interconnects.
        
    - Observe how Cupid learns to avoid “damaged routes”.
        

This project therefore becomes a compact, playful lab for **task scheduling, protocol design, routing, thermal modeling, CDC, and fault-tolerant pairing policies**, all sitting on top of a clean, synthesizable Verilog implementation.