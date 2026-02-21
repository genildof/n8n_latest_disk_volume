# ============================================================
# STAGE 1: FFmpeg estático (sem dependências de SO)
# ============================================================
FROM mwader/static-ffmpeg:6.0 AS ffmpeg-source

# ============================================================
# STAGE 2: n8n com FFmpeg embutido
# Compatível com n8n 2.x (task runners internos)
# ============================================================
FROM docker.n8n.io/n8nio/n8n:2.83.0

USER root

# Copia os binários estáticos do FFmpeg
COPY --from=ffmpeg-source /ffmpeg  /usr/local/bin/ffmpeg
COPY --from=ffmpeg-source /ffprobe /usr/local/bin/ffprobe
RUN chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe

# Cria o diretório de logs e garante permissão para o usuário node (uid 1000)
RUN mkdir -p /home/n8n/logs/dark_video_errors \
    && chown -R node:node /home/n8n

USER node
