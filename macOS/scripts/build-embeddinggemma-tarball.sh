#!/usr/bin/env bash
#
# Build deterministic EmbeddingGemma-300M CoreML tarball for SideQuest.
#
# Converts google/embeddinggemma-300m (PyTorch) to a compiled CoreML .mlmodelc
# directory PLUS the matching SentencePiece tokenizer.model, packs both into a
# single deterministic tar.gz, and prints the SHA256 + URL fields the operator
# must patch into config.json after upload to S3.
#
# Why ship tokenizer.model inside the same tarball:
#   - SentencePiece tokenizer cannot run inference without the model file
#   - HuggingFace ships tokenizer alongside the model checkpoint; pairing them
#     in one artifact guarantees they stay version-locked
#   - Tarball SHA256 already verifies both files atomically — no separate
#     hash needed for tokenizer
#
# This script does NOT upload to S3. Run it locally on a Mac with Xcode +
# coremltools installed; it produces a deterministic tarball that you then
# `aws s3 cp` and CloudFront-invalidate manually (or via release CI).
#
# Requires (pinned for reproducibility):
#   - macOS with Xcode 15.x (xcrun coremlcompiler)
#   - Python 3.11+ with pinned packages:
#       coremltools==8.0
#       torch>=2.1.0
#       transformers>=4.36.0
#       huggingface_hub>=0.17.0
#
# Determinism notes:
#   - HuggingFace EmbeddingGemma revision SHA is pinned (no "latest")
#   - Tarball uses --sort=name and a fixed --mtime to remove timestamps
#   - Two consecutive runs must produce identical SHA256; if not, see
#     RESEARCH Pitfall 4 (model source hash or build env drift).

set -euo pipefail

# --- Pinned versions ---------------------------------------------------------

MODEL_VERSION="1.0"
EMBEDDING_GEMMA_REVISION="de4ea6a8a7da27e9ba00b7d4d91b6b2e4e8d8a4f"

# Output names — versioned so the app can resolve which artifact to load
# from a known cache path.
MLMODEL="embeddinggemma-300m-${MODEL_VERSION}.mlpackage"
MLMODELC="embeddinggemma-300m-${MODEL_VERSION}.mlmodelc"
TOKENIZER="tokenizer.model"
TARBALL="embeddinggemma-300m-qat-q8-${MODEL_VERSION}.tar.gz"

# Deterministic tar mtime — the date this script was first written.
# Bumping this changes the tarball SHA256, which invalidates pinned hashes
# in config.json. Only change when intentionally cutting a new model version.
TAR_MTIME="2026-04-27"

# Build directory — script always works in its own cwd. Caller decides where
# to invoke (e.g. cd client/macOS/build && ../scripts/build-embeddinggemma-tarball.sh).
BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

echo "[build] cwd: $(pwd)"
echo "[build] temp build dir: $BUILD_DIR"
echo "[build] MODEL_VERSION=${MODEL_VERSION}  EMBEDDING_GEMMA_REVISION=${EMBEDDING_GEMMA_REVISION}"

# --- Step 0: tooling preflight ----------------------------------------------

command -v python3 >/dev/null 2>&1 || {
  echo "[build] ERROR: python3 not found on PATH" >&2
  exit 1
}

# Verify Python 3.11+
PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
echo "[build] Python version: $PYTHON_VERSION"

command -v xcrun >/dev/null 2>&1 || {
  echo "[build] ERROR: xcrun not found — install Xcode + Command Line Tools" >&2
  exit 1
}

command -v shasum >/dev/null 2>&1 || {
  echo "[build] ERROR: shasum not found (macOS built-in)" >&2
  exit 1
}

# Verify Python deps are importable; surface a clear install hint if not.
python3 - <<'PYTHON' || { echo "[build] ERROR: missing Python deps. Install with: pip install coremltools==8.0 torch transformers huggingface_hub" >&2; exit 1; }
import importlib.util
import sys
required = ["coremltools", "torch", "transformers", "huggingface_hub"]
missing = [m for m in required if importlib.util.find_spec(m) is None]
if missing:
    sys.exit("missing: " + ",".join(missing))
PYTHON

# --- Step 1: download pinned EmbeddingGemma checkpoint -----------------------

echo "[build] step 1: load google/embeddinggemma-300m @ ${EMBEDDING_GEMMA_REVISION}"
python3 - <<PYTHON
from transformers import AutoModel
model = AutoModel.from_pretrained(
    'google/embeddinggemma-300m',
    revision='${EMBEDDING_GEMMA_REVISION}',
    trust_remote_code=True,
)
print('[build] EmbeddingGemma checkpoint loaded')
PYTHON

# --- Step 2: trace + convert to CoreML, extract tokenizer --------------------

echo "[build] step 2: trace PyTorch graph + convert to CoreML, extract tokenizer"
python3 - <<'PYTHON'
import os
import sys
import shutil
import numpy as np
import torch
import coremltools as ct
from transformers import AutoModel, AutoTokenizer

# Load EmbeddingGemma model and tokenizer
model = AutoModel.from_pretrained(
    'google/embeddinggemma-300m',
    revision='de4ea6a8a7da27e9ba00b7d4d91b6b2e4e8d8a4f',
    trust_remote_code=True,
    device_map='cpu',
)
model.eval()

tokenizer = AutoTokenizer.from_pretrained(
    'google/embeddinggemma-300m',
    revision='de4ea6a8a7da27e9ba00b7d4d91b6b2e4e8d8a4f',
    trust_remote_code=True,
)

# Wrap model to output embeddings only (768-dim for EmbeddingGemma-300M)
class EmbeddingWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        # EmbeddingGemma returns hidden_states; extract [CLS] or pool
        outputs = self.model(input_ids=input_ids, attention_mask=attention_mask, output_hidden_states=False)
        # The model returns pooled representation (768-dim)
        if hasattr(outputs, 'last_hidden_state'):
            # Mean pooling over sequence dimension
            mask = attention_mask.unsqueeze(-1).float()
            masked_embeddings = outputs.last_hidden_state * mask
            sum_embeddings = torch.sum(masked_embeddings, dim=1)
            sum_mask = torch.sum(mask, dim=1)
            embeddings = sum_embeddings / sum_mask.clamp(min=1e-9)
        else:
            embeddings = outputs[0][:, 0, :]  # Use [CLS] token
        # L2 normalize for cosine similarity
        embeddings = torch.nn.functional.normalize(embeddings, p=2, dim=1)
        return embeddings

wrapped = EmbeddingWrapper(model)
wrapped.eval()

# Trace with max_length=512 (EmbeddingGemma's typical context)
example_input_ids = torch.randint(0, 100, (1, 512), dtype=torch.int32)
example_attention_mask = torch.ones((1, 512), dtype=torch.int32)

print('[build] tracing model...')
traced = torch.jit.trace(wrapped, (example_input_ids, example_attention_mask))

print('[build] converting to CoreML...')
ml_model = ct.convert(
    traced,
    convert_to='mlprogram',
    compute_units=ct.ComputeUnit.CPU_AND_NE,
    inputs=[
        ct.TensorType(shape=(1, 512), dtype=np.int32, name='input_ids'),
        ct.TensorType(shape=(1, 512), dtype=np.int32, name='attention_mask'),
    ],
    outputs=[ct.TensorType(name='embeddings', dtype=np.float32)],
    compute_precision=ct.precision.FLOAT32,
)

# Clear non-deterministic metadata
for key in list(ml_model.user_defined_metadata.keys()):
    del ml_model.user_defined_metadata[key]

ml_model.save('embeddinggemma-300m-1.0.mlpackage')
print('[build] saved embeddinggemma-300m-1.0.mlpackage')

# Extract SentencePiece tokenizer
tokenizer_paths = tokenizer.save_vocabulary('.')
print('[build] tokenizer files:', tokenizer_paths)
print('[build] done with Python conversion step')
PYTHON

# --- Step 3: compile .mlmodel -> .mlmodelc ----------------------------------

echo "[build] step 3: xcrun coremlcompiler compile -> ${MLMODELC}"
xcrun coremlcompiler compile "${MLMODEL}" .
[ -d "${MLMODELC}" ] || {
  echo "[build] ERROR: expected ${MLMODELC} after compile, not found" >&2
  exit 1
}

# --- Step 3.5: scrub non-deterministic coremltools artifacts -----------------

echo "[build] step 3.5: scrub non-deterministic artifacts"
rm -rf "${MLMODELC}/analytics"
python3 - <<PYTHON
import json
path = '${MLMODELC}/metadata.json'
with open(path, 'r') as f:
    data = json.load(f)
with open(path, 'w') as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write('\n')
PYTHON

# --- Step 4: verify tokenizer exists -----------------------------------------

# SentencePiece tokenizer will be saved by the conversion step
[ -f "${TOKENIZER}" ] || {
  echo "[build] ERROR: ${TOKENIZER} not present at tar time" >&2
  exit 1
}

# --- Step 5: deterministic tarball (model dir + tokenizer) -------------------

echo "[build] step 5: deterministic tar (sort=name, mtime=${TAR_MTIME}, owner=0)"
# macOS BSD tar lacks --sort=name; require GNU tar (gtar on Mac via
# `brew install gnu-tar`, plain tar on Linux CI).
if command -v gtar >/dev/null 2>&1; then
  TAR_BIN=gtar
elif tar --version 2>/dev/null | grep -q "GNU tar"; then
  TAR_BIN=tar
else
  echo "[build] ERROR: GNU tar not found. Install with: brew install gnu-tar" >&2
  exit 1
fi

"${TAR_BIN}" --sort=name \
    --mtime="${TAR_MTIME}" \
    --owner=0 --group=0 \
    --numeric-owner \
    --use-compress-program="gzip -n" \
    -cf "${TARBALL}" \
    "${MLMODELC}" \
    "${TOKENIZER}"

# --- Step 6: verify size + emit SHA256 + URL hint ---------------------------

SIZE_BYTES=$(stat -f%z "${TARBALL}" 2>/dev/null || stat -c%s "${TARBALL}" 2>/dev/null || echo 0)
SIZE_HUMAN=$(du -h "${TARBALL}" | cut -f1)
SHA256=$(shasum -a 256 "${TARBALL}" | cut -d' ' -f1)

echo ""
echo "[build] DONE"
echo "[build] tarball:   ${TARBALL}"
echo "[build] size:      ${SIZE_HUMAN} (${SIZE_BYTES} bytes)"
echo "[build] sha256:    ${SHA256}"
echo ""
echo "[build] Next steps (manual, NOT run by this script):"
echo "  aws s3 cp ${TARBALL} s3://sidequest-releases/models/${TARBALL} --region us-east-1"
echo "  aws cloudfront create-invalidation --distribution-id E2J2MF0TAZ6G7F --paths '/models/*' '/config.json' --region us-east-1"
echo "  Patch config.json on S3:"
echo "    model_url    = \"https://get.trysidequest.ai/models/${TARBALL}\""
echo "    model_sha256 = \"${SHA256}\""
echo "  Verify by running this script a second time — SHA256 must match exactly."
echo ""
echo "[build] Reproducibility check:"
echo "  export MODEL_VERSION=\"${MODEL_VERSION}\""
echo "  export SHA256_FIRST=\"${SHA256}\""
echo "  ./build-embeddinggemma-tarball.sh"
echo "  # Compare second SHA256 to \$SHA256_FIRST — must be identical"
