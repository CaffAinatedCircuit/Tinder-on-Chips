`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.12.2025 20:17:27
// Design Name: 
// Module Name: person_node
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


//============================================================
// person_node: work + dating FSM
//============================================================
module person_node #(
    parameter ID       = 0,
    parameter ID_W     = 4,
    parameter PREF_W   = 8,
    parameter DATE_LEN = 64
)(
    input                    clk_task,
    input                    clk_async, // reserved for real async use
    input                    rst_n,

    // Task interface
    input                    task_valid,
    input                    task_alt_rate,
    output reg               task_done,

    // Cupid interface
    output reg               free_to_cupid,
    output reg               dating_busy,
    output reg               couple_locked,
    input      [ID_W-1:0]    partner_id_cupid,
    input                    pair_valid_cupid,
    input                    is_initiator,
    input      [3:0]         breakup_reason_from_cupid,
    output reg [3:0]         dating_status_to_cupid,

    // Telemetry
    output reg [15:0]        clk_est,
    output reg [7:0]         temp_est,
    output reg [7:0]         latency_est,
    output reg [7:0]         error_counters,

    // Wormhole (pre-date)
    output reg [ID_W+PREF_W-1:0] wh_tx_data,
    output reg                   wh_tx_valid,
    input                        wh_tx_ready,
    input      [ID_W+PREF_W-1:0] wh_rx_data,
    input                        wh_rx_valid,
    output reg                   wh_rx_ready
);

    localparam [ID_W-1:0] MY_ID = ID[ID_W-1:0];

    // preference vector
    reg [PREF_W-1:0] my_pref;
    always @(posedge clk_task or negedge rst_n) begin
        if (!rst_n)
            my_pref <= (8'h3C ^ ID);
        else
            my_pref <= my_pref;
    end

    // Task engine
    reg [7:0] work_cnt;
    reg       working;

    always @(posedge clk_task or negedge rst_n) begin
        if (!rst_n) begin
            working   <= 1'b0;
            work_cnt  <= 8'd0;
            task_done <= 1'b0;
        end else begin
            task_done <= 1'b0;
            if (!working) begin
                if (task_valid && !dating_busy && !couple_locked) begin
                    working  <= 1'b1;
                    work_cnt <= task_alt_rate ? 8'd100 : 8'd20;
                end
            end else begin
                if (work_cnt == 8'd0) begin
                    working   <= 1'b0;
                    task_done <= 1'b1;
                end else begin
                    work_cnt <= work_cnt - 8'd1;
                end
            end
        end
    end

    // Telemetry
    always @(posedge clk_task or negedge rst_n) begin
        if (!rst_n) begin
            clk_est        <= 16'd100 + ID;
            temp_est       <= 8'd30;
            latency_est    <= 8'd10 + ID;
            error_counters <= 8'd0;
        end else begin
            if (working || dating_busy) begin
                if (temp_est < 8'd100)
                    temp_est <= temp_est + 1'b1;
            end else begin
                if (temp_est > 8'd10)
                    temp_est <= temp_est - 1'b1;
            end
        end
    end

    // Dating FSM
    localparam S_IDLE     = 3'd0;
    localparam S_PRE_SEND = 3'd1;
    localparam S_PRE_RECV = 3'd2;
    localparam S_DATING   = 3'd3;
    localparam S_COUPLED  = 3'd4;

    reg [2:0]      state;
    reg [ID_W-1:0] partner_id_latched;
    reg [PREF_W-1:0] partner_pref_latched;
    reg [7:0]      dating_cnt;
    reg [7:0]      free_wait_cnt;

    wire [ID_W-1:0]   rx_id   = wh_rx_data[ID_W+PREF_W-1 : PREF_W];
    wire [PREF_W-1:0] rx_pref = wh_rx_data[PREF_W-1:0];

    // XOR preference + popcount
    reg [PREF_W-1:0] xor_pref;
    reg [3:0]        xor_popcount;
    integer          bi;

    always @(*) begin
        xor_pref     = my_pref ^ partner_pref_latched;
        xor_popcount = 4'd0;
        for (bi = 0; bi < PREF_W; bi = bi + 1)
            xor_popcount = xor_popcount + xor_pref[bi];
    end

    wire prefs_compatible = (xor_popcount <= 4'd3);
    wire hot_cold_ok      = ((temp_est > 8'd60) && (partner_pref_latched[0] == 1'b0)) ||
                            ((temp_est < 8'd40) && (partner_pref_latched[0] == 1'b1));
    wire latency_ok       = (latency_est < 8'd40);

    always @(posedge clk_task or negedge rst_n) begin
        if (!rst_n) begin
            state                  <= S_IDLE;
            free_to_cupid          <= 1'b1;
            dating_busy            <= 1'b0;
            couple_locked          <= 1'b0;
            dating_status_to_cupid <= 4'd0;
            partner_id_latched     <= {ID_W{1'b0}};
            partner_pref_latched   <= {PREF_W{1'b0}};
            dating_cnt             <= 8'd0;
            free_wait_cnt          <= 8'd0;
            wh_tx_data             <= {ID_W+PREF_W{1'b0}};
            wh_tx_valid            <= 1'b0;
            wh_rx_ready            <= 1'b0;
        end else begin
            wh_tx_valid <= 1'b0;
            wh_rx_ready <= 1'b0;

            case (state)
                S_IDLE: begin
                    free_to_cupid <= (!working && !dating_busy && !couple_locked);
                    dating_busy   <= 1'b0;
                    dating_cnt    <= 8'd0;
                    free_wait_cnt <= 8'd0;

                    if (pair_valid_cupid && !working && !couple_locked) begin
                        partner_id_latched   <= partner_id_cupid;
                        partner_pref_latched <= my_pref;
                        dating_busy          <= 1'b1;
                        if (is_initiator)
                            state <= S_PRE_SEND;
                        else
                            state <= S_PRE_RECV;
                    end
                end

                S_PRE_SEND: begin
                    wh_tx_data  <= {MY_ID, my_pref};
                    wh_tx_valid <= 1'b1;
                    if (wh_tx_ready) begin
                        wh_rx_ready <= 1'b1;
                        if (wh_rx_valid) begin
                            partner_id_latched   <= rx_id;
                            partner_pref_latched <= rx_pref;
                            if (!prefs_compatible) begin
                                dating_status_to_cupid <= 4'd1; // PRE_FAIL
                                dating_busy            <= 1'b0;
                                state                  <= S_IDLE;
                            end else begin
                                state <= S_DATING;
                            end
                        end
                    end
                end

                S_PRE_RECV: begin
                    wh_rx_ready <= 1'b1;
                    if (wh_rx_valid) begin
                        partner_id_latched   <= rx_id;
                        partner_pref_latched <= rx_pref;
                        if (!prefs_compatible) begin
                            dating_status_to_cupid <= 4'd1; // PRE_FAIL
                            dating_busy            <= 1'b0;
                            state                  <= S_IDLE;
                        end else begin
                            wh_tx_data  <= {MY_ID, my_pref};
                            wh_tx_valid <= 1'b1;
                            if (wh_tx_ready)
                                state <= S_DATING;
                        end
                    end
                end

                S_DATING: begin
                    free_to_cupid <= 1'b0;
                    dating_busy   <= 1'b1;

                    dating_cnt <= dating_cnt + 8'd1;

                    if (task_valid && !working) begin
                        free_wait_cnt <= free_wait_cnt + 8'd1;
                        if (free_wait_cnt > 8'd50) begin
                            dating_status_to_cupid <= 4'd2; // imbalance breakup
                            dating_busy            <= 1'b0;
                            state                  <= S_IDLE;
                        end
                    end

                    if (!hot_cold_ok || !latency_ok) begin
                        if (error_counters < 8'hFF)
                            error_counters <= error_counters + 1'b1;
                    end

                    if (error_counters > 8'd10) begin
                        dating_status_to_cupid <= 4'd3; // ERROR_BREAK
                        dating_busy            <= 1'b0;
                        state                  <= S_IDLE;
                    end else if (dating_cnt >= DATE_LEN) begin
                        couple_locked          <= 1'b1;
                        dating_busy            <= 1'b0;
                        dating_status_to_cupid <= 4'd4; // COUPLED
                        state                  <= S_COUPLED;
                    end
                end

                S_COUPLED: begin
                    free_to_cupid <= 1'b0;
                    dating_busy   <= 1'b0;
                    // stay coupled; can still do tasks
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

