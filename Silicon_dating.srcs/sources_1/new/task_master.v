`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.12.2025 20:16:41
// Design Name: 
// Module Name: task_master
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
// task_master: staggered jobs with alternate rates
//============================================================
module task_master #(
    parameter N_NODES = 4
)(
    input                     clk_global,
    input                     rst_n,
    output reg [N_NODES-1:0]  task_valid,
    output reg [N_NODES-1:0]  task_alt_rate,
    input      [N_NODES-1:0]  task_done,
    input      [N_NODES-1:0]  couple_locked
);

    reg [15:0] cnt;
    integer i;

    always @(posedge clk_global or negedge rst_n) begin
        if (!rst_n) begin
            cnt           <= 16'd0;
            task_valid    <= {N_NODES{1'b0}};
            task_alt_rate <= {N_NODES{1'b0}};
        end else begin
            cnt <= cnt + 16'd1;

            task_valid    <= {N_NODES{1'b0}};
            task_alt_rate <= {N_NODES{1'b0}};

            // simple periodic task issue
            for (i = 0; i < N_NODES; i = i + 1) begin
                if (cnt[7:0] == (i * 16)) begin
                    if (!couple_locked[i]) begin
                        task_valid[i]    <= 1'b1;
                        task_alt_rate[i] <= cnt[8]; // toggle job length
                    end
                end
            end
        end
    end

endmodule

