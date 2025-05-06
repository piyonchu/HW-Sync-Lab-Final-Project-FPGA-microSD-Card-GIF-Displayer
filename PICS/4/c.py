from PIL import Image
import os

def rgb888_to_rgb565(r, g, b):
    """Convert RGB888 to RGB565 format."""
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)

def convert_images_to_bin(output_file, image_count):
    with open(output_file, 'wb') as out:
        for i in range(1, image_count + 1):
            filename = f"{i}.png"
            if not os.path.exists(filename):
                print(f"Skipping {filename}: not found")
                continue
            img = Image.open(filename).convert('RGB')
            pixels = img.load()
            width, height = img.size

            for y in range(height):
                for x in range(width):
                    r, g, b = pixels[x, y]
                    rgb565 = rgb888_to_rgb565(r, g, b)
                    out.write(rgb565.to_bytes(2, byteorder='big'))

# Example: convert 1.png to 10.png
convert_images_to_bin("all_images.bin", image_count=6)
