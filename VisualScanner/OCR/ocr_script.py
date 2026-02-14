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
            # New predict() API: result is a dict-like OCRResult with 'rec_texts' key
            if isinstance(res, dict) and 'rec_texts' in res:
                lines.extend(res['rec_texts'])
            elif isinstance(res, list):
                # Legacy ocr() API fallback
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
