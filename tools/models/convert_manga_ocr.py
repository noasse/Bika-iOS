"""Convert manga-ocr (kha-white/manga-ocr-base, Apache-2.0) to Core ML for the iOS app.

Produces, in bika/MangaModels/ (git-ignored, bundled by Xcode when present):
  MangaOCREncoder.mlpackage   pixel_values [1,3,224,224] -> encoder_hidden_states [1,197,768]
  MangaOCRDecoder.mlpackage   input_ids [1,L] + encoder_hidden_states -> logits [1,6144] for the last position
  MangaOCRVocab.txt           token id -> text, one per line
  MangaOCRManifest.json       where the weights came from and how they were converted

The app runs the encoder once per text region and the decoder once per output character.
The decoder has only 2 layers, so recomputing the whole prefix each step is cheap and avoids
a stateful KV cache.

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

REPO_ID = "kha-white/manga-ocr-base"
ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "tools" / "models" / ".cache"
OUTPUT = ROOT / "bika" / "MangaModels"
MAX_TOKENS = 300  # the model's own max_length


class Encoder(torch.nn.Module):
    def __init__(self, model: VisionEncoderDecoderModel):
        super().__init__()
        self.encoder = model.encoder

    def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
        return self.encoder(pixel_values=pixel_values).last_hidden_state


class Decoder(torch.nn.Module):
    """Logits for the next token given the whole prefix. No cache: the decoder is 2 layers."""

    def __init__(self, model: VisionEncoderDecoderModel):
        super().__init__()
        self.decoder = model.decoder

    def forward(self, input_ids: torch.Tensor, encoder_hidden_states: torch.Tensor) -> torch.Tensor:
        logits = self.decoder(
            input_ids=input_ids,
            encoder_hidden_states=encoder_hidden_states,
            use_cache=False,
        ).logits
        return logits[:, -1, :]


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

    pixel_values = torch.zeros(1, 3, 224, 224)
    with torch.no_grad():
        encoder = Encoder(model).eval()
        traced_encoder = torch.jit.trace(encoder, pixel_values)
        states = encoder(pixel_values)
        sequence = states.shape[1]

        decoder = Decoder(model).eval()
        example_ids = torch.tensor([[config.decoder_start_token_id, 5, 6]], dtype=torch.int32)
        traced_decoder = torch.jit.trace(decoder, (example_ids, states))

    encoder_ml = ct.convert(
        traced_encoder,
        inputs=[ct.TensorType(name="pixel_values", shape=(1, 3, 224, 224), dtype=np.float32)],
        outputs=[ct.TensorType(name="encoder_hidden_states", dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.precision.FLOAT16,
    )
    decoder_ml = ct.convert(
        traced_decoder,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, ct.RangeDim(1, MAX_TOKENS)), dtype=np.int32),
            ct.TensorType(name="encoder_hidden_states", shape=(1, sequence, hidden), dtype=np.float32),
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
        "image_size": 224,
        "image_mean": [0.5, 0.5, 0.5],
        "image_std": [0.5, 0.5, 0.5],
        "encoder_sequence": sequence,
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
