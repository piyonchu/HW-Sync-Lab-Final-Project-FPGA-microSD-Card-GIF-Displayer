module vga_sync (
    input wire clk, reset,
    output wire hsync, vsync, video_on,
    output wire p_tick,  // Kept for compatibility but not used in top module
    output wire [9:0] x, y
);
    // constant declarations for VGA sync parameters
    localparam H_DISPLAY = 640; // horizontal display area
    localparam H_L_BORDER = 48; // horizontal left border
    localparam H_R_BORDER = 16; // horizontal right border
    localparam H_RETRACE = 96; // horizontal retrace
    localparam H_MAX = H_DISPLAY + H_L_BORDER + H_R_BORDER + H_RETRACE - 1;
    localparam START_H_RETRACE = H_DISPLAY + H_R_BORDER;
    localparam END_H_RETRACE = H_DISPLAY + H_R_BORDER + H_RETRACE - 1;
    
    localparam V_DISPLAY = 480; // vertical display area
    localparam V_T_BORDER = 10; // vertical top border
    localparam V_B_BORDER = 33; // vertical bottom border
    localparam V_RETRACE = 2; // vertical retrace
    localparam V_MAX = V_DISPLAY + V_T_BORDER + V_B_BORDER + V_RETRACE - 1;
    localparam START_V_RETRACE = V_DISPLAY + V_B_BORDER;
    localparam END_V_RETRACE = V_DISPLAY + V_B_BORDER + V_RETRACE - 1;

    // Remove mod-4 counter since we're already at 25MHz
    // Just pass through the clock signal as pixel_tick
    assign p_tick = 1'b1;  // Always enabled since we're already at 25MHz

    // registers to keep track of current pixel location
    reg [9:0] h_count_reg, h_count_next, v_count_reg, v_count_next;
    // register to keep track of vsync and hsync signal states
    reg vsync_reg, hsync_reg;
    wire vsync_next, hsync_next;

    // infer registers
    always @(posedge clk, posedge reset)
        if(reset) begin
            v_count_reg <= 0;
            h_count_reg <= 0;
            vsync_reg <= 0;
            hsync_reg <= 0;
        end
        else begin
            v_count_reg <= v_count_next;
            h_count_reg <= h_count_next;
            vsync_reg <= vsync_next;
            hsync_reg <= hsync_next;
        end

    // next-state logic of horizontal vertical sync counters
    // No need for pixel_tick since we're already at 25MHz
    always @* begin
        h_count_next = h_count_reg == H_MAX ? 0 : h_count_reg + 1;
        v_count_next = h_count_reg == H_MAX ? 
                      (v_count_reg == V_MAX ? 0 : v_count_reg + 1) : 
                      v_count_reg;
    end

    // hsync and vsync are active low signals
    // hsync signal asserted during horizontal retrace
    assign hsync_next = h_count_reg >= START_H_RETRACE && h_count_reg <= END_H_RETRACE;
    // vsync signal asserted during vertical retrace
    assign vsync_next = v_count_reg >= START_V_RETRACE && v_count_reg <= END_V_RETRACE;

    // video only on when pixels are in both horizontal and vertical display region
    assign video_on = (h_count_reg < H_DISPLAY) && (v_count_reg < V_DISPLAY);

    // output signals
    assign hsync = hsync_reg;
    assign vsync = vsync_reg;
    assign x = h_count_reg;
    assign y = v_count_reg;
endmodule