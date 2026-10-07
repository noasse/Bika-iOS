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
