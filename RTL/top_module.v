module top(
    input wire          clk100mhz,           // Clock input
    input wire          reset,               // Reset button
    input wire          btn,                 // Button to change sectors
    input wire          filter_btn,          // Button for toggling filters/effects
    input               miso,                // SD card data input
    output              mosi,                // SD card data output
    output              sclk,                // SD card clock
    output              cs,                  // SD card chip select
    output reg          [15:0] led,          // LED output for debugging - displays checksum when done
    
    // VGA outputs
    input wire [15:0]   sw,
    output wire         hsync,               // VGA horizontal sync
    output wire         vsync,               // VGA vertical sync
    output wire         [3:0] vga_r,         // VGA red channel
    output wire         [3:0] vga_g,         // VGA green channel
    output wire         [3:0] vga_b          // VGA blue channel
);
    reg        done;
    // Clock and reset signals
    wire       clk;            // 25MHz clock for SD card operation
    wire       locked;         // PLL locked signal
    wire       rst = ~locked | reset;  // Reset is active when PLL is not locked OR reset input is high
    
    // Debounced button signals
    wire       btn_debounced;
    wire       filter_btn_debounced;
    reg        btn_prev = 0;
    reg        btn_pressed = 0;
    reg        filter_btn_prev = 0;
    reg        filter_btn_pressed = 0;
    
    // Display mode enumeration (0:Normal, 1:Inverse, 2:Grayscale, 3:HSV Hue Shift)
    reg [1:0]  display_mode = 0;
    
    // Parameters for hue shift effect
    parameter HUE_SPEED = 2;                 // Speed of hue shifting (incrementing steps)
    
    // Counters and state registers for HSV effect
    reg [7:0] current_hue = 0;              // Current hue value (0-255 for the module)
    
    // Buffer storage instead of block RAM
    // 18432 16-bit words = 36864 bytes = 72 sectors (each sector is 512 bytes)
    reg [15:0] buffer [0:18431];  // 16-bit wide, 18432 entries deep
    reg [14:0] buffer_addr_write = 0;   // Address for writing to buffer
    reg [14:0] buffer_addr_read;       // Address for reading from buffer (for VGA) - NOW REGISTERED
    
    // Byte pairing for 16-bit buffer storage
    reg [7:0]  byte_buffer;     // Buffer for first byte in the pair
    reg        byte_ready = 0;  // Flag indicating byte buffer has data
    
    // Checksum calculation
    reg [31:0] checksum = 0;        // Holds the running sum (needs to be 32-bit to handle overflow before modulo)
    reg [14:0] checksum_addr = 0;   // Address counter for reading buffer during checksum calculation
    reg [1:0]  checksum_state = 0;  // Sub-state for checksum calculation
    
    // SD card controller signals
    reg        rd = 0;          // Read enable for SD controller
    wire [7:0] sd_dout;         // Data from SD controller
    wire       byte_available;  // New byte available from SD controller
    wire       ready;           // SD card is ready for operations
    wire [4:0] status;          // SD controller status
    
    // State machine variables
    reg [3:0]  main_state = INIT;
    parameter  INIT = 0,
               SD_WAIT_READY = 1,
               READ_SD = 2,
               WAIT_SECTOR = 3,
               DONE = 4,
               CALCULATE_CHECKSUM = 5,
               DISPLAY_CHECKSUM = 6;
    
    // Sector reading logic
    reg [31:0] current_sector = 32'd0;    // Current sector being read (0-71)
    reg [31:0] sector_base = 32'd0;       // Base sector for the current group
    reg [9:0]  bytes_read = 0;            // Counter for bytes read in current sector
    reg        reading = 0;               // Flag to indicate reading in progress
    reg [6:0]  sectors_read = 0;          // Counter for number of sectors read (0-71)
    
    // Flag to indicate button was pressed, used to communicate between always blocks
    reg        change_sector_group = 0;
    
    // VGA-related signals
    wire       video_on;         // VGA display active area
    wire       p_tick;           // 25MHz pixel clock tick
    wire [9:0] pixel_x, pixel_y; // Current pixel coordinates
    
    // Debug register for pixel data display - separate from main LED output
    reg [15:0] debug_pixel;
    
    // Animation control
    reg [2:0]  current_frame = 0;      // Current frame being displayed (0-5)
    reg [23:0] frame_counter = 0;      // Counter for frame rate control
    parameter  FRAME_RATE_DIVIDER = 24'd2500000; // Adjustable frame rate (~10 FPS at 25MHz)
    
    // Hue shifter control signals
    reg         hue_shift_start;
    wire        hue_shift_done;
    wire [15:0] hue_shifted_pixel;
    
    // Registered versions of intermediate signals to break long timing paths
    reg [15:0] pixel_data_reg;          // Registered version of pixel data
    reg [15:0] processed_pixel_reg;     // Registered version of processed pixel
    reg video_on_reg;                   // Registered version of video_on signal
    
    // Intermediate calculation registers for grayscale
    reg [15:0] gray_temp_1, gray_temp_2, gray_temp_3;
    reg [7:0] gray_value_reg;
    reg [15:0] grayscale_pixel_reg;
    
    // Pipeline registers to break combinational paths
    reg [12:0] scaled_x_reg, scaled_y_reg;
    reg [12:0] buffer_pixel_addr_reg;
    reg [14:0] frame_base_addr_reg;
    
    // Clock wizard instance for 25MHz clock
    clk_wiz_0 u_clk_wiz_0 (
        .reset       (reset),
        .clk_in1     (clk100mhz),       // input 100MHz
        .locked      (locked),
        .clk_out1    (clk)              // output 25MHz
    );
    
    // Button debouncers
    debounce btn_debouncer (
        .clk         (clk),
        .reset       (rst),
        .btn_in      (btn),
        .btn_out     (btn_debounced)
    );
    
    debounce filter_btn_debouncer (
        .clk         (clk),
        .reset       (rst),
        .btn_in      (filter_btn),
        .btn_out     (filter_btn_debounced)
    );
    
    vga_sync vga_sync_unit (
        .clk(clk),
        .reset(rst),
        .hsync(hsync),
        .vsync(vsync),
        .video_on(video_on),
        .p_tick(p_tick),
        .x(pixel_x),
        .y(pixel_y)
    );
    
    // Color and pixel address calculation
    wire [15:0] pixel_data;         // Original pixel color data from buffer
    reg [15:0] processed_pixel;     // Final pixel data after filters/effects applied
    reg [12:0] scaled_x, scaled_y;
    reg [12:0] buffer_pixel_addr;
    reg [14:0] frame_base_addr;
    
    // Color components of the original pixel (RGB565 format) - NOW REGISTERED
    reg [4:0] orig_r;
    reg [5:0] orig_g;
    reg [4:0] orig_b;
    
    // Extended color components (to avoid truncation in calculations) - NOW REGISTERED
    reg [7:0] ext_r;
    reg [7:0] ext_g;
    reg [7:0] ext_b;
    
    // Grayscale calculation using weighted luminance (approximation)
    // Y = (R + 2G + B)/4 - simplified from Y = 0.299R + 0.587G + 0.114B
    // PIPELINED VERSION OF: wire [15:0] gray_temp = 77 * ext_r + 150 * ext_g + 29 * ext_b;
    // wire [7:0] gray_value = gray_temp[15:8];  // Divide by 256 by taking upper 8 bits
    
    // Convert grayscale back to RGB565 format - NOW REGISTERED
    reg [4:0] gray_r;
    reg [5:0] gray_g;
    reg [4:0] gray_b;
    reg [15:0] grayscale_pixel;
    
    // Instantiate the HSV shifter module
    hue_shifter hue_shifter (
        .clk(clk),
        .reset(rst),
        .rgb_in(pixel_data_reg),     // Feed registered version of pixel data
        .hue_out(current_hue),
        .start(hue_shift_start),
        .rgb_out(hue_shifted_pixel),
        .done(hue_shift_done)
    );
    
    // Timer for updating hue value for the animation effect
    reg [21:0] hue_update_counter = 0;
    parameter HUE_UPDATE_INTERVAL = 22'd250000; // Update hue every 10ms at 25MHz
    
    // Update hue value based on counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_hue <= 0;
            hue_update_counter <= 0;
        end else begin
            // Increment counter
            hue_update_counter <= hue_update_counter + 1;
            
            // Update hue periodically
            if (hue_update_counter >= HUE_UPDATE_INTERVAL) begin
                current_hue <= current_hue + HUE_SPEED; // Will automatically wrap around at 256
                hue_update_counter <= 0;
            end
        end
    end
    
    // Scale coordinates from 640x480 to 64x48 - PIPELINED
    always @(posedge clk) begin
        // Pipeline stage 1: Calculate scaled coordinates
        scaled_x <= pixel_x / 10;  // 640/64 = 10
        scaled_y <= pixel_y / 10;  // 480/48 = 10
        
        // Calculate base address for current frame (each frame is 64x48 = 3072 pixels)
        frame_base_addr <= current_frame * 3072;
        
        // Pipeline stage 2: Register the scaled coordinates
        scaled_x_reg <= scaled_x;
        scaled_y_reg <= scaled_y;
        frame_base_addr_reg <= frame_base_addr;
        
        // Pipeline stage 3: Calculate buffer address using registered coordinates
        buffer_pixel_addr <= (scaled_y_reg * 64) + scaled_x_reg;
        buffer_pixel_addr_reg <= buffer_pixel_addr;
        
        // Pipeline stage 4: Calculate final buffer read address
        buffer_addr_read <= (scaled_x_reg < 64 && scaled_y_reg < 48) ? 
                           frame_base_addr_reg + buffer_pixel_addr_reg : 
                           frame_base_addr_reg; // Default to first pixel if out of bounds
    end
    
    // Register video_on signal to match pipeline delay
    always @(posedge clk) begin
        video_on_reg <= video_on;
    end
    
    // Get data from buffer and register it
    assign pixel_data = (video_on_reg && main_state == DONE) ? buffer[buffer_addr_read] : 16'h0000;
    
    always @(posedge clk) begin
        pixel_data_reg <= pixel_data;
        
        // Extract and register RGB components
        orig_r <= pixel_data_reg[15:11];
        orig_g <= pixel_data_reg[10:5];
        orig_b <= pixel_data_reg[4:0];
        
        // Extend color components to 8 bits
        ext_r <= {orig_r, orig_r[4:2]};     // Extend to 8 bits
        ext_g <= {orig_g, orig_g[5:4]};     // Extend to 8 bits
        ext_b <= {orig_b, orig_b[4:2]};     // Extend to 8 bits
        
        // Pipeline the grayscale calculation
        gray_temp_1 <= 77 * ext_r;
        gray_temp_2 <= 150 * ext_g;
        gray_temp_3 <= 29 * ext_b;
        gray_value_reg <= (gray_temp_1 + gray_temp_2 + gray_temp_3) >> 8; // Divide by 256
        
        // Convert grayscale back to RGB565
        gray_r <= gray_value_reg[7:3];
        gray_g <= gray_value_reg[7:2];
        gray_b <= gray_value_reg[7:3];
        grayscale_pixel <= {gray_r, gray_g, gray_b};
        grayscale_pixel_reg <= grayscale_pixel;
    end
    
    // Trigger the HSV shifter for each pixel when in HSV mode
    always @(posedge clk) begin
        if (rst) begin
            hue_shift_start <= 0;
        end else if (display_mode == 3 && video_on_reg) begin
            // Start HSV shifting for this pixel
            hue_shift_start <= 1;
        end else begin
            hue_shift_start <= 0;
        end
    end
    
    // Apply the selected display mode to the pixel
    always @(posedge clk) begin
        case (display_mode)
            0: processed_pixel <= pixel_data_reg;           // Normal mode
            1: processed_pixel <= ~pixel_data_reg;          // Inverse mode
            2: processed_pixel <= grayscale_pixel_reg;      // Grayscale mode
            3: processed_pixel <= hue_shifted_pixel;        // HSV hue shift mode using the module
            default: processed_pixel <= pixel_data_reg;     // Default to normal
        endcase
        
        processed_pixel_reg <= processed_pixel;
    end
    
    // Extract RGB components for VGA output - REGISTERED OUTPUT
    assign vga_r = video_on_reg ? processed_pixel_reg[15:12] : 4'h0; // Red: bits 15-11, take top 4
    assign vga_g = video_on_reg ? processed_pixel_reg[10:7] : 4'h0;  // Green: bits 10-5, take top 4
    assign vga_b = video_on_reg ? processed_pixel_reg[4:1] : 4'h0;   // Blue: bits 4-0, take top 4
    
    // Frame rate control and animation
    always @(posedge clk) begin
        if (rst) begin
            current_frame <= 0;
            frame_counter <= 0;
        end else if (main_state == DONE) begin
            // Frame animation control
            if (frame_counter >= FRAME_RATE_DIVIDER) begin
                frame_counter <= 0;
                // Move to next frame, cycle through all 6 frames
                if (current_frame == 5)
                    current_frame <= 0;
                else
                    current_frame <= current_frame + 1;
            end else begin
                frame_counter <= frame_counter + 1;
            end
        end
    end
    
    // Button edge detection for both buttons
    always @(posedge clk) begin
        if (rst) begin
            btn_prev <= 0;
            btn_pressed <= 0;
            filter_btn_prev <= 0;
            filter_btn_pressed <= 0;
            change_sector_group <= 0;
            display_mode <= 0;
        end else begin
            // Sector change button
            btn_prev <= btn_debounced;
            btn_pressed <= ~btn_prev & btn_debounced; // Rising edge detection
            
            // Set the flag when button is pressed and we're in DONE state
            if (btn_pressed && main_state == DONE) begin
                change_sector_group <= 1;
            end else begin
                change_sector_group <= 0;
            end
            
            // Filter/effect toggle button
            filter_btn_prev <= filter_btn_debounced;
            filter_btn_pressed <= ~filter_btn_prev & filter_btn_debounced; // Rising edge detection
            
            // Cycle through display modes when filter button is pressed
            if (filter_btn_pressed) begin
                display_mode <= display_mode + 1; // Cycles through 0,1,2,3
            end
        end
    end
    
    // Main state machine
    always @(posedge clk) begin
        if (rst) begin
            main_state <= INIT;
            rd <= 0;
            reading <= 0;
            buffer_addr_write <= 0;
            bytes_read <= 0;
            led <= 16'h0000;
            done <= 0;
            byte_ready <= 0;
            checksum <= 0;
            checksum_addr <= 0;
            checksum_state <= 0;
            // Initialize sector variables
            sector_base <= 32'd0;
            current_sector <= 32'd0;
            sectors_read <= 0;
        end else begin
            // Handle sector group change request from button press
            if (change_sector_group) begin
                // Change sector group when button is pressed and we're in DONE state
                // Cycle through the 6 sector groups
                if (sector_base == 0)          sector_base <= 32'd100;    // Move to Sectors 100-171
                else if (sector_base == 100)   sector_base <= 32'd200;    // Move to Sectors 200-271
                else if (sector_base == 200)   sector_base <= 32'd300;    // Move to Sectors 300-371
                else if (sector_base == 300)   sector_base <= 32'd400;    // Move to Sectors 400-471
                else if (sector_base == 400)   sector_base <= 32'd0;      // Back to Sectors 0-71
                else                           sector_base <= 32'd0;      // Default case
                
                // Reset current sector to base sector
                current_sector <= sector_base;
                sectors_read <= 0;
                buffer_addr_write <= 0;  // Reset buffer address for new sector group
                main_state <= INIT;
            end else begin
                // Normal state machine operation
                case (main_state)
                    INIT: begin
                        main_state <= SD_WAIT_READY;
                        bytes_read <= 0;
                        rd <= 0;
                        reading <= 0;
                        byte_ready <= 0;
                        
                        // Use current sector position
                        current_sector <= sector_base + sectors_read;
                        
                        if (sectors_read >= 72) begin
                            done <= 1;  // Signal all sectors are read
                            main_state <= DONE;
                        end else begin
                            done <= 0;
                        end
                    end
                    
                    SD_WAIT_READY: begin
                        // Wait for SD card to be ready
                        if (ready) begin
                            main_state <= READ_SD;
                        end
                    end
                    
                    READ_SD: begin
                        // Start reading if not already reading
                        if (ready && !reading && !rd) begin
                            rd <= 1;
                            reading <= 1;
                        end else if (rd) begin
                            rd <= 0;  // Clear read signal after one clock cycle
                        end
                        
                        // Process bytes from SD card
                        if (reading && byte_available) begin
                            // Handle 16-bit buffer writing (pair of bytes)
                            if (!byte_ready) begin
                                // Store first byte
                                byte_buffer <= sd_dout;
                                byte_ready <= 1;
                            end else begin
                                // Combine with second byte and write to buffer
                                buffer[buffer_addr_write] <= {byte_buffer, sd_dout};
                                buffer_addr_write <= buffer_addr_write + 1;
                                byte_ready <= 0;
                            end
                            
                            bytes_read <= bytes_read + 1;
                            
                            // Check if we've read a full sector (512 bytes)
                            if (bytes_read == 511) begin
                                reading <= 0;      // Stop reading
                                main_state <= WAIT_SECTOR;
                                sectors_read <= sectors_read + 1;  // Increment sector counter
                            end
                        end
                        
                        // Handle read completion
                        if (reading && ready && !byte_available && bytes_read > 0) begin
                            reading <= 0;
                            main_state <= WAIT_SECTOR;
                            sectors_read <= sectors_read + 1;  // Increment sector counter
                        end
                    end
                    
                    WAIT_SECTOR: begin
                        // Wait until SD controller is ready again
                        if (ready) begin
                            if (sectors_read < 72) begin
                                main_state <= INIT;  // Read next sector
                            end else begin
                                main_state <= CALCULATE_CHECKSUM;  // All sectors read, calculate checksum
                                checksum <= 0;       // Reset checksum
                                checksum_addr <= 0;  // Start from first buffer address
                                checksum_state <= 0; // Reset checksum calculation state
                                done <= 1;           // Signal all sectors are read
                            end
                        end
                    end
                    
                    CALCULATE_CHECKSUM: begin
                        case (checksum_state)
                            0: begin
                                // Add the current buffer value to checksum
                                checksum <= (checksum + buffer[checksum_addr]) % 65521; // Modulo 65521 (largest prime under 16 bits)
                                checksum_state <= 1;
                            end
                            1: begin
                                // Move to next address or finish
                                if (checksum_addr < buffer_addr_write - 1) begin // Check against actual data stored
                                    checksum_addr <= checksum_addr + 1;
                                    checksum_state <= 0; // Go back to state 0 for next read
                                end else begin
                                    main_state <= DISPLAY_CHECKSUM;
                                end
                                checksum_state <= 0;
                            end
                        endcase
                    end
                    
                    DISPLAY_CHECKSUM: begin
                        // Display the checksum on LEDs
                        main_state <= DONE;     // Move to DONE state
                    end
                    
                    DONE: begin
                        // Wait for button press to change sector group
                        done <= 1;  // Signal all sectors are read
                        // Show display mode on LED[15:14], current hue on LED[13:6] and last pixel data on LED[5:0]
                        led <= {display_mode, current_hue, buffer[frame_base_addr_reg + ((47 * 64) + 63)][5:0]};
                    end
                    
                    default: main_state <= INIT;
                endcase
            end
        end
    end
    
    // SD card controller instance
    sd_controller sd_ctrl (
        .cs             (cs),
        .mosi           (mosi),
        .miso           (miso),
        .sclk           (sclk),
        
        .rd             (rd),
        .dout           (sd_dout),
        .byte_available (byte_available),
        
        .wr             (1'b0),               // Not writing to SD card
        .din            (8'h00),              // No input data for writing
        .ready_for_next_byte(),               // Not used for reading
        
        .reset          (rst),
        .ready          (ready),
        .address        (current_sector),
        .clk            (clk),
        .status         (status)
                        // Unused debug output
    );
    
endmodule

// Button debouncer module
module debounce (
    input      clk,
    input      reset,
    input      btn_in,
    output reg btn_out
);
    parameter DEBOUNCE_PERIOD = 250000;  // 10ms
    
    reg [17:0] counter = 0;
    reg stable = 0;
    
    always @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            btn_out <= btn_in;
            stable <= 1;
        end else begin
            if (btn_in != btn_out && stable) begin
                // Button changed, start debounce counter
                counter <= 0;
                stable <= 0;
            end else if (!stable) begin
                // Increment counter while unstable
                counter <= counter + 1;
                
                // Check if we've waited long enough
                if (counter >= DEBOUNCE_PERIOD) begin
                    btn_out <= btn_in;  // Update the output
                    stable <= 1;        // Mark as stable
                end
            end
        end
    end
endmodule

module hue_shifter (
    input wire clk,
    input wire reset,
    input wire [15:0] rgb_in,     // 16-bit RGB input in 5-6-5 format (RRRRRGGGGGGBBBBB)
    input wire [7:0] hue_out,     // 8-bit new hue value
    input wire start,             // Start signal
    output reg [15:0] rgb_out,    // 16-bit RGB output in 5-6-5 format
    output reg done               // Done signal
);

    // FSM states
    localparam IDLE      = 3'd0;
    localparam EXTRACT   = 3'd1;
    localparam CALC_HSV  = 3'd2;
    localparam SET_HUE   = 3'd3;
    localparam CALC_RGB  = 3'd4;
    localparam PACK      = 3'd5;
    localparam COMPLETE  = 3'd6;
    
    // State register
    reg [2:0] state, next_state;
    
    // RGB components (expanded to 8 bits)
    reg [7:0] r, g, b;
    
    // HSV components (8 bits each)
    reg [7:0] h, s, v;
    reg [7:0] calc_h; // Added separate register for calculated hue
    
    // Intermediate values for RGB to HSV
    reg [7:0] rgb_min, rgb_max, delta;
    reg [15:0] temp; // For intermediate calculations
    
    // Intermediate values for HSV to RGB
    reg [7:0] region, remainder;
    reg [7:0] p, q, t;
    
    // Output RGB components (8 bits each)
    reg [7:0] r_out, g_out, b_out;
    
    // State machine: next state logic
    always @(*) begin
        case (state)
            IDLE:      next_state = start ? EXTRACT : IDLE;
            EXTRACT:   next_state = CALC_HSV;
            CALC_HSV:  next_state = SET_HUE;
            SET_HUE:   next_state = CALC_RGB;
            CALC_RGB:  next_state = PACK;
            PACK:      next_state = COMPLETE;
            COMPLETE:  next_state = IDLE;
            default:   next_state = IDLE;
        endcase
    end
    
    // State machine: sequential logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
        end else begin
            state <= next_state;
            if (state == COMPLETE) begin
                done <= 1;
            end else begin
                done <= 0;
            end
        end
    end
    
    // RGB extraction (converting from 5-6-5 format to 8-bit per channel)
    always @(posedge clk) begin
        if (state == EXTRACT) begin
            // Extract R (5 bits to 8 bits)
            r <= {rgb_in[15:11], 3'b000} | {3'b000, rgb_in[15:13]};
            
            // Extract G (6 bits to 8 bits)
            g <= {rgb_in[10:5], 2'b00} | {2'b00, rgb_in[10:7]};
            
            // Extract B (5 bits to 8 bits)
            b <= {rgb_in[4:0], 3'b000} | {3'b000, rgb_in[4:2]};
        end
    end
    
    // RGB to HSV conversion
    always @(posedge clk) begin
        if (state == CALC_HSV) begin
            // Find min and max of RGB
            rgb_min = (r < g) ? ((r < b) ? r : b) : ((g < b) ? g : b);
            rgb_max = (r > g) ? ((r > b) ? r : b) : ((g > b) ? g : b);
            
            // Value is the max RGB value
            v <= rgb_max;
            
            // If value is 0, then h and s are also 0
            if (rgb_max == 0) begin
                calc_h <= 0;  // Store in calc_h instead of h
                s <= 0;
            end else begin
                // Calculate saturation
                delta = rgb_max - rgb_min;
                temp = (255 * delta) / rgb_max;
                s <= temp[7:0];
                
                // If saturation is 0, hue is undefined (set to 0)
                if (delta == 0) begin
                    calc_h <= 0;  // Store in calc_h instead of h
                end else begin
                    // Calculate hue
                    if (rgb_max == r) begin
                        // h = 0 + 43 * (g - b) / delta
                        if (g >= b)
                            temp = (43 * (g - b)) / delta;
                        else
                            temp = 256 + (43 * (g - b)) / delta; // Add 256 for modulo effect
                        calc_h <= temp[7:0];  // Store in calc_h instead of h
                    end else if (rgb_max == g) begin
                        // h = 85 + 43 * (b - r) / delta
                        temp = 85 + (43 * (b - r)) / delta;
                        calc_h <= temp[7:0];  // Store in calc_h instead of h
                    end else begin // rgb_max == b
                        // h = 171 + 43 * (r - g) / delta
                        temp = 171 + (43 * (r - g)) / delta;
                        calc_h <= temp[7:0];  // Store in calc_h instead of h
                    end
                end
            end
        end
    end
    
    // Set new hue value - combined h assignment from both calculations
    always @(posedge clk) begin
        if (state == CALC_HSV) begin
            // Don't modify h here, it's set in SET_HUE state
        end else if (state == SET_HUE) begin
            h <= (hue_out + calc_h) % 255;  // Use the input hue value for shifting
        end
    end
    
    // HSV to RGB conversion
    always @(posedge clk) begin
        if (state == CALC_RGB) begin
            // If saturation is 0, the color is a shade of gray
            if (s == 0) begin
                r_out <= v;
                g_out <= v;
                b_out <= v;
            end else begin
                // Calculate region and remainder
                region = h / 43;
                remainder = (h - (region * 43)) * 6; // Scale remainder to 0-255
                
                // Calculate p, q, t values
                // p = (v * (255 - s)) >> 8
                temp = (v * (255 - s));
                p <= temp >> 8;
                
                // q = (v * (255 - ((s * remainder) >> 8))) >> 8
                temp = (s * remainder) >> 8;
                temp = v * (255 - temp);
                q <= temp >> 8;
                
                // t = (v * (255 - ((s * (255 - remainder)) >> 8))) >> 8
                temp = (s * (255 - remainder)) >> 8;
                temp = v * (255 - temp);
                t <= temp >> 8;
            end
        end else if (state == PACK) begin
            // Determine RGB based on region
            case (region)
                0: begin
                    r_out <= v; g_out <= t; b_out <= p;
                end
                1: begin
                    r_out <= q; g_out <= v; b_out <= p;
                end
                2: begin
                    r_out <= p; g_out <= v; b_out <= t;
                end
                3: begin
                    r_out <= p; g_out <= q; b_out <= v;
                end
                4: begin
                    r_out <= t; g_out <= p; b_out <= v;
                end
                default: begin // region 5
                    r_out <= v; g_out <= p; b_out <= q;
                end
            endcase
        end
    end
    
    // Pack RGB back to 16-bit format (5-6-5)
    always @(posedge clk) begin
        if (state == PACK) begin
            rgb_out <= {r_out[7:3], g_out[7:2], b_out[7:3]};
        end
    end

endmodule