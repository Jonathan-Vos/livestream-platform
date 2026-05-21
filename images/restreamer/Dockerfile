FROM alpine:3.20

LABEL org.opencontainers.image.title="YouTube Re-Streamer" \
      org.opencontainers.image.description="Pakt een YouTube livestream, transcodeert met instelbare bitrate, en streamt naar een RTMP-bestemming" \
      org.opencontainers.image.licenses="MIT"

RUN apk add --no-cache \
        ffmpeg \
        python3 \
        py3-pip \
        bash \
        ca-certificates \
        tini \
    && pip install --no-cache-dir --break-system-packages streamlink \
    && rm -rf /var/cache/apk/* /root/.cache

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default-instellingen, override via `docker run -e`
ENV YOUTUBE_URL="" \
    OUTPUT_URL="" \
    VIDEO_BITRATE="8000k" \
    AUDIO_BITRATE="192k" \
    VIDEO_MAXRATE="" \
    VIDEO_BUFSIZE="" \
    PRESET="veryfast" \
    INPUT_QUALITY="best" \
    KEYFRAME_INTERVAL="60" \
    PIXEL_FORMAT="yuv420p" \
    AUDIO_SAMPLERATE="44100" \
    OUTPUT_FORMAT="flv" \
    EXTRA_FFMPEG_ARGS="" \
    RTMPS_TLS_VERIFY="1" \
    RTMPS_CA_FILE="" \
    HLS_SEGMENT_TIME="4" \
    HLS_LIST_SIZE="6"

# Tini als PID 1 voor nette signal-handling (Ctrl+C / docker stop)
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
