# ECR Build & Push — Dry-run (backend YoutubeLiveApp)

## Contexto

- **App:** `dvn-workshop-apps/backend/YoutubeLiveApp`
- **Repositório ECR:** `devops-na-nuvem/prod/backend`
- **Região:** `us-east-1`
- **Profile AWS:** `workshop_julho`
- **Tag:** `rc-5`
- **Modo:** `--dry-run` (nenhum push real executado)

## Identidade AWS confirmada

```
{
    "UserId": "AIDAZQ3DTYI7LIVXPGC47",
    "Account": "654654554686",
    "Arn": "arn:aws:iam::654654554686:user/workshop.july.user"
}
```

- **Conta:** `654654554686`
- **Registry derivado:** `654654554686.dkr.ecr.us-east-1.amazonaws.com`

## Comando exato executado

```bash
cd /Users/kenerry/Repositories/dvn-workshop-julho && bash .claude/skills/ecr-build-push/scripts/ecr_build_push.sh \
  --tag rc-5 \
  --region us-east-1 \
  --profile workshop_julho \
  --app dvn-workshop-apps/backend/YoutubeLiveApp:devops-na-nuvem/prod/backend \
  --dry-run
```

## Saída do dry-run

```
==> Resolvendo identidade AWS (região=us-east-1, profile=workshop_julho)
    conta=654654554686  registry=654654554686.dkr.ecr.us-east-1.amazonaws.com
==> 1 app(s) para build & push (tag=rc-5, +latest)
==> Login no ECR (654654554686.dkr.ecr.us-east-1.amazonaws.com)
    [dry-run] aws ecr get-login-password | docker login --username AWS --password-stdin 654654554686.dkr.ecr.us-east-1.amazonaws.com
==> Buildando 1 app(s) em paralelo...

================= RESULTADO =================
----- devops-na-nuvem/prod/backend : OK ✅ -----
### app[0]: context=dvn-workshop-apps/backend/YoutubeLiveApp repo=devops-na-nuvem/prod/backend dockerfile=Dockerfile
[dry-run] docker buildx build --platform linux/amd64 -t 654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/backend:rc-5 -f /Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/backend/YoutubeLiveApp/Dockerfile --push /Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/backend/YoutubeLiveApp
OK (dry-run)

=============================================
RESULTADO GERAL: OK ✅  (todos os apps buildaram e deram push com tag 'rc-5')
```

## Detalhamento do plano

### 1. Login (uma única vez no registry)

```bash
aws ecr get-login-password | docker login --username AWS --password-stdin 654654554686.dkr.ecr.us-east-1.amazonaws.com
```

### 2. Build & push (buildx, um passo)

```bash
docker buildx build --platform linux/amd64 \
  -t 654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/backend:rc-5 \
  -f /Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/backend/YoutubeLiveApp/Dockerfile \
  --push \
  /Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/backend/YoutubeLiveApp
```

- **Plataforma:** `linux/amd64`
- **Push:** via `buildx --push` (build + push num passo só)

## URI da imagem

```
654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/backend:rc-5
```

## Observação

Nada foi publicado — execução em `--dry-run`. Para efetivar o push, basta remover
a flag `--dry-run` do comando acima.
