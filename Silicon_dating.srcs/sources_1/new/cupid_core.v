`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.12.2025 20:18:24
// Design Name: 
// Module Name: cupid_core
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
// cupid_core: matchmaker with flattened ports
//============================================================
module cupid_core #(
    parameter N_NODES = 4,
    parameter ID_W    = 4
)(
    input                     clk_global,
    input                     rst_n,

    input      [N_NODES-1:0]  free_from_node,
    input      [N_NODES-1:0]  dating_busy_from_node,
    input      [N_NODES-1:0]  couple_locked_from_node,

    input      [N_NODES*16-1:0] node_clk_est_flat,
    input      [N_NODES*8 -1:0] node_temp_est_flat,
    input      [N_NODES*8 -1:0] node_latency_est_flat,
    input      [N_NODES*8 -1:0] node_error_ctr_flat,
    input      [N_NODES*4 -1:0] node_dating_status_flat,

    output reg [N_NODES*ID_W-1:0] partner_id_to_node_flat,
    output reg [N_NODES-1:0]      pair_valid_to_node,
    output reg [N_NODES-1:0]      initiator_flag_to_node,
    output reg [N_NODES*4-1:0]    breakup_reason_to_node_flat,

    output reg [N_NODES*ID_W-1:0] route_dst_id_flat
);

    // Internal array views
    reg [15:0] node_clk_est      [0:N_NODES-1];
    reg [7:0]  node_temp_est     [0:N_NODES-1];
    reg [7:0]  node_latency_est  [0:N_NODES-1];
    reg [7:0]  node_error_ctr    [0:N_NODES-1];
    reg [3:0]  node_dating_status[0:N_NODES-1];

    reg [ID_W-1:0] partner_id_to_node   [0:N_NODES-1];
    reg [3:0]      breakup_reason_to_node[0:N_NODES-1];
    reg [ID_W-1:0] route_dst_id         [0:N_NODES-1];

    genvar gi;
    generate
        for (gi = 0; gi < N_NODES; gi = gi + 1) begin : UNPACK_IN
            always @(*) begin
                node_clk_est[gi]       = node_clk_est_flat      [gi*16 +: 16];
                node_temp_est[gi]      = node_temp_est_flat     [gi*8  +: 8];
                node_latency_est[gi]   = node_latency_est_flat  [gi*8  +: 8];
                node_error_ctr[gi]     = node_error_ctr_flat    [gi*8  +: 8];
                node_dating_status[gi] = node_dating_status_flat[gi*4  +: 4];
            end
        end
    endgenerate

    generate
        for (gi = 0; gi < N_NODES; gi = gi + 1) begin : PACK_OUT
            always @(*) begin
                partner_id_to_node_flat   [gi*ID_W +: ID_W] = partner_id_to_node[gi];
                breakup_reason_to_node_flat[gi*4   +: 4]    = breakup_reason_to_node[gi];
                route_dst_id_flat         [gi*ID_W +: ID_W] = route_dst_id[gi];
            end
        end
    endgenerate

    integer i, j;
    reg [ID_W-1:0] sel_i;
    reg [ID_W-1:0] sel_j;
    reg            found_pair;

    always @(posedge clk_global or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N_NODES; i = i + 1) begin
                partner_id_to_node[i]      <= {ID_W{1'b0}};
                pair_valid_to_node[i]      <= 1'b0;
                initiator_flag_to_node[i]  <= 1'b0;
                breakup_reason_to_node[i]  <= 4'd0;
                route_dst_id[i]            <= {ID_W{1'b0}};
            end
        end else begin
            // defaults
            for (i = 0; i < N_NODES; i = i + 1) begin
                pair_valid_to_node[i]     <= 1'b0;
                initiator_flag_to_node[i] <= 1'b0;
            end

            // record status (could be extended)
            for (i = 0; i < N_NODES; i = i + 1)
                if (node_dating_status[i] != 4'd0)
                    breakup_reason_to_node[i] <= node_dating_status[i];

            // search for a pair
            found_pair = 1'b0;
            sel_i      = {ID_W{1'b0}};
            sel_j      = {ID_W{1'b0}};

            for (i = 0; i < N_NODES; i = i + 1) begin
                if (!found_pair &&
                    free_from_node[i] &&
                    !dating_busy_from_node[i] &&
                    !couple_locked_from_node[i]) begin

                    for (j = i+1; j < N_NODES; j = j + 1) begin
                        if (!found_pair &&
                            free_from_node[j] &&
                            !dating_busy_from_node[j] &&
                            !couple_locked_from_node[j]) begin

                            // simple latency closeness check
                            if ((node_latency_est[i] > node_latency_est[j] ?
                                 (node_latency_est[i] - node_latency_est[j]) :
                                 (node_latency_est[j] - node_latency_est[i])) < 8'd20) begin
                                found_pair = 1'b1;
                                sel_i      = i[ID_W-1:0];
                                sel_j      = j[ID_W-1:0];
                            end
                        end
                    end
                end
            end

            if (found_pair) begin
                partner_id_to_node[sel_i]     <= sel_j;
                partner_id_to_node[sel_j]     <= sel_i;
                pair_valid_to_node[sel_i]     <= 1'b1;
                pair_valid_to_node[sel_j]     <= 1'b1;
                initiator_flag_to_node[sel_i] <= 1'b1; // sel_i initiator
                initiator_flag_to_node[sel_j] <= 1'b0;

                route_dst_id[sel_i] <= sel_j;
                route_dst_id[sel_j] <= sel_i;
            end
        end
    end

endmodule
