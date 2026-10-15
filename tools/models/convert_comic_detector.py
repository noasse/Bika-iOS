"""Convert the comic text detector (ogkalu/comic-text-and-bubble-detector, Apache-2.0) to Core ML.

An RT-DETR-v2 (ResNet-50) trained on about 11k manga, webtoon, manhua and western comic pages.
It finds three kinds of region: speech bubbles, text inside bubbles, and text outside them
(narration and notes on the art). It replaces the app's rule-based bubble finding, which took
any flat light area with dark marks in it for a bubble — on a device run more than half the
regions it handed to the reader were not text — and could not see text that is not in a light
closed bubble at all.

Produces, in bika/MangaModels/ (git-ignored, bundled by Xcode when present):
  ComicTextDetectorModel.mlpackage    pixel_values [1,3,640,640], RGB in 0...1, stretched
                                      -> scores [1,300,3] (sigmoid), boxes [1,300,4]
                                         (centre x, centre y, width, height; fractions)
  ComicTextDetectorManifest.json      where the weights came from, labels, format

The Core ML model is checked against the PyTorch one on a rendered page, on CPU and GPU — the
compute units the app uses.

Usage (from the repo root):
  tools/models/.venv/bin/python tools/models/convert_comic_detector.py
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from huggingface_hub import snapshot_download
from PIL import Image, ImageDraw, ImageFont
from transformers import RTDetrV2ForObjectDetection

from comic_detector_modules import IMAGE_SIZE, Detector, check_patched

REPO_ID = "ogkalu/comic-text-and-bubble-detector"
REVISION = "16e8a622f91fabc6b5b65c96d32d1183f8843546"
ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "tools" / "models" / ".cache"
OUTPUT = ROOT / "bika" / "MangaModels"
FORMAT = 1


def main() -> int:
    snapshot = Path(snapshot_download(
        REPO_ID, revision=REVISION, cache_dir=str(CACHE),
        allow_patterns=["model.safetensors", "config.json", "preprocessor_config.json", "README.md"],
    ))
    processor = json.loads((snapshot / "preprocessor_config.json").read_text())
    # The app's preprocessing is written for exactly this; fail loudly if upstream changes it.
    assert processor["size"] == {"height": IMAGE_SIZE, "width": IMAGE_SIZE}, processor["size"]
    assert processor["do_rescale"] and not processor["do_normalize"] and not processor["do_pad"], processor

    model = RTDetrV2ForObjectDetection.from_pretrained(str(snapshot)).eval()
    labels = [model.config.id2label[i] for i in range(len(model.config.id2label))]
    print(f"patched vs stock detector, max |Δscore| (float32): {check_patched(model):.2e}")

    detector = Detector(model).eval()
    example = torch.rand(1, 3, IMAGE_SIZE, IMAGE_SIZE)
    with torch.no_grad():
        traced = torch.jit.trace(detector, example, strict=False, check_trace=False)
    ml = ct.convert(
        traced,
        inputs=[ct.TensorType(name="pixel_values", shape=(1, 3, IMAGE_SIZE, IMAGE_SIZE), dtype=np.float32)],
        outputs=[ct.TensorType(name="scores", dtype=np.float32), ct.TensorType(name="boxes", dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.precision.FLOAT16,
    )
    ml.short_description = f"comic text detector ({REPO_ID}@{REVISION[:8]}), Apache-2.0"

    OUTPUT.mkdir(parents=True, exist_ok=True)
    target = OUTPUT / "ComicTextDetectorModel.mlpackage"
    if target.exists():
        shutil.rmtree(target)
    ml.save(str(target))

    failures = compare_on_rendered_page(detector, target, labels)

    manifest = {
        "source": REPO_ID,
        "revision": REVISION,
        "license": "Apache-2.0",
        "format": FORMAT,
        "image_size": IMAGE_SIZE,
        "labels": labels,
        "precision": "float16",
        "torch": torch.__version__,
        "coremltools": ct.__version__,
    }
    (OUTPUT / "ComicTextDetectorManifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    return 0 if failures == 0 else 2


def render_page(width=1280, height=1807) -> Image.Image:
    """A page with the cases the rule-based detector missed: gray and black bubbles, a bubble
    cut by the page edge, and vertical narration on hatched art."""
    page = Image.new("L", (width, height), 255)
    draw = ImageDraw.Draw(page)
    font = ImageFont.truetype("/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc", 40)
    for x in range(0, width + height, 14):
        draw.line([(x, 900), (x - 900, height)], fill=90, width=3)
    draw.rectangle([40, 40, width - 40, height - 40], outline=0, width=6)

    def column_text(right, top, columns, fill):
        for c, text in enumerate(columns):
            for r, ch in enumerate(text):
                draw.text((right - c * 52, top + r * 46), ch, font=font, fill=fill)

    for box, columns, background, ink in [
        ((760, 100, 1100, 560), ["本当に", "それで", "いいの？"], 255, 0),
        ((380, 120, 680, 520), ["話を", "聞いて"], 170, 0),
        ((90, 600, 400, 1000), ["おい", "待てよ"], 0, 255),
        ((1050, 700, 1400, 1150), ["ここだ", "よ"], 255, 0),
    ]:
        draw.ellipse(box, fill=background, outline=255 - ink if background == 0 else 0, width=5)
        rows = max(len(t) for t in columns)
        right = min((box[0] + box[2]) // 2 + 26 * (len(columns) - 1), width - 60)
        column_text(right, (box[1] + box[3]) // 2 - rows * 23, columns, ink)
    column_text(700, 1150, ["その日", "僕は"], 0)
    return page.convert("RGB")


def detections(scores, boxes, labels, size, threshold=0.3):
    best, label = scores.max(-1), scores.argmax(-1)
    width, height = size
    return [
        (labels[int(label[i])], float(best[i]),
         ((boxes[i][0] - boxes[i][2] / 2) * width, (boxes[i][1] - boxes[i][3] / 2) * height,
          (boxes[i][0] + boxes[i][2] / 2) * width, (boxes[i][1] + boxes[i][3] / 2) * height))
        for i in np.argsort(-best) if best[i] >= threshold
    ]


def iou(a, b):
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    if w <= 0 or h <= 0:
        return 0.0
    inter = w * h
    return inter / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter)


def compare_on_rendered_page(detector, package: Path, labels) -> int:
    """Every detection one side makes above 0.3 must be matched on the other side by the same
    label at IoU >= 0.85 and a score within 0.05. Compared per detection, not per query: the
    300 queries are a top-k over encoder scores, whose order float16 can shuffle."""
    page = render_page()
    pixels = (np.asarray(page.resize((IMAGE_SIZE, IMAGE_SIZE), Image.BILINEAR), np.float32) / 255).transpose(2, 0, 1)[None]
    with torch.no_grad():
        s, b = detector(torch.from_numpy(pixels))
    reference = detections(s[0].numpy(), b[0].numpy(), labels, page.size)
    print("PyTorch:", [(label, round(score, 2)) for label, score, _ in reference])

    # The app runs the detector on CPU and GPU. Allowing the Neural Engine moved the narration
    # box on this page well past the tolerance and added a spurious low-scoring one.
    failures = 0
    for units in (ct.ComputeUnit.CPU_AND_GPU,):
        result = ct.models.MLModel(str(package), compute_units=units).predict({"pixel_values": pixels})
        found = detections(result["scores"][0], result["boxes"][0], labels, page.size)
        unmatched = [
            (side, label, round(score, 2))
            for side, ours, theirs in (("PyTorch", reference, found), ("Core ML", found, reference))
            for label, score, box in ours
            if not any(l == label and iou(box, other) >= 0.85 and abs(s - score) <= 0.05 for l, s, other in theirs)
        ]
        failures += len(unmatched)
        print(f"Core ML {units.name}: {len(found)} detections, "
              f"{'all matched' if not unmatched else f'unmatched {unmatched}'}")
    return failures


if __name__ == "__main__":
    sys.exit(main())
