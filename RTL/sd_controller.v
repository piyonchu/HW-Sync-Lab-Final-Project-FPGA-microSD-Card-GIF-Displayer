/* SD Card controller module. Allows reading from and writing to a microSD card
through SPI mode. Fixed version according to lecture specifications. */

`timescale 1ns / 1ps

module sd_controller(
    output reg cs, // Connect to SD_DAT[3].
    output mosi, // Connect to SD_CMD.
    input miso, // Connect to SD_DAT[0].
    output sclk, // Connect to SD_SCK.
                // For SPI mode, SD_DAT[2] and SD_DAT[1] should be held HIGH. 
                // SD_RESET should be held LOW.

    input rd,   // Read-enable. When [ready] is HIGH, asseting [rd] will 
                // begin a 512-byte READ operation at [address]. 
                // [byte_available] will transition HIGH as a new byte has been
                // read from the SD card. The byte is presented on [dout].
    output reg [7:0] dout, // Data output for READ operation.
    output reg byte_available, // A new byte has been presented on [dout].

    input wr,   // Write-enable. When [ready] is HIGH, asserting [wr] will
                // begin a 512-byte WRITE operation at [address].
                // [ready_for_next_byte] will transition HIGH to request that
                // the next byte to be written should be presentaed on [din].
    input [7:0] din, // Data input for WRITE operation.
    output reg ready_for_next_byte, // A new byte should be presented on [din].

    input reset, // Resets controller on assertion.
    output ready, // HIGH if the SD card is ready for a read or write operation.
    input [31:0] address,   // Memory address for read/write operation.
    input clk,  // 25 MHz clock.
    output [4:0] status // For debug purposes: Current state of controller.
    
);

    parameter RST = 0;
    parameter INIT = 1;
    parameter CMD0 = 2;
    parameter CMD8 = 3;  // Added CMD8 state according to lecture flowchart
    parameter CMD55 = 4;
    parameter CMD41 = 5;
    parameter POLL_CMD = 6;
    
    parameter IDLE = 7;
    parameter READ_BLOCK = 8;
    parameter READ_BLOCK_WAIT = 9;
    parameter READ_BLOCK_DATA = 10;
    parameter READ_BLOCK_CRC = 11;
    parameter SEND_CMD = 12;
    parameter RECEIVE_BYTE_WAIT = 13;
    parameter RECEIVE_BYTE = 14;
    parameter WRITE_BLOCK_CMD = 15;
    parameter WRITE_BLOCK_INIT = 16;
    parameter WRITE_BLOCK_DATA = 17;
    parameter WRITE_BLOCK_BYTE = 18;
    parameter WRITE_BLOCK_WAIT = 19;
    parameter CMD58 = 20;  // Added CMD58 state for OCR register check
    
    parameter WRITE_DATA_SIZE = 515;
    
    reg [4:0] state = RST;
    assign status = state;
    reg [4:0] return_state;
    reg sclk_sig = 0;
    reg [55:0] cmd_out;
    reg [7:0] recv_data;
    reg cmd_mode = 1;
    reg [7:0] data_sig = 8'hFF;
    
    reg [9:0] byte_counter;
    reg [9:0] bit_counter;
    
    // Modified to ensure at least 74 clock cycles for proper SD card initialization
    reg [26:0] boot_counter = 27'd100_000_000;
    always @(posedge clk) begin
        if(reset == 1) begin
            state <= RST;
            sclk_sig <= 0;
            boot_counter <= 27'd100_000_000;
        end
        else begin
            case(state)
                RST: begin
                    if(boot_counter == 0) begin
                        sclk_sig <= 0;
                        cmd_out <= {56{1'b1}};
                        byte_counter <= 0;
                        byte_available <= 0;
                        ready_for_next_byte <= 0;
                        cmd_mode <= 1;
                        // Changed to 74 cycles minimum for proper initialization
                        bit_counter <= 160;  
                        cs <= 1;  // Start with CS high
                        state <= INIT;
                        
                    end
                    else begin
                        boot_counter <= boot_counter - 1;
                    end
                    
                end
                INIT: begin
                    if(bit_counter == 0) begin
                        cs <= 0;  // Set CS low to begin communication
                        state <= CMD0;
                    end
                    else begin
                        bit_counter <= bit_counter - 1;
                        sclk_sig <= ~sclk_sig;
                    end
                    
                end
                CMD0: begin
                    // Format according to lecture: 01 000000 00000000 00000000 00000000 00000000 1001010 1
                    cmd_out <= 56'hFF_40_00_00_00_00_95;
                    bit_counter <= 55;
                    return_state <= CMD8;  // Go to CMD8 next as per initialization flowchart
                    state <= SEND_CMD;
                    
                end
                CMD8: begin
                    // Format according to lecture: 01 001000 00000000 00000000 00000001 10101010 0000111 1
                    cmd_out <= 56'hFF_48_00_00_01_AA_87;
                    bit_counter <= 55;
                    return_state <= CMD58;  // Check OCR register next
                    state <= SEND_CMD;
                   
                end
                CMD58: begin
                    // Format according to lecture: 01 111010 00000000 00000000 00000000 00000000 0111010 1
                    cmd_out <= 56'hFF_7A_00_00_00_00_75;
                    bit_counter <= 55;
                    return_state <= CMD55;  // Continue with ACMD41 sequence
                    state <= SEND_CMD;
                    
                end
                CMD55: begin
                    // Fixed CRC as per lecture requirements
                    cmd_out <= 56'hFF_77_00_00_00_00_65;
                    bit_counter <= 55;
                    return_state <= CMD41;
                    state <= SEND_CMD;
                    
                end
                CMD41: begin
                    // Fixed command format and CRC
                    cmd_out <= 56'hFF_69_40_00_00_00_77;
                    bit_counter <= 55;
                    return_state <= POLL_CMD;
                    state <= SEND_CMD;
                   
                end
                POLL_CMD: begin
                    if(recv_data[0] == 0) begin
                        state <= IDLE;
                    end
                    else begin
                        state <= CMD55;  // Retry ACMD41 sequence
                    end
                    
                end
                IDLE: begin
                    if(rd == 1) begin
                        state <= READ_BLOCK;
                    end
                    else if(wr == 1) begin
                        state <= WRITE_BLOCK_CMD;
                    end
                    else begin
                        state <= IDLE;
                    end
                    
                end
                READ_BLOCK: begin
                    cmd_out <= {16'hFF_51, address, 8'hFF};
                    bit_counter <= 55;
                    return_state <= READ_BLOCK_WAIT;
                    state <= SEND_CMD;
                    
                end
                READ_BLOCK_WAIT: begin
                    if(sclk_sig == 1 && miso == 0) begin
                        byte_counter <= 511;
                        bit_counter <= 7;
                        return_state <= READ_BLOCK_DATA;
                        state <= RECEIVE_BYTE;
                    end
                    sclk_sig <= ~sclk_sig;
                    
                end
                READ_BLOCK_DATA: begin
                    dout <= recv_data;
                    byte_available <= 1;
                    if (byte_counter == 0) begin
                        bit_counter <= 7;
                        return_state <= READ_BLOCK_CRC;
                        state <= RECEIVE_BYTE;
                    end
                    else begin
                        byte_counter <= byte_counter - 1;
                        return_state <= READ_BLOCK_DATA;
                        bit_counter <= 7;
                        state <= RECEIVE_BYTE;
                    end
                   
                end
                READ_BLOCK_CRC: begin
                    bit_counter <= 7;
                    return_state <= IDLE;
                    state <= RECEIVE_BYTE;
                    
                end
                SEND_CMD: begin
                    if (sclk_sig == 1) begin
                        if (bit_counter == 0) begin
                            state <= RECEIVE_BYTE_WAIT;
                        end
                        else begin
                            bit_counter <= bit_counter - 1;
                            cmd_out <= {cmd_out[54:0], 1'b1};
                        end
                    end
                    sclk_sig <= ~sclk_sig;
                    
                end
                RECEIVE_BYTE_WAIT: begin
                    if (sclk_sig == 1) begin
                        if (miso == 0) begin
                            recv_data <= 0;
                            bit_counter <= 6;
                            state <= RECEIVE_BYTE;
                        end
                    end
                    sclk_sig <= ~sclk_sig;
                    
                end
                RECEIVE_BYTE: begin
                    byte_available <= 0;
                    if (sclk_sig == 1) begin
                        recv_data <= {recv_data[6:0], miso};
                        if (bit_counter == 0) begin
                            state <= return_state;
                        end
                        else begin
                            bit_counter <= bit_counter - 1;
                        end
                    end
                    sclk_sig <= ~sclk_sig;
                   
                end
                WRITE_BLOCK_CMD: begin
                    cmd_out <= {16'hFF_58, address, 8'hFF};
                    bit_counter <= 55;
                    return_state <= WRITE_BLOCK_INIT;
                    state <= SEND_CMD;
                    ready_for_next_byte <= 1;
                end
                WRITE_BLOCK_INIT: begin
                    cmd_mode <= 0;
                    byte_counter <= WRITE_DATA_SIZE; 
                    state <= WRITE_BLOCK_DATA;
                    ready_for_next_byte <= 0;
                end
                WRITE_BLOCK_DATA: begin
                    if (byte_counter == 0) begin
                        state <= RECEIVE_BYTE_WAIT;
                        return_state <= WRITE_BLOCK_WAIT;
                    end
                    else begin
                        if ((byte_counter == 2) || (byte_counter == 1)) begin
                            data_sig <= 8'hFF;  // CRC bytes (dummy values)
                        end
                        else if (byte_counter == WRITE_DATA_SIZE) begin
                            data_sig <= 8'hFE;  // Data start token
                        end
                        else begin
                            data_sig <= din;
                            ready_for_next_byte <= 1;
                        end
                        bit_counter <= 7;
                        state <= WRITE_BLOCK_BYTE;
                        byte_counter <= byte_counter - 1;
                    end
                end
                WRITE_BLOCK_BYTE: begin
                    if (sclk_sig == 1) begin
                        if (bit_counter == 0) begin
                            state <= WRITE_BLOCK_DATA;
                            ready_for_next_byte <= 0;
                        end
                        else begin
                            data_sig <= {data_sig[6:0], 1'b1};
                            bit_counter <= bit_counter - 1;
                        end
                    end
                    sclk_sig <= ~sclk_sig;
                end
                WRITE_BLOCK_WAIT: begin
                    if (sclk_sig == 1) begin
                        if (miso == 1) begin
                            state <= IDLE;
                            cmd_mode <= 1;
                        end
                    end
                    sclk_sig <= ~sclk_sig;
                end
            endcase
        end
    end
    
    ila_0 ila_0 (
        .clk(clk),
        .probe0(recv_data)
    
    );

    assign sclk = sclk_sig;
    assign mosi = cmd_mode ? cmd_out[55] : data_sig[7];
    assign ready = (state == IDLE);
    
endmodule
