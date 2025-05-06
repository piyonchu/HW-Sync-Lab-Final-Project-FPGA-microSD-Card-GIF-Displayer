from PIL import Image

def rgb888_to_rgb565(r, g, b):
    """Convert 24-bit RGB to 16-bit RGB565."""
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)

def png_to_rgb565_bytes(input_path, output_path):
    img = Image.open(input_path).convert('RGB')  # Ensure RGB mode
    width, height = img.size
    pixels = img.load()

    with open(output_path, 'wb') as f:
        for y in range(height):
            for x in range(width):
                r, g, b = pixels[x, y]
                rgb565 = rgb888_to_rgb565(r, g, b)
                f.write(rgb565.to_bytes(2, byteorder='big'))  # or 'little' if needed

# Example usage
png_to_rgb565_bytes('1.png', '1.bin')
