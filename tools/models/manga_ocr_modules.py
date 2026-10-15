"""Inference-shaped modules for manga-ocr's decoder, built from the original weights.

The stock decoder recomputes everything on every step. Measured from a device run, reading
bubbles was 80% of page time at about 52 ms per generated character, with the decoder on the
CPU (a Core ML compute plan places every decoder op there). Per step it was:
  - projecting all 197 encoder states to keys and values for cross-attention (~465M
    multiply-adds) — the same result every step;
  - running the 2 layers over the whole prefix;
  - computing vocabulary logits for every position, of which only the last is used.

Here the cross-attention keys and values are computed once per text region, alongside the
encoder, and the decoder computes logits for the last position only. The arithmetic is the
same as BertLMHeadModel's, which check_modules() verifies.
"""

from __future__ import annotations

import math

import torch
import torch.nn.functional as F
from transformers import VisionEncoderDecoderModel

MASK_VALUE = -1e4  # finite, so it survives float16


# Reshapes use constants and -1 rather than sizes read from the tensor: under a dynamic prefix
# length those reads become runtime values that coremltools cannot turn into constants.
def split_heads(x: torch.Tensor, heads: int, head_size: int) -> torch.Tensor:
    return x.view(1, -1, heads, head_size).transpose(1, 2)


def merge_heads(x: torch.Tensor, heads: int, head_size: int) -> torch.Tensor:
    return x.transpose(1, 2).reshape(1, -1, heads * head_size)


class EncoderWithCrossKV(torch.nn.Module):
    """ViT encoder plus every decoder layer's cross-attention keys and values.

    Outputs cross_keys and cross_values, each [layers, 1, heads, 197, head_size].
    """

    def __init__(self, model: VisionEncoderDecoderModel):
        super().__init__()
        self.encoder = model.encoder
        layers = model.decoder.bert.encoder.layer
        self.keys = torch.nn.ModuleList(layer.crossattention.self.key for layer in layers)
        self.values = torch.nn.ModuleList(layer.crossattention.self.value for layer in layers)
        config = model.decoder.config
        self.heads = config.num_attention_heads
        self.head_size = config.hidden_size // config.num_attention_heads

    def forward(self, pixel_values: torch.Tensor):
        states = self.encoder(pixel_values=pixel_values).last_hidden_state
        keys = torch.stack([split_heads(key(states), self.heads, self.head_size) for key in self.keys])
        values = torch.stack([split_heads(value(states), self.heads, self.head_size) for value in self.values])
        return keys, values


class FastDecoder(torch.nn.Module):
    """Logits for the next token, given the prefix and precomputed cross-attention keys/values."""

    def __init__(self, model: VisionEncoderDecoderModel):
        super().__init__()
        decoder = model.decoder
        config = decoder.config
        self.embeddings = decoder.bert.embeddings
        self.layers = decoder.bert.encoder.layer
        self.head = decoder.cls.predictions
        self.heads = config.num_attention_heads
        self.head_size = config.hidden_size // config.num_attention_heads
        self.scale = 1.0 / math.sqrt(self.head_size)

    def attend(self, query, key, value, mask=None):
        scores = torch.matmul(query, key.transpose(-1, -2)) * self.scale
        if mask is not None:
            scores = scores + mask
        return torch.matmul(torch.softmax(scores, dim=-1), value)

    def forward(
        self,
        input_ids: torch.Tensor,
        cross_keys: torch.Tensor,
        cross_values: torch.Tensor,
        last_index: torch.Tensor,
    ) -> torch.Tensor:
        """`input_ids` may be padded at the end to a fixed length; `last_index` is the position of
        the last real token. The causal mask keeps padding from influencing earlier positions."""
        # Positions and the causal mask come from the input itself, so a traced graph works
        # for every prefix length rather than the one it was traced with.
        positions = torch.cumsum(torch.ones_like(input_ids), dim=1) - 1
        e = self.embeddings
        x = e.word_embeddings(input_ids) + e.position_embeddings(positions) \
            + e.token_type_embeddings(torch.zeros_like(input_ids))
        x = e.LayerNorm(x)
        later = (positions.unsqueeze(1) > positions.unsqueeze(2)).to(x.dtype)  # [1, L, L]: key after query
        mask = (later * MASK_VALUE).unsqueeze(1)

        for index, layer in enumerate(self.layers):
            own = layer.attention
            q = split_heads(own.self.query(x), self.heads, self.head_size)
            k = split_heads(own.self.key(x), self.heads, self.head_size)
            v = split_heads(own.self.value(x), self.heads, self.head_size)
            x = own.output.LayerNorm(x + own.output.dense(merge_heads(self.attend(q, k, v, mask), self.heads, self.head_size)))

            cross = layer.crossattention
            q = split_heads(cross.self.query(x), self.heads, self.head_size)
            attended = self.attend(q, cross_keys[index], cross_values[index])
            x = cross.output.LayerNorm(x + cross.output.dense(merge_heads(attended, self.heads, self.head_size)))

            hidden = F.gelu(layer.intermediate.dense(x))
            x = layer.output.LayerNorm(x + layer.output.dense(hidden))

        last = torch.index_select(x, 1, last_index)[:, 0, :]
        transform = self.head.transform
        last = transform.LayerNorm(F.gelu(transform.dense(last)))
        return self.head.decoder(last)  # [1, vocab]


def check_modules(
    model: VisionEncoderDecoderModel,
    lengths=(1, 2, 7, 16, 23, 64),
    padded_to=(16, 32, 64, 128),
    tolerance=1e-3,
) -> float:
    """Largest difference between FastDecoder and the stock decoder's last-position logits, with
    the prefix both unpadded and padded to every fixed length at least as long as it."""
    encoder = EncoderWithCrossKV(model).eval()
    fast = FastDecoder(model).eval()
    torch.manual_seed(0)
    pixels = torch.randn(1, 3, 224, 224)
    worst = 0.0
    with torch.no_grad():
        states = model.encoder(pixel_values=pixels).last_hidden_state
        keys, values = encoder(pixels)
        for length in lengths:
            ids = torch.randint(5, model.decoder.config.vocab_size, (1, length))
            ids[0, 0] = model.config.decoder_start_token_id
            stock = model.decoder(input_ids=ids, encoder_hidden_states=states, use_cache=False).logits[:, -1, :]
            last = torch.tensor([length - 1])
            worst = max(worst, float((stock - fast(ids, keys, values, last)).abs().max()))
            for size in (size for size in padded_to if size >= length):
                padded = torch.zeros(1, size, dtype=ids.dtype)
                padded[0, :length] = ids[0]
                worst = max(worst, float((stock - fast(padded, keys, values, last)).abs().max()))
    if worst > tolerance:
        raise AssertionError(f"FastDecoder differs from the stock decoder by {worst}")
    return worst
