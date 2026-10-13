# /// script
# requires-python = "==3.12.*"
# dependencies = ["rapidocr_onnxruntime>=1.4"]
# ///
"""OCR an image with RapidOCR (PaddleOCR models on ONNX). Prints JSON lines to stdout:
[{"text": str, "conf": float, "box": [x, y, w, h]}] in image pixels."""
import json
import sys

from rapidocr_onnxruntime import RapidOCR

result, _ = RapidOCR()(sys.argv[1])
out = []
for quad, text, conf in result or []:
    xs = [p[0] for p in quad]
    ys = [p[1] for p in quad]
    out.append({"text": text, "conf": float(conf), "box": [min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys)]})
json.dump(out, sys.stdout)
