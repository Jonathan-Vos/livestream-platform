FROM nginx:1.27-alpine

LABEL org.opencontainers.image.title="Livestream Viewer" \
      org.opencontainers.image.description="HLS-viewer met hls.js, STREAM_URL configureerbaar via env var"

# Static assets
COPY html/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Runtime-injectie van STREAM_URL via /docker-entrypoint.d/
# (nginx:alpine voert scripts uit /docker-entrypoint.d/*.sh uit bij start)
COPY 20-stream-config.sh /docker-entrypoint.d/20-stream-config.sh
RUN chmod +x /docker-entrypoint.d/20-stream-config.sh

ENV STREAM_URL="" \
    PAGE_TITLE="Live Stream"

EXPOSE 80
