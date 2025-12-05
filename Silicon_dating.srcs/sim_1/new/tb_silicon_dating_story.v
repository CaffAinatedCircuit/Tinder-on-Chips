`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.12.2025 20:21:51
// Design Name: 
// Module Name: tb_silicon_dating_story
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_silicon_dating_story;

    // Parameters must match DUT
    localparam N_NODES = 4;
    localparam ID_W    = 4;
    localparam PREF_W  = 8;
    localparam DATA_W  = ID_W + PREF_W;

    reg clk;
    reg rst_n;

    wire [7:0] debug_leds;

    // Instantiate DUT
    silicon_dating_top #(
        .N_NODES(N_NODES),
        .ID_W   (ID_W),
        .PREF_W (PREF_W)
    ) uut (
        .clk_global(clk),
        .rst_n     (rst_n),
        .debug_leds(debug_leds)
    );

    // -----------------------------------------
    // Clock generation
    // -----------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 100 MHz
    end

    // -----------------------------------------
    // Reset sequence
    // -----------------------------------------
    initial begin
        rst_n = 1'b0;
        #50;
        rst_n = 1'b1;
    end

    // -----------------------------------------
    // Helper tasks/functions for decoding
    // -----------------------------------------

    // Read partner ID for node i from flattened bus
    function [ID_W-1:0] get_partner_id;
        input integer idx;
        begin
            get_partner_id = uut.partner_id_to_node_flat[idx*ID_W +: ID_W];
        end
    endfunction

    // Read dating status code for node i
    function [3:0] get_status;
        input integer idx;
        begin
            get_status = uut.node_dating_status_flat[idx*4 +: 4];
        end
    endfunction

    // Read breakup reason for node i
    function [3:0] get_breakup_reason;
        input integer idx;
        begin
            get_breakup_reason = uut.breakup_reason_to_node_flat[idx*4 +: 4];
        end
    endfunction

    // Read temp estimate for node i
    function [7:0] get_temp;
        input integer idx;
        begin
            get_temp = uut.node_temp_est_flat[idx*8 +: 8];
        end
    endfunction

    // Small text helpers
    function [80*8-1:0] status_to_str;
        input [3:0] s;
        begin
            case (s)
                4'd0: status_to_str = "IDLE_OR_NO_REPORT";
                4'd1: status_to_str = "PRE_DATE_BREAKUP (prefs too different)";
                4'd2: status_to_str = "DATE_BREAKUP (load imbalance)";
                4'd3: status_to_str = "DATE_BREAKUP (too many errors)";
                4'd4: status_to_str = "COUPLED (they survived!)";
                default: status_to_str = "UNKNOWN_STATUS";
            endcase
        end
    endfunction

    // -----------------------------------------
    // Story monitor
    // -----------------------------------------
    integer i;
    reg [N_NODES-1:0] prev_free;
    reg [N_NODES-1:0] prev_dating_busy;
    reg [N_NODES-1:0] prev_couple;
    reg [N_NODES-1:0] prev_pair_valid;
    reg [3:0]         prev_status [0:N_NODES-1];

    initial begin
        // initialize previous states
        prev_free       = {N_NODES{1'b0}};
        prev_dating_busy= {N_NODES{1'b0}};
        prev_couple     = {N_NODES{1'b0}};
        prev_pair_valid = {N_NODES{1'b0}};
        for (i = 0; i < N_NODES; i = i + 1)
            prev_status[i] = 4'd0;

        // wait for reset deassertion
        @(posedge rst_n);
        $display("Time %0t: The silicon city awakens. %0d nodes are ready for work and maybe love.",
                 $time, N_NODES);

        // Main monitor loop
        forever begin
            @(posedge clk);

            // Monitor free status: who just became free?
            for (i = 0; i < N_NODES; i = i + 1) begin
                if (uut.free_to_cupid[i] && !prev_free[i]) begin
                    $display("Time %0t: Node %0d finishes its task and walks into the dating lobby (free_to_cupid=1).",
                             $time, i);
                end
            end

            // Monitor new pair proposals from Cupid
            for (i = 0; i < N_NODES; i = i + 1) begin
                if (uut.pair_valid_to_node[i] && !prev_pair_valid[i]) begin
                    $display("Time %0t: Cupid whispers to Node %0d: 'How about you meet Node %0d?' (pair_valid).",
                             $time, i, get_partner_id(i));
                end
            end

            // Monitor start of dating_busy
            for (i = 0; i < N_NODES; i = i + 1) begin
                if (uut.dating_busy[i] && !prev_dating_busy[i]) begin
                    $display("Time %0t: Node %0d has left the lobby and gone on a date with Node %0d.",
                             $time, i, get_partner_id(i));
                end
            end

            // Monitor status transitions (pre-fail, breaks, coupling)
            for (i = 0; i < N_NODES; i = i + 1) begin
                if (get_status(i) != prev_status[i]) begin
                    case (get_status(i))
                        4'd1: $display("Time %0t: Awkward silence! Node %0d and Node %0d realize their prefs clash and break up before the date.",
                                       $time, i, get_partner_id(i));
                        4'd2: $display("Time %0t: Work-life imbalance: Node %0d is overloaded while its partner idles. They drift apart.",
                                       $time, i);
                        4'd3: $display("Time %0t: Signal issues: Node %0d sees too many errors while talking to Node %0d. They call it off.",
                                       $time, i, get_partner_id(i));
                        4'd4: $display("Time %0t: After many cycles together, Node %0d and Node %0d become an official couple (locked).",
                                       $time, i, get_partner_id(i));
                        default: ;
                    endcase
                end
            end

            // Monitor new couples (locking)
            for (i = 0; i < N_NODES; i = i + 1) begin
                if (uut.couple_locked[i] && !prev_couple[i]) begin
                    $display("Time %0t: Node %0d now wears a ring on its clock tree (couple_locked=1).",
                             $time, i);
                end
            end

            // Optional: small thermal gossip
            for (i = 0; i < N_NODES; i = i + 1) begin
                if (uut.dating_busy[i] && (get_temp(i) > 8'd70)) begin
                    $display("Time %0t: Node %0d is running hot at temp=%0d while dating. Sparks are literally flying.",
                             $time, i, get_temp(i));
                end
            end

            // update previous state
            prev_free        = uut.free_to_cupid;
            prev_dating_busy = uut.dating_busy;
            prev_couple      = uut.couple_locked;
            prev_pair_valid  = uut.pair_valid_to_node;
            for (i = 0; i < N_NODES; i = i + 1)
                prev_status[i] = get_status(i);
        end
    end

    // -----------------------------------------
    // Simulation end
    // -----------------------------------------
    initial begin
        // run for a while then finish
        #1000;
        $display("Time %0t: The workday in silicon city ends. Final couples count on debug LEDs = %0d.",
                 $time, debug_leds);
        $finish;
    end

endmodule
