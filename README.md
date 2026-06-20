# Persepsi Robot: 3D Photogrammetry WebODM

This system facilitates the automated capture of image datasets using a camera synchronized with robot hardware (via ESP32), and automatically processes those images into 3D models using NodeODM.

## System Architecture (Frontend & Backend Decoupling)
This system is designed to be deployed across two separate devices:
1. **Device 1 (Stationary / Main PC)**: Runs `NodeODM` and the `Backend` container. It is responsible for reading physical signals from the microcontroller (ESP32) and handling the heavy 3D rendering computations.
2. **Device 2 (Mobile / Remote Laptop)**: Runs the `Frontend` UI. This device acts as the control panel and the **main camera** (the camera is accessed via the web browser on this device).

### How Does the Synchronization Work?
The photogrammetry automation in this system is designed to be independent of the number of robot waypoints. Instead, it reacts purely to hardware electrical signals.

- **Standby**: When the "Start Robot" button is pressed on the Frontend, the device's camera turns on. The Frontend sends an instruction to the Backend to start listening to the ESP32 inputs (Pin 33 for Capture & Pin 32 for Stop). While on standby, the Frontend continuously polls the Backend for state updates every 150 milliseconds.
- **Capture**: Every time the robot reaches a *waypoint*, the robotic arm sends a HIGH voltage signal to Pin 33 of the ESP32. The Backend reads this signal and changes its internal state to `capture` for frame N. The polling Frontend detects this instruction and automatically captures a frame from the live video feed into its RAM. A debounce mechanism ensures that the camera does not take duplicate photos at the same waypoint.
- **Finish & Upload**: Once the survey process is complete, the robotic arm sends a signal to Pin 32. The Backend changes the state to `stop`. The Frontend responds by turning off the camera, bundling all the captured frames held in memory, and automatically uploading them to the Backend server as a `multipart/form-data` payload. Upon successful upload, the Backend immediately triggers the NodeODM processing pipeline.

---

## Deployment: How to Download Images & Run the App

### 1. Run NodeODM (Device 1)
Run NodeODM on your Main PC:
```bash
docker run -it -d -p 3000:3000 --name nodeodm opendronemap/nodeodm --network host
```

### 2. Run Backend (Device 1)
The backend requires local folders to store the photo dataset (`datasets/`) and the 3D output (`output/`). Create them first.
```bash
# Create local directories
mkdir -p datasets output

# Download/Pull the latest backend image
docker pull kamna213/persepsi_backend:latest

# Remove old container if it exists
docker rm -f pr-backend

# Run the Backend container
docker run -d \
  --name pr-backend \
  --network host \
  -e PYTHONUNBUFFERED=1 \
  -v $(pwd)/datasets:/app/datasets \
  -v $(pwd)/output:/app/output \
  --restart unless-stopped \
  kamna213/persepsi_backend:latest
```

### 3. Run Frontend (Device 2)
Run this command on the device you will use to take pictures and access the Web UI.
```bash
# Download/Pull the latest frontend image
docker pull kamna213/persepsi_frontend:latest

# Remove old container if it exists
docker rm -f pr-frontend

# Run the Frontend container
docker run -d \
  --name pr-frontend \
  -p 80:80 \
  --restart unless-stopped \
  kamna213/persepsi_frontend:latest
```

Once running, access the Frontend via your browser at `http://<IP_FRONTEND>:80`. Select your connected camera from the Dropdown UI, input the Backend URL, and start the survey process!

---

## ODM Options
To configure advanced NodeODM computation options, you can edit the `run_odm.sh` file in the backend folder (specifically the `ODM_OPTIONS` variable).
| Option Name | Alternative / Supported Values | Description |
| :--- | :--- | :--- |
| **`feature-quality`** | `"ultra"`, `"highest"`, `"high"`, `"medium"`, `"low"`, `"lowest"` | Image feature detection quality level. |
| **`min-num-features`** | Positive integer (Default: `10000`, e.g., `4000`, `8000`, `16000`) | Minimum number of keypoints to extract per image. |
| **`matcher-type`** | `"flann"`, `"bruteforce"`, `"bow"` | The algorithm used for matching features between images. |
| **`mesh-octree-depth`** | Integer from `1` to `14` (Default: `9`) | Density and detail level of the 3D mesh structure. |
| **`mesh-size`** | Positive integer (e.g., `100000`, `200000`, `400000`) | Maximum vertex/polygon count limit for the mesh. |
| **`use-3dmesh`** | `true`, `false` | Enables or disables the generation of a 3D mesh model. |
| **`pc-quality`** | `"ultra"`, `"high"`, `"medium"`, `"low"`, `"lowest"` | Point cloud density and generation quality. |
| **`ignore-gsd`** | `true`, `false` | Bypasses the default GSD limit to process photos at full resolution. |
| **`bg-removal`** | `true`, `false` | Automatically detects and removes sky/horizon backgrounds. |