from pyodm import Node
import os
from pathlib import Path


client = Node("localhost", 3000)


dataset_dir = Path(__file__).resolve().parent / "sfm_dataset"


valid_extensions = {".jpg", ".jpeg", ".png", ".tif", ".tiff"}
images = [
    str(file) for file in dataset_dir.iterdir()
    if file.is_file() and file.suffix.lower() in valid_extensions
]

if not images:
    raise FileNotFoundError(f"No images found in {dataset_dir}. Please check the path.")

print(f"Found {len(images)} images. Sending task to node...")

#Create and execute the task
task = client.create_task(
    images, 
    {
        'dsm': True, 
        'orthophoto-resolution': 2.0,
        'feature-quality': 'medium'
    }
)

#Wait for task completion
print("Processing in progress. Waiting for completion...")
task.wait_for_completion()

#Download the generated assets
output_dir = Path(__file__).resolve().parent / "output_assets"
output_dir.mkdir(exist_ok=True)

print(f"Downloading assets to {output_dir}...")
task.download_assets(str(output_dir))

print("Processing complete!")