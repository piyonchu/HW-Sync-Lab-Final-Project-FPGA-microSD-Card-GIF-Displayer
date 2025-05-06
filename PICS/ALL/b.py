def read_sectors(drive_number, start_sector, end_sector, sector_size=512):
    num_sectors = end_sector - start_sector + 1
    drive_path = f"\\\\.\\PhysicalDrive{drive_number}"
    
    with open(drive_path, 'rb') as disk:
        disk.seek(start_sector * sector_size)
        data = disk.read(num_sectors * sector_size)
    
    print(f"Read {len(data)} bytes from sectors {start_sector} to {end_sector} on PhysicalDrive{drive_number}")
    return data


drive_number = 3       # Your SD card drive number
start_sector = 0        # Starting sector
end_sector = 71         # Ending sector (inclusive)

raw_data = read_sectors(drive_number, start_sector, end_sector)

print(raw_data)