# Guia de Deploy e Operação — n8n 2.83 + FFmpeg

## ESTRUTURA DO REPOSITÓRIO

```
repo-github/
├── Dockerfile
├── docker-compose.yml
└── COMANDOS.md          (este arquivo, opcional)
```

---

## 1. CRIAR REPOSITÓRIO E SUBIR OS ARQUIVOS

```bash
# Na sua máquina local, com os arquivos Dockerfile e docker-compose.yml na pasta:

git init
git add Dockerfile docker-compose.yml
git commit -m "feat: n8n 2.83 + FFmpeg com detecção de vídeo escuro"

# Crie o repositório no GitHub (pode ser privado):
#   https://github.com/new

git remote add origin https://github.com/SEU_USUARIO/SEU_REPO.git
git branch -M main
git push -u origin main
```

---

## 2. CRIAR A PASTA DE LOGS NO SERVIDOR (host)

Faça isso via SSH no servidor onde o Easypanel está rodando,
**antes** de criar o serviço no Easypanel:

```bash
# Conectar ao servidor
ssh usuario@ip-do-servidor

# Criar a pasta física que será montada como volume
sudo mkdir -p /opt/n8n/logs/dark_video_errors

# Dar permissão para o usuário node do container (uid 1000)
sudo chown -R 1000:1000 /opt/n8n/logs

# Confirmar
ls -la /opt/n8n/logs
```

> **Por que uid 1000?** O container n8n roda com o usuário `node` (uid 1000).
> Sem essa permissão, o Code node não consegue gravar os arquivos `.jsonl`.

---

## 3. CONFIGURAR NO EASYPANEL

1. No painel: **Create Project → Create Service → App**
2. Aba **Source**: conecte o GitHub e selecione seu repositório
3. Aba **Build**: certifique que o **Dockerfile** está selecionado como builder
4. Aba **Domains**: adicione seu domínio (ex: `n8n.seudominio.com`)
   - O Easypanel provisiona SSL automaticamente via Traefik
5. Aba **Environment** — adicione estas variáveis:

```
N8N_HOST                    = n8n.seudominio.com
WEBHOOK_URL                 = https://n8n.seudominio.com
N8N_ENCRYPTION_KEY          = (gere com: openssl rand -hex 32)
```

6. Aba **Mounts** (ou **Volumes**): verifique que o volume `n8n_data` foi criado.
   O bind de `/opt/n8n/logs` já está fixo no `docker-compose.yml`.

7. **Deploy** → aguarde o build (primeira vez demora ~3-5 min pelo FFmpeg)

---

## 4. VERIFICAR SE SUBIU CORRETAMENTE

Via terminal do Easypanel ou SSH:

```bash
# Status do container
docker ps | grep n8n

# Logs do container em tempo real
docker logs -f n8n

# Confirmar ffmpeg acessível dentro do container
docker exec n8n ffmpeg -version
docker exec n8n ffprobe -version

# Confirmar que a pasta de logs está montada
docker exec n8n ls -la /home/n8n/logs/
```

---

## 5. ATUALIZAR VERSÃO (REDEPLOY)

```bash
# Editar o Dockerfile localmente: trocar 2.83.0 pela nova versão
# Depois:
git add Dockerfile
git commit -m "chore: atualiza n8n para X.X.X"
git push

# O Easypanel detecta o push e faz redeploy automático
# (ou acione manualmente pelo painel: Deploy → Redeploy)
```

---

## 6. LOGS DE VÍDEO ESCURO

Arquivos `.jsonl` salvos em `/opt/n8n/logs/dark_video_errors/` no servidor.
Cada linha = 1 erro, com: `timestamp`, `act_id`, `scene_id`, `retry_count`,
`mean_luma`, `video_url`, `prompt`, `ffmpeg_output`, `ffmpeg_error`.

### Comandos no servidor (via SSH):

```bash
# Ver erros de hoje (raw)
cat /opt/n8n/logs/dark_video_errors/dark_videos_$(date +%Y-%m-%d).jsonl

# Ver formatado (requer jq — instale com: apt install jq)
cat /opt/n8n/logs/dark_video_errors/dark_videos_$(date +%Y-%m-%d).jsonl | jq .

# Resumo: timestamp | ato | cena | retry | luma
cat /opt/n8n/logs/dark_video_errors/*.jsonl | jq -r \
  '[.timestamp, "ato="+(.act_id|tostring), "cena="+(.scene_id|tostring),
    "retry="+(.retry_count|tostring), "luma="+(.mean_luma|tostring)] | join(" | ")'

# Só erros onde o FFmpeg falhou completamente (luma = -1)
cat /opt/n8n/logs/dark_video_errors/*.jsonl | jq 'select(.mean_luma == -1)'

# Contar erros por arquivo (por dia)
for f in /opt/n8n/logs/dark_video_errors/*.jsonl; do
  echo "$(basename $f): $(wc -l < $f) erros"
done

# Listar URLs únicas dos vídeos com problema (para o ticket)
cat /opt/n8n/logs/dark_video_errors/*.jsonl | jq -r '.video_url' | sort -u

# Exportar CSV para ticket de suporte
echo "timestamp,act_id,scene_id,retry_count,mean_luma,video_url,ffmpeg_error" \
  > /tmp/dark_videos_report.csv

cat /opt/n8n/logs/dark_video_errors/*.jsonl | jq -r \
  '[.timestamp,
    (.act_id|tostring),
    (.scene_id|tostring),
    (.retry_count|tostring),
    (.mean_luma|tostring),
    .video_url,
    (.ffmpeg_error // "")] | @csv' \
  >> /tmp/dark_videos_report.csv

cat /tmp/dark_videos_report.csv
```

---

## 7. BACKUP

```bash
# Backup dos dados do n8n (workflows, credenciais, SQLite)
# Substitua NOME_DO_VOLUME pelo nome real (verifique com: docker volume ls)
docker run --rm \
  -v NOME_DO_VOLUME:/source \
  -v /opt/n8n/backup:/backup \
  alpine tar czf /backup/n8n_data_$(date +%Y%m%d_%H%M).tar.gz -C /source .

# Backup dos logs de erro
tar czf /opt/n8n/backup/dark_logs_$(date +%Y%m%d).tar.gz \
  /opt/n8n/logs/dark_video_errors/

# Verificar backups
ls -lh /opt/n8n/backup/
```

---

## 8. TROUBLESHOOTING

### Container não sobe
```bash
docker logs n8n --tail=50
```

### Erro "permission denied" nos logs
```bash
# Corrigir permissão da pasta no servidor
sudo chown -R 1000:1000 /opt/n8n/logs
```

### Code node falha com "require is not defined" ou "cannot find module"
Confirme que as variáveis de ambiente estão definidas no Easypanel:
```
N8N_RUNNERS_ENABLED=true
NODE_FUNCTION_ALLOW_BUILTIN=fs,child_process,os,path,buffer
```

### FFmpeg não encontrado dentro do container
```bash
docker exec n8n which ffmpeg   # deve retornar /usr/local/bin/ffmpeg
# Se vazio, o build falhou — redeploy forçando rebuild sem cache no Easypanel
```

### Testar luma de um vídeo manualmente
```bash
# Substitua a URL por uma URL real gerada pela laozhang
docker exec n8n bash -c "
  wget -q -O /tmp/teste.mp4 'https://URL_DO_VIDEO.mp4' && \
  ffmpeg -hide_banner -i /tmp/teste.mp4 \
    -vf 'signalstats=stat=tout' -f null - 2>&1 \
  | grep YAVG | awk '{sum+=\$NF; n++} END {printf \"Luma media: %.2f\n\", sum/n}'
"
```
