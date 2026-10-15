# On-device models

Converted locally, never committed: the weights are large and third-party. When a model is
missing the app falls back to the previous recognition path, and tests that need it skip.

## manga-ocr (Japanese text recognition)

Source: [`kha-white/manga-ocr-base`](https://huggingface.co/kha-white/manga-ocr-base), Apache-2.0.

```bash
python3 -m venv --system-site-packages tools/models/.venv
tools/models/.venv/bin/python -m pip install transformers coremltools pillow huggingface_hub
tools/models/.venv/bin/python tools/models/convert_manga_ocr.py
```

Writes `bika/MangaModels/` (git-ignored); Xcode compiles and bundles it when present.

To check the conversion against the original PyTorch model:

```bash
swift tools/models/render_samples.swift tools/models/.cache/samples
tools/models/.venv/bin/python tools/models/verify_manga_ocr.py tools/models/.cache/samples
```

Each sample must decode to identical text with both.

## Comic text detector (finding the text)

Source: [`ogkalu/comic-text-and-bubble-detector`](https://huggingface.co/ogkalu/comic-text-and-bubble-detector)
at revision `16e8a622`, Apache-2.0. An RT-DETR-v2 that finds speech bubbles, text inside
them, and text outside them (narration and notes on the art).

```bash
tools/models/.venv/bin/python tools/models/convert_comic_detector.py
```

Downloads about 170 MB and writes `ComicTextDetectorModel.mlpackage` (about 82 MB) next to
manga-ocr. The script checks the converted model against PyTorch on a rendered page, on CPU
and GPU, which is what the app runs it on; the Neural Engine moved boxes past tolerance.

The detector is only used together with manga-ocr. Without it, bubbles are found by rule.
