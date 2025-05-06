module top(
    input wire          clk100mhz,           // Clock input
    input wire          reset,               // Reset button
    input wire          btn,                 // Button to change sectors
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
    
    // Debounced button signal
    wire       btn_debounced;
    reg        btn_prev = 0;
    reg        btn_pressed = 0;
    
    // Buffer storage instead of block RAM
    // 18432 16-bit words = 36864 bytes = 72 sectors (each sector is 512 bytes)
    reg [15:0] buffer [0:18431];  // 16-bit wide, 18432 entries deep
    reg [14:0] buffer_addr_write = 0;   // Address for writing to buffer
    wire [14:0] buffer_addr_read;       // Address for reading from buffer (for VGA)
    
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
    
    // Clock wizard instance for 25MHz clock
    clk_wiz_0 u_clk_wiz_0 (
        .reset       (reset),
        .clk_in1     (clk100mhz),       // input 100MHz
        .locked      (locked),
        .clk_out1    (clk)              // output 25MHz
    );
    
    // Button debouncer
    debounce btn_debouncer (
        .clk         (clk),
        .reset       (rst),
        .btn_in      (btn),
        .btn_out     (btn_debounced)
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
    wire [15:0] pixel_data;     // Current pixel color data
    reg [12:0] scaled_x, scaled_y;
    reg [12:0] buffer_pixel_addr;
    reg [14:0] frame_base_addr;
    reg [15:0] tled;
    // Scale coordinates from 640x480 to 64x48
    always @* begin
        scaled_x = pixel_x / 10;  // 640/64 = 10
        scaled_y = pixel_y / 10;  // 480/48 = 10
        
        // Calculate base address for current frame (each frame is 64x48 = 3072 pixels)
        frame_base_addr = current_frame * 3072;
        
        // Calculate pixel address within the buffer
        buffer_pixel_addr = (scaled_y * 64) + scaled_x;
        
        // Debug pixel capture (separate from LED output)
//        if (pixel_x == 639 && pixel_y == 479) begin 
//            led <= buffer[frame_base_addr + buffer_pixel_addr]; 
//        end
    end
    

   
    // Assign buffer read address for VGA display
    assign buffer_addr_read = (scaled_x < 64 && scaled_y < 48) ? 
                           frame_base_addr + buffer_pixel_addr : 
                           frame_base_addr; // Default to first pixel if out of bounds
    
    // Get data from buffer
    //assign led = tled;
    assign pixel_data = (video_on && main_state == DONE) ? buffer[buffer_addr_read] : 16'h0000;
    
    // Extract RGB components (assuming 16-bit RGB565 format)
    assign vga_r = video_on ? pixel_data[15:12] : 4'h0; // Red: bits 15-11, take top 4
    assign vga_g = video_on ? pixel_data[10:7] : 4'h0;  // Green: bits 10-5, take middle 4
    assign vga_b = video_on ? pixel_data[4:1] : 4'h0;   // Blue: bits 4-0, take top 4
    
//    always @(posedge clk) begin
//        if (pixel_x == 639 && pixel_y == 479 && main_state == DONE) begin 
//            // Calculate the buffer address for the bottom-right pixel directly
//            // Avoid using pixel_data which depends on video_on
//            scaled_x = 63;  // Last column (0-indexed)
//            scaled_y = 47;  // Last row (0-indexed)
//            buffer_pixel_addr = (scaled_y * 64) + scaled_x;
//            led <= buffer[frame_base_addr + buffer_pixel_addr]; 
//        end
//    end
    
    // Frame rate control and animation
    always @(posedge clk) begin
        if (rst) begin
            current_frame <= 0;
            frame_counter <= 0;
        end else if (main_state == DONE) begin
            // Only animate when in DONE state
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
            //led <= current_frame;
        end
   end
    
   ila_1 ila_1 (
        .clk(clk),
        .probe0(pixel_x),
        .probe1(pixel_y),
        .probe2(led),
        .probe3(current_frame),
        .probe4(pixel_data)
    );
    
    
    // Button edge detection
    always @(posedge clk) begin
        if (rst) begin
            btn_prev <= 0;
            btn_pressed <= 0;
            change_sector_group <= 0;
        end else begin
            btn_prev <= btn_debounced;
            btn_pressed <= ~btn_prev & btn_debounced; // Rising edge detection
            
            // Set the flag when button is pressed and we're in DONE state
            if (btn_pressed && main_state == DONE) begin
                change_sector_group <= 1;
            end else begin
                change_sector_group <= 0;
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
                            
                            // Update debug LEDs with the last two bytes
//                            if (bytes_read[0])  // Every other byte
//                                led[15:8] <= sd_dout;
//                            else
//                                led[7:0] <= sd_dout;
                                
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
                        //led <= checksum[15:0];  // Show the 16 least significant bits
                        main_state <= DONE;     // Move to DONE state
                    end
                    
                    DONE: begin
                        // Wait for button press to change sector group
                        done <= 1;  // Signal all sectors are read
                        //led <= current_frame;
                        led <= buffer[frame_base_addr + ((47 * 64) + 63)];
                        // Keep displaying the checksum - LEDs are not updated here anymore
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
        .status         (status),
        .fuck           ()                    // Unused debug output
    );
    
endmodule

// Button debouncer module
module debounce (
    input      clk,
    input      reset,
    input      btn_in,
    output reg btn_out
);
    parameter DEBOUNCE_PERIOD = 250000;  // 10ms at 25MHz
    
    reg [19:0] counter = 0;
    reg        btn_state = 0;
    
    always @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            btn_state <= 0;
            btn_out <= 0;
        end else begin
            if (btn_in != btn_state) begin
                // Button state changed, start counting
                counter <= 0;
                btn_state <= btn_in;
            end else if (counter < DEBOUNCE_PERIOD) begin
                // Still counting
                counter <= counter + 1;
            end else begin
                // Debounce period elapsed, update output
                btn_out <= btn_state;
            end
        end
    end
endmodule