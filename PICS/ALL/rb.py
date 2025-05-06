with open("0.bin", "rb") as f:
    data = f.read()

data_list = list(data)  # Now it's a list of ints

#data_list = [bytes([b]) for b in data]  # Each item is a single-byte bytes object

print(hex(data_list[512]), hex(data_list[513]))