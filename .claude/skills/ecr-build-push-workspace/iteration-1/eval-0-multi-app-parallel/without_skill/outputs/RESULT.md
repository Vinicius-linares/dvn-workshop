# DRY-RUN — ECR login + build & push (backend .NET + frontend Next) em paralelo

> **NADA foi publicado.** Este documento apenas mostra exatamente o que rodaria.
> Confirme antes de eu executar de verdade.

## Parâmetros

| Item | Valor |
|---|---|
| Região | `us-east-1` |
| Perfil AWS | `workshop_julho` |
| Conta | `654654554686` |
| Registry (ECR) | `654654554686.dkr.ecr.us-east-1.amazonaws.com` |
| Tag | `v1.2.0` |
| Plataforma alvo | `linux/amd64` (host é arm64 → precisa de `--platform`, ver observação 3) |

## Apps (fonte: `dvn-workshop-apps/ecr-apps.json`)

| App | Context (build) | Dockerfile | Repositório ECR |
|---|---|---|---|
| backend (.NET 8) | `backend/YoutubeLiveApp` | `Dockerfile` | `devops-na-nuvem/prod/backend` |
| frontend (Next) | `frontend/youtube-live-app` | `Dockerfile` | `devops-na-nuvem/prod/frontend` |

> **Observação 1 (divergência):** o enunciado do ambiente cita **um** repositório
> `devops-na-nuvem/prod/application`, mas o `ecr-apps.json` (source of truth do repo)
> declara **dois** repositórios distintos: `.../backend` e `.../frontend`. Segui o JSON.
> Se o correto for um único repo `.../application`, dá pra diferenciar as duas imagens
> por tag (ex.: `application:backend-v1.2.0` e `application:frontend-v1.2.0`). **Confirme
> qual dos dois cenários usar antes do push real.**

## URIs de imagem resultantes

```
654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/backend:v1.2.0
654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/frontend:v1.2.0
```

---

## 1. Login no ECR (uma vez — vale para os dois repos do mesmo registry)

```bash
aws ecr get-login-password \
  --region us-east-1 \
  --profile workshop_julho \
| docker login \
    --username AWS \
    --password-stdin \
    654654554686.dkr.ecr.us-east-1.amazonaws.com
```

## 2. Build & push — em PARALELO

Todos os comandos abaixo rodam a partir de `dvn-workshop-apps/`.
Cada `docker build` já embute a tag final do ECR (`-t <uri>`), então o push é direto — sem `docker tag` extra.

### Opção A — paralelismo com `docker buildx bake` (recomendada)

Um único arquivo declara os dois targets; o `bake` builda ambos concorrentemente.
Com `--push`, buildx builda E envia numa passada só (multi-plataforma nativo).

`docker-bake.hcl`:

```hcl
variable "REGISTRY" { default = "654654554686.dkr.ecr.us-east-1.amazonaws.com" }
variable "TAG"      { default = "v1.2.0" }

group "default" {
  targets = ["backend", "frontend"]
}

target "backend" {
  context    = "backend/YoutubeLiveApp"
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64"]
  tags       = ["${REGISTRY}/devops-na-nuvem/prod/backend:${TAG}"]
}

target "frontend" {
  context    = "frontend/youtube-live-app"
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64"]
  tags       = ["${REGISTRY}/devops-na-nuvem/prod/frontend:${TAG}"]
}
```

Dry-run (só imprime o plano, não builda nada):

```bash
docker buildx bake --print
```

Execução real (buildar + push dos dois em paralelo) — **NÃO rodar agora**:

```bash
docker buildx bake --push
```

### Opção B — dois `docker build` em background + `wait` (sem arquivo extra)

```bash
REGISTRY=654654554686.dkr.ecr.us-east-1.amazonaws.com
TAG=v1.2.0

# backend
docker build --platform linux/amd64 \
  -t "$REGISTRY/devops-na-nuvem/prod/backend:$TAG" \
  -f backend/YoutubeLiveApp/Dockerfile \
  backend/YoutubeLiveApp &
PID_BACKEND=$!

# frontend
docker build --platform linux/amd64 \
  -t "$REGISTRY/devops-na-nuvem/prod/frontend:$TAG" \
  -f frontend/youtube-live-app/Dockerfile \
  frontend/youtube-live-app &
PID_FRONTEND=$!

# espera os dois builds; falha se qualquer um falhar
wait $PID_BACKEND && wait $PID_FRONTEND

# push em paralelo (só após ambos os builds concluírem com sucesso)
docker push "$REGISTRY/devops-na-nuvem/prod/backend:$TAG" &
docker push "$REGISTRY/devops-na-nuvem/prod/frontend:$TAG" &
wait
```

---

## 3. Observações importantes antes do push real

1. **Arquitetura:** o host é `arm64` (Apple Silicon) e o destino de execução na AWS
   normalmente é `amd64`. Por isso todos os builds usam `--platform linux/amd64`
   (ou `platforms = ["linux/amd64"]` no bake). Sem isso, a imagem sairia arm64 e
   poderia quebrar no runtime da nuvem. Ajuste se o alvo for arm64/Graviton.

2. **Repositórios precisam existir** no ECR antes do push (o push não cria repo).
   Checagem (read-only, seguro):
   ```bash
   aws ecr describe-repositories \
     --region us-east-1 --profile workshop_julho \
     --repository-names devops-na-nuvem/prod/backend devops-na-nuvem/prod/frontend
   ```

3. **Divergência de repositório** descrita na Observação 1 — confirmar 1 repo vs. 2 repos.

4. Ferramentas presentes no host: docker `27.3.1`, buildx `v0.18.0`, aws-cli `2.22.17`. OK.

## Resumo do que rodaria (na ordem)

1. `aws ecr get-login-password ... | docker login ...` (login no registry)
2. build + push em paralelo dos dois apps com tag `v1.2.0` (Opção A `buildx bake --push`, ou Opção B builds em background + `wait`)

**Status: DRY-RUN — nenhum comando de login/build/push foi executado.**
