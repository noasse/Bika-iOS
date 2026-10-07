"""Check the converted Core ML manga-ocr models against the original PyTorch model.

For each sample image: decode greedily with the stock PyTorch model and with Core ML (same preprocessing,
same no-repeat-3-gram rule), require identical text, and report the largest logit difference
at every decoding step — which covers every prefix length the decoder sees, since its input
length was traced at one value and must work at all of them.

Usage (from the repo root):
  swift tools/models/render_samples.swift tools/models/.cache/samples
  tools/models/.venv/bin/python tools/models/verify_manga_ocr.py tools/models/.cache/samples
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from huggingface_hub import snapshot_download
from PIL import Image
from transformers import VisionEncoderDecoderModel

ROOT = Path(__file__).resolve().parents[2]
MODELS = ROOT / "bika" / "MangaModels"
CACHE = ROOT / "tools" / "models" / ".cache"


def preprocess(path: Path) -> np.ndarray:
    # As upstream manga-ocr: grayscale, back to RGB, bilinear 224x224, then (x - 0.5) / 0.5.
    image = Image.open(path).convert("L").convert("RGB").resize((224, 224), Image.BILINEAR)
    array = np.asarray(image, dtype=np.float32) / 255.0
    array = (array - 0.5) / 0.5
    return array.transpose(2, 0, 1)[None]


def banned_tokens(ids: list[int], n: int) -> set[int]:
    """Tokens that would repeat an n-gram already in `ids` (transformers' no_repeat_ngram)."""
    if len(ids) + 1 < n:
        return set()
    prefix = tuple(ids[-(n - 1):])
    return {ids[i + n - 1] for i in range(len(ids) - n + 1) if tuple(ids[i:i + n - 1]) == prefix}


def greedy(step, start: int, eos: int, max_tokens: int, n: int):
    ids = [start]
    logits_seen = []
    while len(ids) < max_tokens:
        logits = step(ids)
        logits_seen.append(logits)
        masked = logits.copy()
        for token in banned_tokens(ids, n):
            masked[token] = -np.inf
        token = int(masked.argmax())
        ids.append(token)
        if token == eos:
            break
    return ids, logits_seen


def detokenize(ids: list[int], vocab: list[str]) -> str:
    text = "".join(vocab[i].removeprefix("##") for i in ids if i > 4)  # 0-4 are special tokens
    return "".join(text.split())


def main() -> int:
    samples = sorted(Path(sys.argv[1]).glob("*.png")) if len(sys.argv) > 1 else []
    if not samples:
        print("no samples; render them with render_samples.swift first")
        return 1

    manifest = json.loads((MODELS / "MangaOCRManifest.json").read_text())
    vocab = (MODELS / "MangaOCRVocab.txt").read_text(encoding="utf-8").split("\n")
    start, eos, n, max_tokens = (manifest[k] for k in ("decoder_start_token_id", "eos_token_id", "no_repeat_ngram_size", "max_tokens"))

    snapshot = snapshot_download(manifest["source"], revision=manifest["revision"], cache_dir=str(CACHE))
    torch_model = VisionEncoderDecoderModel.from_pretrained(snapshot).eval()
    encoder = ct.models.MLModel(str(MODELS / "MangaOCREncoder.mlpackage"))
    decoder = ct.models.MLModel(str(MODELS / "MangaOCRDecoder.mlpackage"))

    failures = 0
    for path in samples:
        pixels = preprocess(path)
        with torch.no_grad():
            states_torch = torch_model.encoder(pixel_values=torch.from_numpy(pixels)).last_hidden_state

            def torch_step(ids):
                out = torch_model.decoder(
                    input_ids=torch.tensor([ids]), encoder_hidden_states=states_torch, use_cache=False
                ).logits
                return out[0, -1].numpy()

            torch_ids, torch_logits = greedy(torch_step, start, eos, max_tokens, n)

        cross = encoder.predict({"pixel_values": pixels})
        keys, values = cross["cross_keys"].astype(np.float32), cross["cross_values"].astype(np.float32)

        def ml_step(ids):
            return decoder.predict({
                "input_ids": np.array([ids], dtype=np.int32),
                "cross_keys": keys,
                "cross_values": values,
            })["logits"][0]

        ml_ids, ml_logits = greedy(ml_step, start, eos, max_tokens, n)

        # Reference cross-attention keys from the stock decoder's own projection.
        with torch.no_grad():
            layer = torch_model.decoder.bert.encoder.layer[0].crossattention.self
            heads = torch_model.decoder.config.num_attention_heads
            reference = layer.key(states_torch).view(1, -1, heads, keys.shape[-1]).transpose(1, 2).numpy()
        encoder_diff = float(np.abs(keys[0] - reference).max())
        step_diffs = [float(np.abs(a - b).max()) for a, b in zip(torch_logits, ml_logits)]
        same = torch_ids == ml_ids
        failures += 0 if same else 1
        print(f"{path.stem:22} torch={detokenize(torch_ids, vocab)!r:28} coreml={detokenize(ml_ids, vocab)!r:28} "
              f"{'SAME' if same else 'DIFFERENT'}  steps={len(ml_ids) - 1}  "
              f"max|Δcross keys|={encoder_diff:.3f}  max|Δlogits| per step={max(step_diffs):.3f}")

    print(f"\n{len(samples) - failures}/{len(samples)} samples decode identically")
    return 0 if failures == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
