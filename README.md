# 🧪💘Dating in Silicon – Simulation Story🧪💘

> File type: Obsidian note (Markdown)  
> Context: Vivado simulation log for `tb_silicon_dating_story` wrapped as a story of a tiny digital city.​
![License: MIT]([https://img.shields.io/badge/License-MIT-yellow.svg](https://img.shields.io/badge/License-MIT-yellow.svg)
---
<img src="images/wave_synthesis.png" alt="Simulation Waveform" width="800"/>
## 1. Prologue: Welcome to Silicon City

In a quiet corner of the FPGA, there is a tiny metropolis called **Silicon City**.  
The inhabitants are four compute nodes: **Node 0**, **Node 1**, **Node 2**, and **Node 3**. Each one has a job, a clock, a temperature, and—most importantly—a _preference vector_ that secretly encodes what they like in a partner.

Every “day” in Silicon City is a **simulation run**. The **Task Master** hands out work, **Cupid Core** arranges dates, and the **Wormhole Fabric** acts as an underground communication tunnel where nodes exchange their “phone numbers” and preferences asynchronously before deciding whether to date.

This note chronicles two simulation runs:

- **Test 1:** First shakedown of the dating rules, no long hot runs.
    
- **Test 2:** Same world, but we let the city run hotter and watch sparks fly.
    

---

## 2. Cast of Characters (Modules)

## 2.1 Task Master

- Module: `task_master`
    
- Role: Overworked but cheerful scheduler.
    
- Behavior:
    
    - Issues staggered jobs to each node at different intervals.
        
    - Sometimes gives longer jobs (for “workaholic stress tests”) by toggling `task_alt_rate`.
        
    - If a node is _coupled_, tries not to overload it, to avoid work–love imbalance.
        

## 2.2 Cupid Core

- Module: `cupid_core`
    
- Role: Matchmaker-in-chief.
    
- Behavior:
    
    - Watches `free_to_cupid`, `dating_busy`, and `couple_locked` from each node.
        
    - Looks at **latency estimates** and rough compatibility to choose pairs.
        
    - Decides who initiates the wormhole exchange.
        
    - Tracks **dating status codes**:
        
        - `1`: Pre-date breakup (preferences clash).
            
        - `2`: Date breakup (load imbalance).
            
        - `3`: Date breakup (too many errors).
            
        - `4`: Success: couple locked.
            

## 2.3 Wormhole Fabric

- Module: `wormhole_fabric`
    
- Role: The city’s secret subway.
    
- Behavior:
    
    - Routes `{ID, preference}` packets from initiator to target.
        
    - Uses flattened buses for easy Verilog wiring.
        
    - In future versions, becomes a full async FIFO network to really stress CDC.
        

## 2.4 Person Nodes

- Module: `person_node`
    
- Instances: Node 0, Node 1, Node 2, Node 3
    
- Each node:
    
    - Works on tasks at changing rates.
        
    - When idle and single, raises `free_to_cupid` to enter the **dating lobby**.
        
    - On a match:
        
        - Initiator sends `{ID, pref}` through the wormhole.
            
        - Responder XORs preferences; if too different, they break up instantly.
            
    - While dating:
        
        - They accumulate _error counters_ if hot/cold or latency is bad.
            
        - If errors exceed a threshold, they break up due to “signal issues”.
            
        - If work keeps interrupting only one side, they break up due to imbalance.
            
        - If they survive `DATE_LEN` cycles, they become a **permanent couple**.
            

---

## 3. Test 1 – A Short Workday With No Couples

> **Config:** 50,000 to 500,000 time units observed  
> **Outcome:** All four nodes date, some multiple times, but no couple survives long enough to lock.

## 3.1 Morning: Everybody Arrives

At time **50,000**, the simulator announces the start of the day:

> Time 50000: The silicon city awakens. 4 nodes are ready for work and maybe love.

Shortly after, all four finish their initial tasks and drift into the dating lobby:

- Time 55,000: Node 0, 1, 2, and 3 each “finish work and walk into the dating lobby (free_to_cupid=1).”
    

Visually, you can imagine four tiny cores stepping off a bus at the same time and looking around for someone interesting.

## 3.2 First Matches: 0–1 and 2–3

Cupid does not waste time:

- Time 65,000:
    
    - “Cupid whispers to Node 0: ‘How about you meet Node 1?’”
        
    - “Cupid whispers to Node 1: ‘How about you meet Node 0?’”
        
- Time 75,000:
    
    - Node 0 and Node 1 both “leave the lobby and go on a date.”
        

This is the **first couple attempt** of the day.

Soon after:

- Time 85,000:
    
    - Cupid proposes Node 2 ↔ Node 3.
        
- Time 95,000:
    
    - Node 2 and Node 3 start dating.
        

At this point, Silicon City looks like:

- Pair 1: Node 0 ❤ Node 1
    
- Pair 2: Node 2 ❤ Node 3
    

Everyone is off the market and talking through wormhole packets.

## 3.3 Midday: Signal Issues and Breakups

The design intentionally injects stress: temperature, latency, and error counters may not line up. After a period of dating:

- Time 245,000:  
    “Signal issues: Node 1 sees too many errors while talking to Node 0. They call it off.”
    

Later:

- Time 265,000:  
    “Signal issues: Node 3 sees too many errors while talking to Node 2. They call it off.”
    

These events come from the **error counter threshold** inside `person_node`. The hot–cold and latency checks are imperfect, like a mis-tuned PHY: if they accumulate enough violations, the pair breaks.

After breakups, each node returns to work and eventually comes back to the lobby:

- Node 1 reappears free at 255,000.
    
- Node 3 reappears free at 275,000.
    

## 3.4 New Pairing: 1–3

Cupid, ever optimistic, re-shuffles the deck:

- Time 285,000:
    
    - Node 1 ↔ Node 3 get matched.
        
- Time 295,000:
    
    - They both “leave the lobby and go on a date.”
        

But the clock skew, temperatures, or workload do not favor long-term harmony. The earlier Node 0–1 and 2–3 link histories linger in their error counters and compatibility metrics.

Eventually, **Node 0** also reports issues:

- Time 315,000:  
    “Signal issues: Node 0 sees too many errors while talking to Node 1. They call it off.”
    

The dance continues: nodes work, go free, get paired, date, and then break when the internal rules complain.

## 3.5 Evening: Still No Permanent Couples

By the time we reach:

> Time 500000: The workday in silicon city ends. Final couples count on debug LEDs = 0.

No pair has survived the full `DATE_LEN` without triggering a breakup condition. The **`debug_leds`** port shows 0, indicating that no `couple_locked` bit remained high at the end.

From a hardware-design angle, this confirms:

- The **dating FSM** is exercising:
    
    - Free → pre-date → dating → breakup paths.
        
- The **error counters** and breakup logic are active.
    
- No deadlocks: all nodes keep transitioning and returning to free state.
    

---

## 4. Test 2 – Hot City, No Rings

> **Config:** Longer run to 1,000,000 time units  
> **Outcome:** More dates, lots of thermal drama, still no couples.

## 4.1 Setup and Compilation

Vivado walks through the usual ritual:

- Static elaboration, data flow analysis.
    
- Compilation of:
    
    - `task_master`
        
    - `cupid_core_default`
        
    - `wormhole_fabric_default`
        
    - `person_node_default` (for ID 0)
        
    - `person_node(ID=1)`, `(ID=2)`, `(ID=3)`
        
    - `silicon_dating_top_default`
        
    - `tb_silicon_dating_story`
        
- Snapshot `tb_silicon_dating_story_behav` is built and simulated.[semanticscholar+1](https://www.semanticscholar.org/paper/2fe16f01c975f6fe93bf28b2970ab29d33aabadf)​
    

This is the toolchain’s way of saying: **“The city is ready for another day.”**

## 4.2 Replaying the Early Story

The early narrative is identical to Test 1:

- Awakening at 50,000.
    
- All four nodes enter the lobby at 55,000.
    
- Matches:
    
    - Node 0 ↔ Node 1.
        
    - Node 2 ↔ Node 3.
        
- Both pairs start dating.
    
- Later, the same style of **signal-issue breakups** for 1–0 and 3–2.
    
- Intermediate re-matching:
    
    - Node 1 ↔ Node 3.
        
    - Node 0 ↔ Node 1 again.
        
    - Node 0 ↔ Node 2 later on.
        

The system is stable and repeatable: the same stimuli produce the same pattern of early relationships.

## 4.3 The Thermal Arc: “Sparks Are Literally Flying”

Test 2 runs longer, so the **temperature model** inside each `person_node` gets to fully ramp:

- When a node is either **working or dating**, `temp_est` increments up toward 100.
    
- When idle and not dating, it cools down.
    

Past a threshold (70+), the testbench adds commentary:

> “Node X is running hot at temp=YY while dating. Sparks are literally flying.”

From around **605,000** onwards, the log becomes a thermal drama:

- Node 3 starts climbing: temp 71, 72, 73, … up to 100.
    
- Soon Node 1 and Node 2 join the race:
    
    - Each line: “Node N is running hot at temp=TT while dating. Sparks are literally flying.”
        
- Temperatures plateau at 100 for some nodes, showing the _saturation_ of the model.
    

In narrative terms, this is the **“passion arc”**: everyone keeps dating under heavy, hot workloads. In hardware terms, it validates:

- The temperature counter never overflows incorrectly.
    
- The “hot while dating” condition is exercised for many cycles.
    
- All nodes can sustain high temp while still progressing state machines.
    

## 4.4 Still No Stable Couples

Despite many matches and a lot of heat:

- No pair manages to stay together for the full `DATE_LEN` without hitting error thresholds or imbalance.
    
- The final line:
    

> Time 1000000: The workday in silicon city ends. Final couples count on debug LEDs = 0.

Once again, **no `couple_locked`** bits remain set. Silicon City has had a passionate but ultimately **non-committal** day.

From a verification lens:

- The “success path” (coupling) is still untested in this configuration.
    
- The “failure paths” (error-based breakup, pre-date style mismatch, thermal stress) are very well exercised.
    

---

## 5. Visual Ideas for Obsidian

You can enhance this note with a few conceptual images (drawn by you or as diagrams):

- **Block Diagram of Silicon City**  
    A small diagram showing:
    
    - Task Master at the top.
        
    - Cupid Core and Wormhole Fabric in the middle.
        
    - Four Person Nodes at the bottom, with arrows for work and dating traffic.
        
- **Timeline Sketch**  
    A simple timeline with colored bars:
    
    - Each row = one node.
        
    - Bars for “working”, “free”, “dating with X”, “breakup events”.
        
    - Overlaid temperature curve.
        
- **State Machine Doodle**  
    For `person_node`:
    
    - Circles: `IDLE`, `PRE_SEND`, `PRE_RECV`, `DATING`, `COUPLED`.
        
    - Arrows annotated with **“prefs XOR too large → PRE_FAIL”**, **“error_ctr > TH → ERROR_BREAK”**, **“DATE_LEN reached → COUPLED”**.
        

These visuals fit nicely beside the story text in Obsidian and help explain both the **romantic metaphor** and the **hard RTL behavior** at the same time.[joss.theoj+1](http://joss.theoj.org/papers/10.21105/joss.00185)​

If you want, a follow-up note can be written as a “post-mortem” where you tune DATE_LEN, temperature thresholds, and error rules to finally let at least one couple survive a day in Silicon City.