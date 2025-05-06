import os

def pad_data(data, sector_size=512):
    padding = (sector_size - len(data) % sector_size) % sector_size
    return data + b'\x00' * padding

def write_file_to_sector(file_path, drive_number, start_sector, sector_size=512):
    # Read and pad file
    with open(file_path, 'rb') as f:
        data = f.read()
    padded_data = pad_data(data, sector_size)
    print(" what ", data, " end ")

    total_sectors = len(padded_data) // sector_size
    end_sector = start_sector + total_sectors - 1

    drive_path = f"\\\\.\\PhysicalDrive{drive_number}"
    with open(drive_path, 'r+b') as disk:
        disk.seek(start_sector * sector_size)
        disk.write(padded_data)
    
    print(f"Wrote {len(padded_data)} bytes "
          f"({total_sectors} sectors) from sector {start_sector} to {end_sector} "
          f"on PhysicalDrive{drive_number}")

# ==== Example Usage ====
file_path = '0.bin'
drive_number = 3
start_sector = 0

write_file_to_sector(file_path, drive_number, start_sector)
