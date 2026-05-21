# Livestream Platform

YouTube-livestream opnieuw encoderen met instelbare bitrate, en via een eigen viewer-website bekijken. Bestaat uit twee onafhankelijke componenten:

| Component   | Image                                  | Wat doet 'ie                                  |
|-------------|----------------------------------------|-----------------------------------------------|
| `restreamer` | `ghcr.io/USER/REPO-restreamer`        | streamlink + ffmpeg, schrijft HLS naar volume |
| `viewer`    | `ghcr.io/USER/REPO-viewer`             | nginx + hls.js player, runtime-config via env |

Beide images zijn los te gebruiken. De viewer weet via `STREAM_URL` alleen waar 'ie HLS moet halen — verder is er geen koppeling. Schalen, vervangen, of beide in verschillende clusters: kan allemaal.

## Architectuur

```
                            ┌─ Pod: stream ──────────────────────┐
[YouTube] ──HLS──► restreamer ──emptyDir──► nginx-sidecar :80    │
                            └────────────────────▲───────────────┘
                                                 │ Service: stream
                                                 ▼ Ingress
                                    https://stream.example.com
                                                 ▲
                                                 │ browser laadt .m3u8 / .ts
                                                 │
                            ┌─ Pod: viewer ──────┴───────────────┐
                            │  nginx + hls.js (statisch)         │
                            └────────────────────▲───────────────┘
                                                 │ Service: viewer
                                                 ▼ Ingress
                                    https://kijk.example.com
```

## Repo-indeling

```
livestream-platform/
├── images/
│   ├── restreamer/        # Dockerfile + entrypoint
│   └── viewer/            # Dockerfile + nginx config + HTML
├── k8s/
│   ├── stream/            # restreamer + sidecar manifests
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   ├── viewer/            # viewer manifests
│   │   ├── deployment.yaml
│   │   └── kustomization.yaml
│   └── kustomization.yaml # bundelt beide
└── .github/workflows/
    └── publish.yml        # matrix build → GHCR
```

## Setup

### Eenmalig: images bouwen

Push de repo naar GitHub. De workflow bouwt beide images automatisch en pusht naar GHCR onder:

```
ghcr.io/USER/REPO-restreamer:latest
ghcr.io/USER/REPO-viewer:latest
```

Default zijn GHCR-packages privé. Maak ze publiek via Package settings → Change visibility, óf gebruik een `imagePullSecret` in je cluster.

### Vereisten in het cluster

- Een **Ingress controller** (Traefik, nginx-ingress, etc.)
- **cert-manager** met een werkende `ClusterIssuer` (in de manifests: `letsencrypt-prod`)
- DNS-records voor `stream.jouwdomein.nl` en `kijk.jouwdomein.nl`

### Aanpassen vóór deploy

Vervang in alle manifests:
- `JOUW_GEBRUIKERSNAAM` → je GitHub-gebruikersnaam (in image-namen)
- `jouwdomein.nl` → je echte domein
- `letsencrypt-prod` → naam van je ClusterIssuer
- `ingressClassName: traefik` → de naam van jouw Ingress controller class

### Deploy met kubectl + kustomize

```bash
# Beide componenten in één keer
kubectl apply -k k8s/

# Of afzonderlijk
kubectl apply -k k8s/stream/
kubectl apply -k k8s/viewer/
```

### Checken

```bash
kubectl get pods,svc,ingress
kubectl logs deploy/stream -c restreamer -f
curl -I https://stream.jouwdomein.nl/stream.m3u8   # verwacht: 200, application/vnd.apple.mpegurl
```

Open `https://kijk.jouwdomein.nl` in je browser.

## Per-environment configuratie (Kustomize overlays)

Maak overlays in plaats van de base-manifests te wijzigen:

```
k8s/
├── base/                  # de huidige inhoud van k8s/
└── overlays/
    ├── staging/
    │   └── kustomization.yaml
    └── production/
        └── kustomization.yaml
```

Voorbeeld `overlays/production/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: livestream-prod
resources:
  - ../../base
patches:
  - target: { kind: ConfigMap, name: stream-config }
    patch: |
      - op: replace
        path: /data/YOUTUBE_URL
        value: "https://www.youtube.com/watch?v=PRODUCTIE_ID"
      - op: replace
        path: /data/VIDEO_BITRATE
        value: "20000k"
  - target: { kind: ConfigMap, name: viewer-config }
    patch: |
      - op: replace
        path: /data/STREAM_URL
        value: "https://stream.example.com/stream.m3u8"
```

## Configuratie-opties

### restreamer env vars (via `stream-config` ConfigMap)

| Variabele            | Default        | Toelichting                                              |
|----------------------|----------------|----------------------------------------------------------|
| `YOUTUBE_URL`        | _(verplicht)_  | YouTube livestream URL                                   |
| `OUTPUT_URL`         | `/hls/stream.m3u8` | Output-pad (binnen container)                        |
| `OUTPUT_FORMAT`      | `hls`          | `hls` voor browser-streaming, `flv` voor RTMP push       |
| `VIDEO_BITRATE`      | `12000k`       | Doel video bitrate                                       |
| `AUDIO_BITRATE`      | `256k`         | Audio bitrate                                            |
| `PRESET`             | `veryfast`     | x264 preset                                              |
| `INPUT_QUALITY`      | `best`         | streamlink kwaliteit                                     |
| `HLS_SEGMENT_TIME`   | `4`            | Segmentduur (sec) — lager = lagere latency               |
| `HLS_LIST_SIZE`      | `6`            | Aantal segmenten in playlist                             |

### viewer env vars (via `viewer-config` ConfigMap)

| Variabele     | Default          | Toelichting                                  |
|---------------|------------------|----------------------------------------------|
| `STREAM_URL`  | _(verplicht)_    | Publieke HLS-endpoint (browser laadt 'm)     |
| `PAGE_TITLE`  | `Live Stream`    | Browser tab-titel                            |

## Schaal & resource-overwegingen

**Stream-component**: blijft 1 replica. Twee parallel encoderende ffmpeg-processen hebben geen meerwaarde. Voor failover: gebruik een PodDisruptionBudget of een externe RTMP-relay.

**Viewer-component**: stateless en cacht goed — schaal vrijuit naar 2-10 replicas. De echte bottleneck voor veel kijkers zit bij de HLS-server (stream-component). Voor honderden concurrent viewers: zet een CDN (Cloudflare, BunnyCDN, etc.) voor `stream.jouwdomein.nl` en de cluster wordt nooit zwaar belast.

**Geheugen voor HLS-data**: emptyDir met `medium: Memory` (tmpfs) is gekozen omdat HLS-bestanden tijdelijk zijn. 512Mi is ruim voldoende voor het glijdende venster.

## Troubleshooting

**Pod `stream` blijft restarten**: check `kubectl logs deploy/stream -c restreamer` — meestal een onbereikbare YouTube URL of een livestream die nog niet bezig is.

**Viewer toont "offline"**: open dev tools → Network. Als de browser de `.m3u8` niet kan laden, controleer dat de stream-Ingress live is (`curl -I` op de URL) en dat CORS-headers verschijnen.

**Cert wordt niet uitgegeven**: `kubectl describe certificate stream-tls` — DNS moet bestaan en wijzen naar de Ingress controller's externe IP.

**Hoge CPU op restreamer**: gebruik een tragere preset (`fast` of `medium`) niet, maar juist `superfast` of `ultrafast`. Of beperk input quality (`INPUT_QUALITY: 720p`) zodat er minder pixels te transcoderen zijn.
