"""Make the comic text detector traceable at a fixed input size.

ogkalu/comic-text-and-bubble-detector is transformers' RTDetrV2ForObjectDetection. Its graph
reads sizes off tensor shapes (feature map sizes for the position embeddings, the anchors and
the deformable attention), and under tracing those reads become tensors that coremltools has
to cast back to ints — which it cannot do for these. The app always feeds 640x640, so every one
of those sizes is a constant: patch() makes the position embeddings and anchors constants
built once, outside the trace, and replaces the deformable attention with a batch-1 version
whose sizes are plain ints. check_patched() verifies the patched model against the stock one.
"""

from __future__ import annotations

import torch
import torch.nn.functional as F
import transformers.models.rt_detr_v2.modeling_rt_detr_v2 as rt
from transformers import RTDetrV2ForObjectDetection

IMAGE_SIZE = 640


def plain(value):
    """Sizes read from tensor shapes are tensors while tracing; make them ints again."""
    if isinstance(value, torch.Tensor) and value.numel() == 1:
        return int(value)
    if isinstance(value, (tuple, list)):
        return type(value)(plain(v) for v in value)
    return value


_constants: dict = {}


def _constant(name, build):
    """A staticmethod returning `build`'s result for the same (plain) arguments, built once."""
    def wrapper(*args, **kwargs):
        args, kwargs = plain(args), {k: plain(v) for k, v in kwargs.items()}
        key = (name, repr(args), repr(sorted(kwargs.items())))
        if key not in _constants:
            _constants[key] = build(*args, **kwargs)
        return _constants[key]
    return staticmethod(wrapper)


def deformable_attention(value, shapes, locations, weights, points, method="default"):
    """multi_scale_deformable_attention_v2 for batch 1, every size a Python int.

    value [1, S, heads, dim]; locations [1, Q, heads, levels*points, 2] in 0...1;
    weights [1, Q, heads, levels*points]. Returns [1, Q, heads*dim].
    """
    if method != "default":
        raise ValueError(f"unsupported deformable attention method {method!r}")
    shapes = plain(shapes)
    heads, dim = int(value.shape[2]), int(value.shape[3])
    values = value[0].permute(1, 2, 0).split([h * w for h, w in shapes], dim=-1)   # [heads, dim, h*w]
    grids = (2 * locations - 1)[0].permute(1, 0, 2, 3).split(points, dim=-2)        # [heads, Q, points, 2]
    sampled = [
        F.grid_sample(v.reshape(heads, dim, h, w), g, mode="bilinear", padding_mode="zeros", align_corners=False)
        for v, g, (h, w) in zip(values, grids, shapes)
    ]                                                                                  # [heads, dim, Q, points]
    w = weights[0].permute(1, 0, 2).unsqueeze(1)                                      # [heads, 1, Q, levels*points]
    out = (torch.cat(sampled, dim=-1) * w).sum(-1)                                    # [heads, dim, Q]
    return out.reshape(heads * dim, -1).transpose(0, 1).unsqueeze(0)


_stock_attention = rt.multi_scale_deformable_attention_v2


def patch() -> None:
    rt.torch_int = int
    rt.torch_compilable_check = lambda *args, **kwargs: None  # a shape assertion, true by construction
    rt.RTDetrV2SinePositionEmbedding._cached_build_2d_sinusoidal_position_embedding = _constant(
        "position", rt.build_2d_sinusoidal_position_embedding
    )
    anchors = rt.RTDetrV2Model._cached_generate_anchors
    rt.RTDetrV2Model._cached_generate_anchors = _constant("anchors", getattr(anchors, "__wrapped__", anchors))
    rt.multi_scale_deformable_attention_v2 = deformable_attention


class Detector(torch.nn.Module):
    """pixel_values [1, 3, 640, 640] in 0...1 -> scores [1, 300, 3] (sigmoid), boxes [1, 300, 4]
    (centre x, centre y, width, height, as fractions of the image)."""

    def __init__(self, model: RTDetrV2ForObjectDetection):
        super().__init__()
        self.model = model

    def forward(self, pixel_values):
        out = self.model(pixel_values=pixel_values)
        return out.logits.sigmoid(), out.pred_boxes


def check_patched(model: RTDetrV2ForObjectDetection, tolerance=1e-4) -> float:
    """Largest score difference between the stock and the patched model on a random input.
    Call before patch(); leaves the model patched."""
    torch.manual_seed(0)
    x = torch.rand(1, 3, IMAGE_SIZE, IMAGE_SIZE)
    with torch.no_grad():
        stock = model(pixel_values=x).logits.sigmoid()
        patch()
        patched = Detector(model)(x)[0]
    worst = float((stock - patched).abs().max())
    if worst > tolerance:
        raise AssertionError(f"patched detector differs from the stock one by {worst}")
    return worst
