import requests
import time
import os
import json
import signal
import sys

global id_frame
id_frame = 0

ESP32_IP = os.getenv("ESP32_IP", "http://192.168.200.219")
STATE_FILE = "robot_state.json"

def update_state(action, frame_id=0):
    try:
        with open(STATE_FILE, "w") as f:
            json.dump({
                "action": action, 
                "frame_id": frame_id, 
                "timestamp": time.time()
            }, f)
    except Exception as e:
        print(f"[ERROR] Gagal menulis state: {e}")

def set_relay_active(relay_id, state):
    url = f"{ESP32_IP}/relay/{relay_id}"
    try:
        requests.post(url, data={'state': state}, timeout=2)
        return True
    except:
        return False

def get_input_states():
    url = f"{ESP32_IP}/input"
    try:
        response = requests.get(url, timeout=2)
        if response.status_code == 200:
            return response.json()['inputs']
    except:
        return None

def main():
    print("Program dimulai (Mode Sinkronisasi Frontend)...")
    global id_frame

    def handle_sigterm(signum, frame):
        print("\n[INFO] Menerima sinyal stop (SIGTERM). Keluar...")
        update_state("stop")
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_sigterm)

    # Inisialisasi state
    update_state("idle", id_frame)

    if set_relay_active(0, "on"):
        print("Relay aktif")

    jatah_foto = 1

    try:
        while True:
            inputs = get_input_states()

            if inputs:
                pin_33 = next((item for item in inputs if item["pin"] == 33), None)
                pin_32 = next((item for item in inputs if item["pin"] == 32), None)

                # =========================
                # TRIGGER FOTO
                # =========================
                if pin_33:
                    state_33 = pin_33["state"]

                    if state_33 == 1:
                        if jatah_foto > 0:
                            print(f"[TRIGGER] Minta Frontend ambil foto ke-{id_frame}")
                            update_state("capture", id_frame)
                            id_frame += 1
                            jatah_foto = 0
                    else:
                        if jatah_foto == 0:
                            jatah_foto = 1
                            print("[READY]")
                            update_state("idle", id_frame)

                # =========================
                # STOP
                # =========================
                if pin_32:
                    state_32 = pin_32["state"]

                    if state_32 == 1:
                        print("[INFO] Selesai")
                        set_relay_active(0, "off")
                        update_state("stop", id_frame)
                        break

            time.sleep(0.1)  # Interval polling ESP32

    except KeyboardInterrupt:
        print("\nProgram dihentikan")
        update_state("stop")

if __name__ == "__main__":
    main()