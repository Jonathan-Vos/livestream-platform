#!/usr/bin/env bash
set -euo pipefail

# --- Verplichte variabelen controleren ---
if [[ -z "${YOUTUBE_URL:-}" ]]; then
    echo "FOUT: omgevingsvariabele YOUTUBE_URL is verplicht" >&2
    echo "Voorbeeld: -e YOUTUBE_URL=https://www.youtube.com/watch?v=XXXX" >&2
    exit 1
fi

if [[ -z "${OUTPUT_URL:-}" ]]; then
    echo "FOUT: omgevingsvariabele OUTPUT_URL is verplicht" >&2
    echo "Voorbeeld: -e OUTPUT_URL=rtmp://server/live/streamkey" >&2
    exit 1
fi

# --- Defaults voor afgeleide waarden ---
VIDEO_BITRATE="${VIDEO_BITRATE:-8000k}"
VIDEO_MAXRATE="${VIDEO_MAXRATE:-$VIDEO_BITRATE}"

# Bufsize standaard 2x bitrate voor stabielere VBR
if [[ -z "${VIDEO_BUFSIZE:-}" ]]; then
    NUM="${VIDEO_BITRATE%[kKmM]}"
    SUFFIX="${VIDEO_BITRATE: -1}"
    VIDEO_BUFSIZE="$((NUM * 2))${SUFFIX}"
fi

# --- HLS-modus automatiseren ---
# Als OUTPUT_FORMAT=hls en er zijn geen custom HLS-args, vul ze automatisch in.
if [[ "$OUTPUT_FORMAT" == "hls" ]]; then
    HLS_DIR=$(dirname "$OUTPUT_URL")
    mkdir -p "$HLS_DIR"
    chmod 755 "$HLS_DIR" 2>/dev/null || true

    if [[ -z "${EXTRA_FFMPEG_ARGS// }" ]]; then
        SEG_PATTERN="${HLS_DIR}/seg_%05d.ts"
        EXTRA_FFMPEG_ARGS="-hls_time ${HLS_SEGMENT_TIME} -hls_list_size ${HLS_LIST_SIZE} -hls_flags delete_segments+independent_segments+program_date_time -hls_segment_filename ${SEG_PATTERN}"
    fi
fi

echo "=============================================="
echo " YouTube Re-Streamer"
echo "----------------------------------------------"
echo " Bron URL          : $YOUTUBE_URL"
echo " Bron kwaliteit    : $INPUT_QUALITY"
echo " Doel              : $OUTPUT_URL"
echo " Video bitrate     : $VIDEO_BITRATE (max: $VIDEO_MAXRATE, buf: $VIDEO_BUFSIZE)"
echo " Audio bitrate     : $AUDIO_BITRATE @ ${AUDIO_SAMPLERATE}Hz"
echo " x264 preset       : $PRESET"
echo " Keyframe interval : $KEYFRAME_INTERVAL frames"
echo " Output formaat    : $OUTPUT_FORMAT"

# --- RTMPS detectie & TLS-opties opbouwen ---
TLS_ARGS=()
if [[ "$OUTPUT_URL" == rtmps://* ]]; then
    echo " Transport         : RTMPS (TLS)"
    # ffmpeg leest deze als output-opties via -tls_*. Verify staat default aan.
    if [[ "$RTMPS_TLS_VERIFY" == "0" ]]; then
        echo " TLS verificatie   : UIT (onveilig — alleen voor testen!)"
        TLS_ARGS+=(-tls_verify 0)
    else
        TLS_ARGS+=(-tls_verify 1)
        if [[ -n "$RTMPS_CA_FILE" ]]; then
            echo " TLS CA bestand    : $RTMPS_CA_FILE"
            TLS_ARGS+=(-ca_file "$RTMPS_CA_FILE")
        fi
    fi
else
    echo " Transport         : RTMP (onversleuteld)"
fi
echo "=============================================="

# Sanity-check: heeft ffmpeg TLS-ondersteuning?
if [[ "$OUTPUT_URL" == rtmps://* ]]; then
    if ! ffmpeg -hide_banner -protocols 2>/dev/null | grep -q '^ *rtmps$'; then
        echo "WAARSCHUWING: ffmpeg lijkt geen rtmps-protocol te ondersteunen" >&2
    fi
fi

# --- streamlink → ffmpeg pipeline ---
# streamlink onderhoudt de HLS-verbinding met YouTube en geeft een ruwe
# transportstream op stdout. ffmpeg leest die in, encodeert opnieuw met
# de gewenste bitrate en pusht naar de RTMP-bestemming.

# shellcheck disable=SC2086
streamlink \
    --stdout \
    --hls-live-restart \
    --retry-streams 5 \
    --retry-max 10 \
    --twitch-disable-ads \
    "$YOUTUBE_URL" "$INPUT_QUALITY" \
| ffmpeg \
    -hide_banner \
    -loglevel info \
    -fflags +genpts \
    -i pipe:0 \
    -c:v libx264 \
    -preset "$PRESET" \
    -b:v "$VIDEO_BITRATE" \
    -maxrate "$VIDEO_MAXRATE" \
    -bufsize "$VIDEO_BUFSIZE" \
    -pix_fmt "$PIXEL_FORMAT" \
    -g "$KEYFRAME_INTERVAL" \
    -keyint_min "$KEYFRAME_INTERVAL" \
    -sc_threshold 0 \
    -c:a aac \
    -b:a "$AUDIO_BITRATE" \
    -ar "$AUDIO_SAMPLERATE" \
    -ac 2 \
    $EXTRA_FFMPEG_ARGS \
    -f "$OUTPUT_FORMAT" \
    "${TLS_ARGS[@]}" \
    "$OUTPUT_URL"
