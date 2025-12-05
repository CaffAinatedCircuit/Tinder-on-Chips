`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.12.2025 20:19:05
// Design Name: 
// Module Name: wormhole_fabric
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
// wormhole_fabric: very simple single-clock router
//============================================================
module wormhole_fabric #(
    parameter N_NODES = 4,
    parameter ID_W    = 4,
    parameter PREF_W  = 8
)(
    input                        clk_global,
    input                        rst_n,

    input      [N_NODES*(ID_W+PREF_W)-1:0] src_data_flat,
    input      [N_NODES-1:0]              src_valid,
    output reg [N_NODES-1:0]              src_ready,

    output reg [N_NODES*(ID_W+PREF_W)-1:0] dst_data_flat,
    output reg [N_NODES-1:0]               dst_valid,
    input      [N_NODES-1:0]               dst_ready,

    input      [N_NODES*ID_W-1:0]          route_dst_id_flat
);

    localparam DATA_W = ID_W + PREF_W;

    // internal array views
    reg [DATA_W-1:0] src_data [0:N_NODES-1];
    reg [DATA_W-1:0] dst_data [0:N_NODES-1];
    reg [ID_W-1:0]   route_dst_id [0:N_NODES-1];

    genvar gi;
    generate
        for (gi = 0; gi < N_NODES; gi = gi + 1) begin : UNPACK
            always @(*) begin
                src_data[gi]      = src_data_flat     [gi*DATA_W +: DATA_W];
                route_dst_id[gi]  = route_dst_id_flat [gi*ID_W   +: ID_W];
            end
            always @(*) begin
                dst_data_flat[gi*DATA_W +: DATA_W] = dst_data[gi];
            end
        end
    endgenerate

    integer i;

    always @(posedge clk_global or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N_NODES; i = i + 1) begin
                src_ready[i] <= 1'b0;
                dst_valid[i] <= 1'b0;
                dst_data[i]  <= {DATA_W{1'b0}};
            end
        end else begin
            // defaults
            for (i = 0; i < N_NODES; i = i + 1) begin
                src_ready[i] <= 1'b0;
                if (dst_valid[i] && dst_ready[i])
                    dst_valid[i] <= 1'b0;
            end

            // simple: if src_valid, forward to its configured dest if free
            for (i = 0; i < N_NODES; i = i + 1) begin
                if (src_valid[i]) begin
                    if (!dst_valid[route_dst_id[i]]) begin
                        dst_data[route_dst_id[i]]  <= src_data[i];
                        dst_valid[route_dst_id[i]] <= 1'b1;
                        src_ready[i]               <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
