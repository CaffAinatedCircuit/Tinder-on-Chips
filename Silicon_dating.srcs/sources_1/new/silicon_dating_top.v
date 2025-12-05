`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.12.2025 20:12:13
// Design Name: 
// Module Name: silicon_dating_top
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
// Top-level: silicon_dating_top
//============================================================
module silicon_dating_top #(
    parameter N_NODES = 4,
    parameter ID_W    = 4,
    parameter PREF_W  = 8
)(
    input              clk_global,
    input              rst_n,
    output [7:0]       debug_leds
);

    // One-bit per node signals
    wire [N_NODES-1:0] task_valid;
    wire [N_NODES-1:0] task_alt_rate;
    wire [N_NODES-1:0] task_done;

    wire [N_NODES-1:0] free_to_cupid;
    wire [N_NODES-1:0] dating_busy;
    wire [N_NODES-1:0] couple_locked;

    wire [N_NODES-1:0] pair_valid_to_node;
    wire [N_NODES-1:0] initiator_flag_to_node;

    // Flattened multi-node buses
    wire [N_NODES*ID_W-1:0] partner_id_to_node_flat;
    wire [N_NODES*4-1:0]    breakup_reason_to_node_flat;
    wire [N_NODES*4-1:0]    node_dating_status_flat;
    wire [N_NODES*ID_W-1:0] route_dst_id_flat;

    wire [N_NODES*16-1:0]   node_clk_est_flat;
    wire [N_NODES*8-1:0]    node_temp_est_flat;
    wire [N_NODES*8-1:0]    node_latency_est_flat;
    wire [N_NODES*8-1:0]    node_error_ctr_flat;

    // Wormhole (flattened)
    localparam DATA_W = ID_W + PREF_W;
    wire [N_NODES*DATA_W-1:0] wh_src_data_flat;
    wire [N_NODES-1:0]        wh_src_valid;
    wire [N_NODES-1:0]        wh_src_ready;

    wire [N_NODES*DATA_W-1:0] wh_dst_data_flat;
    wire [N_NODES-1:0]        wh_dst_valid;
    wire [N_NODES-1:0]        wh_dst_ready;

    //========================================================
    // Task Master
    //========================================================
    task_master #(
        .N_NODES (N_NODES)
    ) u_task_master (
        .clk_global    (clk_global),
        .rst_n         (rst_n),
        .task_valid    (task_valid),
        .task_alt_rate (task_alt_rate),
        .task_done     (task_done),
        .couple_locked (couple_locked)
    );

    //========================================================
    // Cupid Core
    //========================================================
    cupid_core #(
        .N_NODES (N_NODES),
        .ID_W    (ID_W)
    ) u_cupid_core (
        .clk_global               (clk_global),
        .rst_n                    (rst_n),

        .free_from_node           (free_to_cupid),
        .dating_busy_from_node    (dating_busy),
        .couple_locked_from_node  (couple_locked),

        .node_clk_est_flat        (node_clk_est_flat),
        .node_temp_est_flat       (node_temp_est_flat),
        .node_latency_est_flat    (node_latency_est_flat),
        .node_error_ctr_flat      (node_error_ctr_flat),
        .node_dating_status_flat  (node_dating_status_flat),

        .partner_id_to_node_flat  (partner_id_to_node_flat),
        .pair_valid_to_node       (pair_valid_to_node),
        .initiator_flag_to_node   (initiator_flag_to_node),
        .breakup_reason_to_node_flat(breakup_reason_to_node_flat),

        .route_dst_id_flat        (route_dst_id_flat)
    );

    //========================================================
    // Wormhole Fabric (single-clock)
    //========================================================
    wormhole_fabric #(
        .N_NODES (N_NODES),
        .ID_W    (ID_W),
        .PREF_W  (PREF_W)
    ) u_wormhole_fabric (
        .clk_global   (clk_global),
        .rst_n        (rst_n),
        .src_data_flat(wh_src_data_flat),
        .src_valid    (wh_src_valid),
        .src_ready    (wh_src_ready),
        .dst_data_flat(wh_dst_data_flat),
        .dst_valid    (wh_dst_valid),
        .dst_ready    (wh_dst_ready),
        .route_dst_id_flat(route_dst_id_flat)
    );

    //========================================================
    // Person Nodes
    //========================================================
    genvar gi;
    generate
        for (gi = 0; gi < N_NODES; gi = gi + 1) begin : GEN_NODES
            person_node #(
                .ID       (gi),
                .ID_W     (ID_W),
                .PREF_W   (PREF_W),
                .DATE_LEN (64)
            ) u_person_node (
                .clk_task        (clk_global),
                .clk_async       (clk_global), // later: different clocks per node
                .rst_n           (rst_n),

                .task_valid      (task_valid[gi]),
                .task_alt_rate   (task_alt_rate[gi]),
                .task_done       (task_done[gi]),

                .free_to_cupid   (free_to_cupid[gi]),
                .dating_busy     (dating_busy[gi]),
                .couple_locked   (couple_locked[gi]),

                .partner_id_cupid(partner_id_to_node_flat[gi*ID_W +: ID_W]),
                .pair_valid_cupid(pair_valid_to_node[gi]),
                .is_initiator    (initiator_flag_to_node[gi]),
                .breakup_reason_from_cupid(
                    breakup_reason_to_node_flat[gi*4 +: 4]
                ),
                .dating_status_to_cupid(
                    node_dating_status_flat[gi*4 +: 4]
                ),

                .clk_est         (node_clk_est_flat[gi*16 +: 16]),
                .temp_est        (node_temp_est_flat[gi*8 +: 8]),
                .latency_est     (node_latency_est_flat[gi*8 +: 8]),
                .error_counters  (node_error_ctr_flat[gi*8 +: 8]),

                .wh_tx_data      (wh_src_data_flat[gi*DATA_W +: DATA_W]),
                .wh_tx_valid     (wh_src_valid[gi]),
                .wh_tx_ready     (wh_src_ready[gi]),
                .wh_rx_data      (wh_dst_data_flat[gi*DATA_W +: DATA_W]),
                .wh_rx_valid     (wh_dst_valid[gi]),
                .wh_rx_ready     (wh_dst_ready[gi])
            );
        end
    endgenerate

    // Simple debug: number of coupled nodes
    reg [7:0] couple_count;
    integer k;
    always @(posedge clk_global or negedge rst_n) begin
        if (!rst_n) begin
            couple_count <= 8'd0;
        end else begin
            couple_count <= 8'd0;
            for (k = 0; k < N_NODES; k = k + 1) begin
                couple_count <= couple_count + (couple_locked[k] ? 1'b1 : 1'b0);
            end
        end
    end

    assign debug_leds = couple_count;

endmodule
