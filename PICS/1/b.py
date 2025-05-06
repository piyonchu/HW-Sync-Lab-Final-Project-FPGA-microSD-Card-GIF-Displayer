from PIL import Image

def rgb888_to_rgb565(r, g, b):
    """Convert 24-bit RGB to 16-bit RGB565."""
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)

def print_png_pixels_as_bits(input_path):
    img = Image.open(input_path).convert('RGB')  # Ensure RGB mode
    width, height = img.size
    pixels = img.load()

    for y in range(height):
        for x in range(width):
            r, g, b = pixels[x, y]
            rgb565 = rgb888_to_rgb565(r, g, b)
            print(f"{x:03},{y:03} -> RGB565: {format(rgb565, '02x')}")  # binary 16-bit output

# Example usage
print_png_pixels_as_bits('1.png')
