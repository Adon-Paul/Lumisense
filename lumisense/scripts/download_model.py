#!/usr/bin/env python3
"""
Download and export YOLOv8n to TFLite format for LumiSense.

Requirements:
    pip install ultralytics

Usage:
    python scripts/download_model.py

This will:
1. Download the YOLOv8n pre-trained model (~6 MB)
2. Export it to TFLite format (float32)
3. Copy the exported model to assets/models/yolov8n.tflite
"""

import shutil
import sys
from pathlib import Path

def main():
    try:
        from ultralytics import YOLO
    except ImportError:
        print("ERROR: ultralytics package not found.")
        print("Install it with: pip install ultralytics")
        sys.exit(1)

    print("Loading YOLOv8n model...")
    model = YOLO("yolov8n.pt")

    print("Exporting to TFLite format...")
    export_path = model.export(format="tflite")

    # The export creates a file like yolov8n_float32.tflite
    export_file = Path(export_path)
    if not export_file.exists():
        # Try common export paths
        for candidate in [
            Path("yolov8n_float32.tflite"),
            Path("yolov8n_saved_model") / "yolov8n_float32.tflite",
        ]:
            if candidate.exists():
                export_file = candidate
                break

    if not export_file.exists():
        print(f"ERROR: Could not find exported TFLite model at {export_path}")
        sys.exit(1)

    # Copy to assets directory
    script_dir = Path(__file__).parent
    dest = script_dir.parent / "assets" / "models" / "yolov8n.tflite"
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(str(export_file), str(dest))

    size_mb = dest.stat().st_size / (1024 * 1024)
    print(f"Model exported successfully!")
    print(f"  Location: {dest}")
    print(f"  Size: {size_mb:.1f} MB")
    print()
    print("You can now build the APK with: flutter build apk --release")


if __name__ == "__main__":
    main()
