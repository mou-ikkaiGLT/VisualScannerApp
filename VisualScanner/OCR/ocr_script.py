#!/usr/bin/env python3
"""
PaddleOCR wrapper script for VisualScanner.
Takes an image path as argument, runs OCR, outputs JSON to stdout.

Usage: python3 ocr_script.py /path/to/image.png

Output: {"success": true, "text": "full text", "lines": ["line1", "line2"]}
"""

import json
import sys
import os

def sort_by_layout(texts, dt_polys):
    """Sort detected text regions by reading order.

    For vertical text (tall narrow columns), sort right-to-left then top-to-bottom.
    For horizontal text, sort top-to-bottom then left-to-right.
    """
    if not texts:
        return texts

    # Build list of (text, x_center, y_center, width, height)
    entries = []
    for i, poly in enumerate(dt_polys):
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        x_min, x_max = min(xs), max(xs)
        y_min, y_max = min(ys), max(ys)
        w = x_max - x_min
        h = y_max - y_min
        cx = (x_min + x_max) / 2
        cy = (y_min + y_max) / 2
        entries.append((texts[i], cx, cy, w, h))

    # Detect if majority of text regions are vertical (height > width * 1.5)
    vertical_count = sum(1 for _, _, _, w, h in entries if h > w * 1.5)
    is_vertical = vertical_count > len(entries) / 2

    if is_vertical:
        # Vertical text: sort by x descending (right-to-left), then y ascending (top-to-bottom)
        entries.sort(key=lambda e: (-e[1], e[2]))
    else:
        # Horizontal text: sort by y ascending (top-to-bottom), then x ascending (left-to-right)
        entries.sort(key=lambda e: (e[2], e[1]))

    return [e[0] for e in entries]


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"success": False, "error": "No image path provided", "text": "", "lines": []}))
        sys.exit(1)

    image_path = sys.argv[1]
    if not os.path.exists(image_path):
        print(json.dumps({"success": False, "error": f"Image not found: {image_path}", "text": "", "lines": []}))
        sys.exit(1)

    try:
        # Suppress PaddlePaddle and PaddleOCR logging noise
        os.environ.setdefault("GLOG_minloglevel", "2")
        os.environ.setdefault("PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK", "True")
        import logging
        logging.disable(logging.DEBUG)
        import warnings
        warnings.filterwarnings("ignore", category=DeprecationWarning)

        from paddleocr import PaddleOCR

        ocr = PaddleOCR(
            text_recognition_model_name='PP-OCRv5_server_rec',
            use_doc_orientation_classify=False,
            use_doc_unwarping=False,
            use_textline_orientation=False,
            lang='en',
        )

        result = ocr.predict(image_path)

        lines = []
        for res in result:
            if isinstance(res, dict) and 'rec_texts' in res:
                texts = res['rec_texts']
                dt_polys = res.get('dt_polys', [])
                if texts and dt_polys and len(texts) == len(dt_polys):
                    lines.extend(sort_by_layout(texts, dt_polys))
                else:
                    lines.extend(texts)
            elif isinstance(res, list):
                for line in res:
                    if line and len(line) >= 2:
                        text_info = line[1]
                        if text_info and len(text_info) >= 1:
                            lines.append(str(text_info[0]))

        full_text = "\n".join(lines)
        print(json.dumps({"success": True, "text": full_text, "lines": lines}))

    except ImportError as e:
        print(json.dumps({
            "success": False,
            "error": f"PaddleOCR not installed: {e}. Run: pip3 install paddleocr paddlepaddle",
            "text": "",
            "lines": []
        }))
        sys.exit(1)
    except Exception as e:
        print(json.dumps({
            "success": False,
            "error": str(e),
            "text": "",
            "lines": []
        }))
        sys.exit(1)

if __name__ == "__main__":
    main()
