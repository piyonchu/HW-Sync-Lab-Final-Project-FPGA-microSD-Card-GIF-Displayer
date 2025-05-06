# HW Sync Lab Final Project: FPGA microSD Card GIF Displayer

<img alt="Preview" title="Preview" src="preview.gif" width="50%"/> 
<br> <br>

This project demonstrates how to read a GIF stored on a microSD card using a Basys3 FPGA board, scale the resolution and display it via VGA output at a resolution of 640×480. You can switch between GIFs using a button on the board.

---

## How It Works

1. Convert and format the GIF frames into 16-bit color binary using Python.
2. Write the binary data directly to the microSD card using a sector-based write script.
3. Load the appropriate bitstream (e.g., `VGA`) onto the Basys3 FPGA.
4. Watch the GIF display and change frames using the button on the board.

---

## Bitstreams

* **SD**: Checks if the microSD card is functioning correctly. (All LEDs ON = OK)
* **SUM**: Verifies that all sectors containing the image frames are read correctly using checksum.
* **VGA**: The main bitstream used to display the stored GIF on the VGA output.

---

## Pictures

* The GIF consists of 6 frames.
* Each frame is 64×48 pixels, with each pixel stored as a 16-bit value.
* Frames are concatenated and saved into a binary file (`.bin`), totaling `6 × 64 × 48 × 2` bytes.
* A Python script converts each pixel to 16-bit color and writes the entire image data directly to specific sectors on the microSD card, bypassing the filesystem.

---










[![Review Assignment Due Date](https://classroom.github.com/assets/deadline-readme-button-22041afd0340ce965d47ae6ef1cefeee28c7c493a6346c4f15d667ab976d596c.svg)](https://classroom.github.com/a/tmSIHg3v)
> [!IMPORTANT]
> Please read full version of final project instructions in MyCourseVille.

# **Final Project: FPGA Image Display from MicroSD on Basys 3**

## **Project Overview**

In this final project, students will implement an FPGA-based image display system that reads image data from a microSD card and renders it on a VGA display using a Basys 3 board. The primary objective is to successfully interface an FPGA with a microSD card, extract stored images, and display them on the VGA output.

## **Project Requirements**

1. **MicroSD Card Data Retrieval**: The FPGA must be capable of reading data from a microSD card. Data may be stored in a raw format or within a file system (such as FAT32).  
2. **VGA Display Implementation**: The FPGA should be able to generate VGA signals and display content on a monitor.  
3. **Image Rendering**: Successfully retrieve and display an image stored in the microSD card on the VGA screen with resolution of 320 \* 240 pixel.  
4. **Image Switching**: Implement a method to switch between multiple stored images.  
5. **Extra Features**: Add an additional functionality to enhance the project (e.g., image blending, animations, file system support, etc.).

## **Deliverables**

* **Verilog Code**: Well-documented HDL implementation.  
* **Project Report**: Explanation of design decisions, implementation details, and challenges faced.  
* **Demo**: A live demonstration or recorded video showcasing project functionality.
