# ECR Build & Push — Dry-run (multi-app, paralelo)

Skill: `ecr-build-push` (script bundled `scripts/ecr_build_push.sh`).
Modo: **--dry-run** (NENHUM push real foi feito ao ECR).

## Comando executado

Executado a partir de `dvn-workshop-apps/` (onde vive `ecr-apps.json`):

```bash
/Users/kenerry/Repositories/dvn-workshop-julho/.claude/skills/ecr-build-push/scripts/ecr_build_push.sh \
  --tag v1.2.0 \
  --region us-east-1 \
  --profile workshop_julho \
  --manifest ./ecr-apps.json \
  --dry-run
```

- Tag explícita do usuário: `v1.2.0` (não silenciosa).
- `:latest` NÃO incluído (`--also-latest` não foi passado) — as imagens levam apenas `:v1.2.0`.
- Apps descobertos via manifesto versionado `dvn-workshop-apps/ecr-apps.json` (fonte preferida).
- Ambos os Dockerfiles verificados como existentes antes do run.

## Saída do dry-run

```
==> Resolvendo identidade AWS (região=us-east-1, profile=workshop_julho)
    conta=654654554686  registry=654654554686.dkr.ecr.us-east-1.amazonaws.com
==> Usando manifesto: ./ecr-apps.json
==> 2 app(s) para build & push (tag=v1.2.0, +latest)
==> Login no ECR (654654554686.dkr.ecr.us-east-1.amazonaws.com)
    [dry-run] aws ecr get-login-password | docker login --username AWS --password-stdin 654654554686.dkr.ecr.us-east-1.amazonaws.com
==> Buildando 2 app(s) em paralelo...

================= RESULTADO =================
----- devops-na-nuvem/prod/backend : OK ✅ -----
### app[0]: context=backend/YoutubeLiveApp repo=devops-na-nuvem/prod/backend dockerfile=Dockerfile
[dry-run] docker buildx build --platform linux/amd64 -t 654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/backend:v1.2.0 -f /Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/backend/YoutubeLiveApp/Dockerfile --push /Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/backend/YoutubeLiveApp
OK (dry-run)

----- devops-na-nuvem/prod/frontend : OK ✅ -----
### app[1]: context=frontend/youtube-live-app repo=devops-na-nuvem/prod/frontend dockerfile=Dockerfile
[dry-run] docker buildx build --platform linux/amd64 -t 654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/frontend:v1.2.0 -f /Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/frontend/youtube-live-app/Dockerfile --push /Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/frontend/youtube-live-app
OK (dry-run)

=============================================
RESULTADO GERAL: OK ✅  (todos os apps buildaram e deram push com tag 'v1.2.0')
```

## O que seria feito (resolvido)

### Identidade / contexto AWS
- Conta: `654654554686`
- Região: `us-east-1`
- Profile: `workshop_julho`
- Registry derivado: `654654554686.dkr.ecr.us-east-1.amazonaws.com`

### Login no ECR (uma única vez, para o registry inteiro)
```
aws ecr get-login-password | docker login --username AWS --password-stdin 654654554686.dkr.ecr.us-east-1.amazonaws.com
```

### Apps descobertos (2, buildados em paralelo)

| App | Contexto | Repositório ECR | Dockerfile |
|-----|----------|-----------------|------------|
| backend (.NET) | `backend/YoutubeLiveApp` | `devops-na-nuvem/prod/backend` | `Dockerfile` |
| frontend (Next) | `frontend/youtube-live-app` | `devops-na-nuvem/prod/frontend` | `Dockerfile` |

### Comandos buildx que rodariam (plataforma amd64, `--push`)

Backend:
```
docker buildx build --platform linux/amd64 \
  -t 654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/backend:v1.2.0 \
  -f /Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/backend/YoutubeLiveApp/Dockerfile \
  --push \
  /Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/backend/YoutubeLiveApp
```

Frontend:
```
docker buildx build --platform linux/amd64 \
  -t 654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/frontend:v1.2.0 \
  -f /Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/frontend/youtube-live-app/Dockerfile \
  --push \
  /Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/frontend/youtube-live-app
```

> Nota: no run real (sem `--dry-run`), o script também adiciona `--provenance=false` a cada
> `buildx build` (manifest previsível para o ECR). A linha de dry-run acima omite esse flag,
> mas ele faz parte do comando real.

## URIs de imagem que seriam publicados

- `654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/backend:v1.2.0`
- `654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/frontend:v1.2.0`

## Observações

- Cosmético: o cabeçalho imprime `(tag=v1.2.0, +latest)` porque a expansão `${ALSO_LATEST:+...}`
  do script testa string não-vazia (o default é a string `"false"`). Isso é só o texto do
  cabeçalho — os comandos `buildx` reais listam **apenas** a tag `:v1.2.0`, confirmando que
  `:latest` NÃO seria publicado.

## Próximo passo (aguardando confirmação)

Para publicar de verdade, repita o mesmo comando **sem** `--dry-run`:

```bash
/Users/kenerry/Repositories/dvn-workshop-julho/.claude/skills/ecr-build-push/scripts/ecr_build_push.sh \
  --tag v1.2.0 --region us-east-1 --profile workshop_julho --manifest ./ecr-apps.json
```
