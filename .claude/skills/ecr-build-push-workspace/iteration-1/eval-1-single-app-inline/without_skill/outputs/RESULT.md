# ECR Build & Push — Dry-Run Plan (NÃO EXECUTADO)

> Este documento é apenas o **plano**. Nenhum build, login ou push real foi
> executado. Nada foi enviado ao ECR.

## Parâmetros

| Item | Valor |
|------|-------|
| App | `dvn-workshop-apps/backend/YoutubeLiveApp` (ASP.NET Core net8.0) |
| Build context | `dvn-workshop-apps/backend/YoutubeLiveApp` |
| Dockerfile | `./Dockerfile` (multi-stage, runtime aspnet:8.0, usuário não-root `app`, HEALTHCHECK em `/backend/health`, porta 8080) |
| Repositório ECR | `devops-na-nuvem/prod/backend` |
| Região | `us-east-1` |
| AWS profile | `workshop_julho` |
| Conta AWS | `654654554686` |
| Tag | `rc-5` |
| Registry | `654654554686.dkr.ecr.us-east-1.amazonaws.com` |
| **URI da imagem** | `654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/backend:rc-5` |

## Variáveis (para facilitar o copy/paste)

```bash
ACCOUNT_ID=654654554686
REGION=us-east-1
PROFILE=workshop_julho
REPO=devops-na-nuvem/prod/backend
TAG=rc-5
REGISTRY=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
IMAGE_URI=${REGISTRY}/${REPO}:${TAG}
APP_DIR=/Users/kenerry/Repositories/dvn-workshop-julho/dvn-workshop-apps/backend/YoutubeLiveApp
```

## Comandos que seriam usados

### 0. (Pré-requisito, opcional) Garantir que o repositório ECR existe

O `docker push` NÃO cria o repositório automaticamente. Se ainda não existir:

```bash
aws ecr describe-repositories \
  --repository-names "${REPO}" \
  --region "${REGION}" \
  --profile "${PROFILE}" \
  || aws ecr create-repository \
       --repository-name "${REPO}" \
       --image-scanning-configuration scanOnPush=true \
       --region "${REGION}" \
       --profile "${PROFILE}"
```

### 1. Login no ECR

```bash
aws ecr get-login-password \
  --region "${REGION}" \
  --profile "${PROFILE}" \
| docker login \
    --username AWS \
    --password-stdin "${REGISTRY}"
```

### 2. Build da imagem

```bash
docker build \
  -t "${IMAGE_URI}" \
  -f "${APP_DIR}/Dockerfile" \
  "${APP_DIR}"
```

> Observação sobre arquitetura: o host é `darwin/x86_64`. Se o destino de execução
> (ex.: ECS/EKS) for `linux/amd64`, o build acima já produz `amd64`. Caso o host
> fosse Apple Silicon (arm64), seria necessário `docker buildx build --platform linux/amd64 --load ...`
> para garantir compatibilidade. Aqui o host já é amd64, então não é obrigatório.

### 3. Push para o ECR

```bash
docker push "${IMAGE_URI}"
```

### 4. (Verificação, opcional) Confirmar a tag publicada

```bash
aws ecr describe-images \
  --repository-name "${REPO}" \
  --image-ids imageTag="${TAG}" \
  --region "${REGION}" \
  --profile "${PROFILE}"
```

## Resumo

- **Tag:** `rc-5`
- **URI final da imagem:** `654654554686.dkr.ecr.us-east-1.amazonaws.com/devops-na-nuvem/prod/backend:rc-5`
- **Status:** dry-run — nenhum comando foi executado; nada foi publicado.
</content>
</invoke>
