a = []

def sum_16bit_chunks(filename):
    total = 0
    with open(filename, 'rb') as f:
        while True:
            chunk = f.read(2)  # Read 2 bytes
            if len(chunk) < 2:
                break
            value = int.from_bytes(chunk, byteorder='big')  # or 'big'
            #print(hex(value))
            a.append(hex(value))
            total += value
    return total

# Usage
filename = '0.bin'
result = sum_16bit_chunks(filename) % 65521 
print(f"Sum of 16-bit chunks: {result} {bin(result)}")

result1 = sum_16bit_chunks('1.bin') % 65521 
print(f"Sum of 16-bit chunks: {result1} {bin(result1)}")

result2 = sum_16bit_chunks('2.bin') % 65521 
print(f"Sum of 16-bit chunks: {result2} {bin(result2)}")

result3 = sum_16bit_chunks('3.bin') % 65521 
print(f"Sum of 16-bit chunks: {result3} {bin(result3)}")

result4 = sum_16bit_chunks('4.bin') % 65521 
print(f"Sum of 16-bit chunks: {result4} {bin(result4)}")