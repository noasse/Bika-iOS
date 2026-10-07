"""Convert manga-ocr (kha-white/manga-ocr-base, Apache-2.0) to Core ML for the iOS app.

Produces, in bika/MangaModels/ (git-ignored, bundled by Xcode when present):
  MangaOCREncoder.mlpackage   pixel_values [1,3,224,224]
                              -> cross_keys, cross_values [2,1,12,197,64]
  MangaOCRDecoder.mlpackage   input_ids [1,L] + cross_keys + cross_values -> logits [1,6144]
  MangaOCRVocab.txt           token id -> text, one per line
  MangaOCRManifest.json       where the weights came from, how they were converted, format

The app runs the encoder once per text region and the decoder once per output character.
Format 2 (manga_ocr_modules.py): the decoder's cross-attention keys and values are computed
once per region with the encoder, and the decoder computes logits for the last position only.
Format 1 recomputed both every step, which a device run measured at about 52 ms per character.

Usage (from the repo root):
  tools/models/.venv/bin/python tools/models/convert_manga_ocr.py
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
from transformers import VisionEncoderDecoderModel

from manga_ocr_modules import EncoderWithCrossKV, FastDecoder, check_modules

REPO_ID = "kha-white/manga-ocr-base"
ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "tools" / "models" / ".cache"
OUTPUT = ROOT / "bika" / "MangaModels"
MAX_TOKENS = 300  # the model's own max_length


FORMAT = 2


def main() -> int:
    snapshot = Path(snapshot_download(REPO_ID, cache_dir=str(CACHE)))
    revision = snapshot.name
    # transformers loads pytorch_model.bin with torch.load(weights_only=True): tensors only,
    # no code from the pickle is executed.
    model = VisionEncoderDecoderModel.from_pretrained(str(snapshot)).eval()
    config = model.config
    generation = model.generation_config
    hidden = config.encoder.hidden_size
    vocab_size = config.decoder.vocab_size

    OUTPUT.mkdir(parents=True, exist_ok=True)

    # The hand-built decoder must match the stock one before anything is converted.
    print(f"FastDecoder vs stock decoder, max |Δlogits| (float32): {check_modules(model):.2e}")

    pixel_values = torch.zeros(1, 3, 224, 224)
    with torch.no_grad():
        encoder = EncoderWithCrossKV(model).eval()
        traced_encoder = torch.jit.trace(encoder, pixel_values)
        keys, values = encoder(pixel_values)

        decoder = FastDecoder(model).eval()
        example_ids = torch.tensor([[config.decoder_start_token_id, 5, 6]], dtype=torch.int32)
        traced_decoder = torch.jit.trace(decoder, (example_ids, keys, values))

    kv_shape = tuple(keys.shape)
    encoder_ml = ct.convert(
        traced_encoder,
        inputs=[ct.TensorType(name="pixel_values", shape=(1, 3, 224, 224), dtype=np.float32)],
        outputs=[
            ct.TensorType(name="cross_keys", dtype=np.float32),
            ct.TensorType(name="cross_values", dtype=np.float32),
        ],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.precision.FLOAT16,
    )
    decoder_ml = ct.convert(
        traced_decoder,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, ct.RangeDim(1, MAX_TOKENS)), dtype=np.int32),
            ct.TensorType(name="cross_keys", shape=kv_shape, dtype=np.float32),
            ct.TensorType(name="cross_values", shape=kv_shape, dtype=np.float32),
        ],
        outputs=[ct.TensorType(name="logits", dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.precision.FLOAT16,
    )

    for name, ml in (("MangaOCREncoder", encoder_ml), ("MangaOCRDecoder", decoder_ml)):
        ml.short_description = f"manga-ocr ({REPO_ID}@{revision[:8]}), Apache-2.0"
        target = OUTPUT / f"{name}.mlpackage"
        if target.exists():
            shutil.rmtree(target)
        ml.save(str(target))

    shutil.copyfile(snapshot / "vocab.txt", OUTPUT / "MangaOCRVocab.txt")
    manifest = {
        "source": REPO_ID,
        "revision": revision,
        "license": "Apache-2.0",
        "format": FORMAT,
        "cross_kv_shape": list(kv_shape),
        "image_size": 224,
        "image_mean": [0.5, 0.5, 0.5],
        "image_std": [0.5, 0.5, 0.5],
        "hidden_size": hidden,
        "vocab_size": vocab_size,
        "decoder_start_token_id": config.decoder_start_token_id,
        "eos_token_id": config.eos_token_id,
        "pad_token_id": config.pad_token_id,
        "max_tokens": MAX_TOKENS,
        # transformers 5 keeps generation settings on generation_config, not config.
        "no_repeat_ngram_size": generation.no_repeat_ngram_size,
        "precision": "float16",
        "torch": torch.__version__,
        "coremltools": ct.__version__,
    }
    (OUTPUT / "MangaOCRManifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(manifest, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
