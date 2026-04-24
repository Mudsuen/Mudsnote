#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="${ROOT_DIR}/assets/source"
GENERATED_DIR="${ROOT_DIR}/assets/generated"
TMP_DIR="$(mktemp -d)"
ICONSET_DIR="${GENERATED_DIR}/MudsnoteAppIcon.iconset"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

render_svg() {
    local svg_path="$1"
    local size="$2"
    qlmanage -t -s "${size}" -o "${TMP_DIR}" "${svg_path}" >/dev/null 2>&1
    find "${TMP_DIR}" -maxdepth 1 -type f -name "$(basename "${svg_path}")*.png" | head -n 1
}

resize_png() {
    local input_png="$1"
    local size="$2"
    local output_png="$3"
    sips -z "${size}" "${size}" "${input_png}" --out "${output_png}" >/dev/null
}

mkdir -p "${GENERATED_DIR}"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

APP_SVG="${SOURCE_DIR}/mudsnote-app-icon.svg"
STATUS_SVG="${SOURCE_DIR}/mudsnote-status-template.svg"

BASE_ICON_PNG="$(render_svg "${APP_SVG}" 1024)"
if [[ -z "${BASE_ICON_PNG}" || ! -f "${BASE_ICON_PNG}" ]]; then
    echo "Failed to render app icon SVG" >&2
    exit 1
fi

for spec in \
    "16:icon_16x16.png" \
    "32:icon_16x16@2x.png" \
    "32:icon_32x32.png" \
    "64:icon_32x32@2x.png" \
    "128:icon_128x128.png" \
    "256:icon_128x128@2x.png" \
    "256:icon_256x256.png" \
    "512:icon_256x256@2x.png" \
    "512:icon_512x512.png" \
    "1024:icon_512x512@2x.png"; do
    size="${spec%%:*}"
    name="${spec#*:}"
    resize_png "${BASE_ICON_PNG}" "${size}" "${ICONSET_DIR}/${name}"
done

rm -f "${GENERATED_DIR}/MudsnoteAppIcon.icns"
iconutil -c icns "${ICONSET_DIR}" -o "${GENERATED_DIR}/MudsnoteAppIcon.icns"

BASE_STATUS_PNG="$(render_svg "${STATUS_SVG}" 64)"
if [[ -z "${BASE_STATUS_PNG}" || ! -f "${BASE_STATUS_PNG}" ]]; then
    echo "Failed to render status icon SVG" >&2
    exit 1
fi

resize_png "${BASE_STATUS_PNG}" 36 "${GENERATED_DIR}/MudsnoteStatusTemplate.png"
