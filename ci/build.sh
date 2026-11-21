#!/usr/bin/env bash
# Builds Rico's Windows installer on Linux (used by GitHub Actions).
# Usage: ci/build.sh 1.5.0
set -euo pipefail
VERSION="${1:?version required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${ROOT}/.cache"
OUT="${ROOT}/build/Rico"
GODOT_VER="4.4.1"
WHISPER_TAG="v1.7.6"
LLAMA_TAG="b12590"
LHM_TAG="v0.9.6"
mkdir -p "$CACHE" "$OUT"
cd "$CACHE"

fetch() { [ -f "$2" ] || curl -fsSL -o "$2" "$1"; }

# Godot + Windows export templates
fetch "https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_linux.x86_64.zip" godot.zip
[ -f "Godot_v${GODOT_VER}-stable_linux.x86_64" ] || unzip -oq godot.zip
TPL="$HOME/.local/share/godot/export_templates/${GODOT_VER}.stable"
if [ ! -f "$TPL/windows_release_x86_64.exe" ]; then
  fetch "https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_export_templates.tpz" templates.tpz
  mkdir -p "$TPL"
  unzip -oq -j templates.tpz 'templates/windows_release_x86_64.exe' 'templates/version.txt' -d "$TPL"
fi
GODOT="$CACHE/Godot_v${GODOT_VER}-stable_linux.x86_64"

# Third-party runtimes
fetch "https://github.com/ggml-org/whisper.cpp/releases/download/${WHISPER_TAG}/whisper-bin-x64.zip" whisper.zip
fetch "https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}/llama-${LLAMA_TAG}-bin-win-cpu-x64.zip" llama.zip
fetch "https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}/llama-${LLAMA_TAG}-bin-win-vulkan-x64.zip" llama-vulkan.zip
fetch "https://huggingface.co/onnx-community/snac_24khz-ONNX/resolve/main/onnx/decoder_model.onnx" snac_decoder.onnx
[ -f onnxruntime.whl ] || { pip download --no-deps -q onnxruntime==1.20.1 --platform win_amd64 --python-version 3.12 --only-binary=:all: -d ortwhl && mv ortwhl/*.whl onnxruntime.whl; }
fetch "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/${LHM_TAG}/LibreHardwareMonitor.zip" lhm.zip

# Export the game with the release version stamped in
cd "$ROOT/game"
sed -i "s/^config\/version=.*/config\/version=\"${VERSION}\"/" project.godot
sed -i "s/^application\/file_version=.*/application\/file_version=\"${VERSION}.0\"/; s/^application\/product_version=.*/application\/product_version=\"${VERSION}.0\"/" export_presets.cfg
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/Rico.exe"
[ -f "$OUT/Rico.exe" ] || { echo "export failed"; exit 1; }

# Assemble the folder that gets installed
cd "$OUT"
cp "$ROOT/helper/rico_helper.exe" .
cp "$ROOT/installer/rico.ico" .
cp "$ROOT/installer/README.txt" "$ROOT/installer/LICENSE-Fredoka-font.txt" "$ROOT/installer/LICENSE-tabler-icons.txt" .
mkdir -p whisper brain voice tools/lhm
unzip -oqj "$CACHE/whisper.zip" 'Release/whisper-cli.exe' 'Release/whisper.dll' 'Release/ggml.dll' 'Release/ggml-base.dll' 'Release/ggml-cpu.dll' -d whisper
unzip -oqj "$CACHE/llama.zip" 'llama-server.exe' 'llama-server-impl.dll' 'llama-common.dll' 'llama.dll' 'mtmd.dll' 'ggml.dll' 'ggml-base.dll' 'ggml-rpc.dll' 'ggml-cpu-*.dll' 'libomp.dll' 'LICENSE*' -d brain
# Rico's own voice: Vulkan llama.cpp (AMD/NVIDIA/Intel GPUs, falls back to CPU) + SNAC decoder
unzip -oqj "$CACHE/llama-vulkan.zip" 'llama-server.exe' 'llama-server-impl.dll' 'llama-common.dll' 'llama.dll' 'mtmd.dll' 'ggml.dll' 'ggml-base.dll' 'ggml-rpc.dll' 'ggml-vulkan.dll' 'ggml-cpu-*.dll' 'libomp.dll' -d voice
unzip -oqj "$CACHE/onnxruntime.whl" 'onnxruntime/capi/onnxruntime.dll' -d voice
cp "$CACHE/snac_decoder.onnx" voice/snac_decoder.onnx
cp "$ROOT/helper/rico_voice.exe" voice/
cp "$ROOT/installer/LICENSE-voice.txt" voice/
unzip -oq "$CACHE/lhm.zip" -d tools/lhm -x '*.pdb' '*.xml' '*/*.resources.dll'
curl -fsSL -o whisper/LICENSE-whisper.cpp.txt https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/LICENSE
curl -fsSL -o brain/LICENSE-llama.cpp.txt https://raw.githubusercontent.com/ggml-org/llama.cpp/master/LICENSE
curl -fsSL -o tools/lhm/LICENSE-LibreHardwareMonitor.txt https://raw.githubusercontent.com/LibreHardwareMonitor/LibreHardwareMonitor/master/LICENSE

# Installer
cd "$ROOT/installer"
makensis -V2 -DVERSION="$VERSION" rico.nsi
ls -la "$ROOT/build/Rico-Setup-${VERSION}.exe"
