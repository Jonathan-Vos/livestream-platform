#!/bin/sh
# Schrijft runtime-config naar /usr/share/nginx/html/config.js zodat de
# viewer-pagina deze waarden kan oppikken zonder de image opnieuw te bouwen.
set -e

CONFIG_FILE=/usr/share/nginx/html/config.js

cat > "$CONFIG_FILE" <<EOF
// Auto-generated at container start. Override via env vars.
window.STREAM_URL = "${STREAM_URL}";
window.PAGE_TITLE = "${PAGE_TITLE:-Live Stream}";
EOF

echo "[viewer] config.js gegenereerd:"
echo "  STREAM_URL = ${STREAM_URL:-<leeg>}"
echo "  PAGE_TITLE = ${PAGE_TITLE:-Live Stream}"
