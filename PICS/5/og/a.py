import os
import hashlib

def get_file_hash(filepath):
    hasher = hashlib.md5()
    with open(filepath, 'rb') as f:
        buf = f.read()
        hasher.update(buf)
    return hasher.hexdigest()

def delete_duplicate_pngs(folder_path):
    hashes = {}
    for filename in os.listdir(folder_path):
        if filename.lower().endswith('.png'):
            file_path = os.path.join(folder_path, filename)
            file_hash = get_file_hash(file_path)

            if file_hash in hashes:
                print(f"Deleting duplicate: {file_path}")
                os.remove(file_path)
            else:
                hashes[file_hash] = file_path

# Example usage
delete_duplicate_pngs('C:/Users/piyon/Desktop/diglab/finalwrite/src/pic/5/og')
