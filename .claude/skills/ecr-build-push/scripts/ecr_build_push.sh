#!/usr/bin/env bash
#
# ecr_build_push.sh — login no ECR + build & push de uma ou mais imagens, em paralelo.
#
# Fluxo:
#   1. Resolve conta/região/registry (via aws sts + args/env).
#   2. Faz UM login no ECR (docker login) — vale para todos os repos daquele registry.
#   3. Descobre os apps a partir de um manifesto (ecr-apps.json) OU dos argumentos.
#   4. Builda e dá push de cada app EM PARALELO, cada um com seu log próprio.
#   5. Agrega resultados e retorna != 0 se qualquer app falhar.
#
# Uso:
#   ecr_build_push.sh --tag <tag> [opções]
#
# Opções:
#   --tag <tag>            Tag da imagem (obrigatório). Ex.: v1.2.3, um git sha, etc.
#   --region <region>     Região AWS (default: $AWS_REGION ou us-east-1).
#   --profile <profile>   Profile AWS (opcional; senão usa credencial do ambiente).
#   --manifest <arquivo>  JSON com a lista de apps (default: procura ecr-apps.json no cwd
#                         e na raiz do repo git). Ver formato abaixo.
#   --app <ctx>:<repo>    Define um app inline (pode repetir). <ctx> = diretório de build,
#                         <repo> = nome do repositório ECR. Se usado, ignora o manifesto.
#   --dockerfile <nome>   Nome do Dockerfile dentro do contexto (default: Dockerfile).
#   --also-latest         Além de <tag>, também empurra :latest.
#   --dry-run             Mostra o que faria (login/build/push) sem executar build/push.
#
# Formato do manifesto (ecr-apps.json):
#   {
#     "apps": [
#       { "context": "dvn-workshop-apps/backend/YoutubeLiveApp", "repository": "devops-na-nuvem/prod/backend" },
#       { "context": "dvn-workshop-apps/frontend/youtube-live-app", "repository": "devops-na-nuvem/prod/frontend", "dockerfile": "Dockerfile" }
#     ]
#   }
#   Caminhos de "context" são relativos à localização do manifesto.
#
set -uo pipefail

TAG=""
REGION="${AWS_REGION:-us-east-1}"
PROFILE=""
MANIFEST=""
DOCKERFILE_DEFAULT="Dockerfile"
ALSO_LATEST="false"
DRY_RUN="false"
declare -a INLINE_APPS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)        TAG="$2"; shift 2 ;;
    --region)     REGION="$2"; shift 2 ;;
    --profile)    PROFILE="$2"; shift 2 ;;
    --manifest)   MANIFEST="$2"; shift 2 ;;
    --app)        INLINE_APPS+=("$2"); shift 2 ;;
    --dockerfile) DOCKERFILE_DEFAULT="$2"; shift 2 ;;
    --also-latest) ALSO_LATEST="true"; shift ;;
    --dry-run)    DRY_RUN="true"; shift ;;
    *) echo "ERRO: opção desconhecida '$1'" >&2; exit 2 ;;
  esac
done

if [[ -z "$TAG" ]]; then
  echo "ERRO: --tag é obrigatório." >&2
  exit 2
fi

# aws com profile opcional
awsc() {
  if [[ -n "$PROFILE" ]]; then aws --profile "$PROFILE" "$@"; else aws "$@"; fi
}

for bin in aws docker jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERRO: '$bin' não encontrado no PATH." >&2
    exit 3
  fi
done
if ! docker info >/dev/null 2>&1; then
  echo "ERRO: daemon do Docker inacessível. Suba o Docker e tente de novo." >&2
  exit 3
fi

echo "==> Resolvendo identidade AWS (região=$REGION${PROFILE:+, profile=$PROFILE})"
ACCOUNT_ID="$(awsc sts get-caller-identity --query Account --output text 2>/dev/null)"
if [[ -z "$ACCOUNT_ID" || "$ACCOUNT_ID" == "None" ]]; then
  echo "ERRO: não foi possível obter a conta AWS. Verifique credenciais/profile." >&2
  exit 3
fi
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
echo "    conta=$ACCOUNT_ID  registry=$REGISTRY"

# --- Descobrir apps: inline > manifesto ---
declare -a APP_CTX=() APP_REPO=() APP_DF=()

if [[ ${#INLINE_APPS[@]} -gt 0 ]]; then
  BASE_DIR="$(pwd)"
  for spec in "${INLINE_APPS[@]}"; do
    ctx="${spec%%:*}"; repo="${spec#*:}"
    if [[ -z "$ctx" || -z "$repo" || "$ctx" == "$repo" ]]; then
      echo "ERRO: --app inválido '$spec' (esperado <ctx>:<repo>)." >&2; exit 2
    fi
    APP_CTX+=("$ctx"); APP_REPO+=("$repo"); APP_DF+=("$DOCKERFILE_DEFAULT")
  done
else
  # localizar manifesto
  if [[ -z "$MANIFEST" ]]; then
    if [[ -f "./ecr-apps.json" ]]; then
      MANIFEST="./ecr-apps.json"
    else
      gitroot="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      if [[ -n "$gitroot" && -f "$gitroot/ecr-apps.json" ]]; then MANIFEST="$gitroot/ecr-apps.json"; fi
    fi
  fi
  if [[ -z "$MANIFEST" || ! -f "$MANIFEST" ]]; then
    echo "ERRO: nenhum app informado. Use --app <ctx>:<repo> ou forneça um manifesto (ecr-apps.json)." >&2
    exit 2
  fi
  echo "==> Usando manifesto: $MANIFEST"
  BASE_DIR="$(cd "$(dirname "$MANIFEST")" && pwd)"
  count="$(jq '.apps | length' "$MANIFEST")"
  for i in $(seq 0 $((count-1))); do
    APP_CTX+=("$(jq -r ".apps[$i].context" "$MANIFEST")")
    APP_REPO+=("$(jq -r ".apps[$i].repository" "$MANIFEST")")
    df="$(jq -r ".apps[$i].dockerfile // \"$DOCKERFILE_DEFAULT\"" "$MANIFEST")"
    APP_DF+=("$df")
  done
fi

N=${#APP_CTX[@]}
if [[ $N -eq 0 ]]; then echo "ERRO: nenhum app resolvido." >&2; exit 2; fi
latest_note=""; [[ "$ALSO_LATEST" == "true" ]] && latest_note=", +latest"
echo "==> $N app(s) para build & push (tag=$TAG$latest_note)"

# --- Login ÚNICO no ECR (vale para o registry inteiro) ---
echo "==> Login no ECR ($REGISTRY)"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "    [dry-run] aws ecr get-login-password | docker login --username AWS --password-stdin $REGISTRY"
else
  if ! awsc ecr get-login-password --region "$REGION" \
        | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null 2>&1; then
    echo "ERRO: docker login no ECR falhou." >&2
    exit 1
  fi
  echo "    login OK"
fi

# --- Build & push de UM app (executado em background para paralelizar) ---
LOGDIR="$(mktemp -d -t ecr-build-push-XXXXXX)"
build_one() {
  local idx="$1" ctx_rel="$2" repo="$3" df="$4" logf="$5"
  local ctx="$BASE_DIR/$ctx_rel"
  {
    echo "### app[$idx]: context=$ctx_rel repo=$repo dockerfile=$df"
    if [[ ! -d "$ctx" ]]; then echo "FALHA: contexto '$ctx' não existe."; exit 1; fi
    if [[ ! -f "$ctx/$df" ]]; then echo "FALHA: Dockerfile '$ctx/$df' não existe."; exit 1; fi

    local image="$REGISTRY/$repo:$TAG"
    local -a tags=(-t "$image")
    [[ "$ALSO_LATEST" == "true" ]] && tags+=(-t "$REGISTRY/$repo:latest")

    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[dry-run] docker buildx build --platform linux/amd64 ${tags[*]} -f $ctx/$df --push $ctx"
      echo "OK (dry-run)"; exit 0
    fi
    # buildx --push builda e envia em um passo, sem load intermediário no daemon.
    # --provenance=false evita o índice de attestation multi-manifest que confunde alguns
    # consumidores (ex.: alguns scanners/ECR UI) — imagem final mais previsível.
    if docker buildx build \
          --platform linux/amd64 \
          "${tags[@]}" \
          -f "$ctx/$df" \
          --provenance=false \
          --push \
          "$ctx"; then
      echo "OK: push de $image concluído"
      exit 0
    else
      echo "FALHA: build/push de $image"
      exit 1
    fi
  } >"$logf" 2>&1
}

declare -a PIDS=() LOGS=() NAMES=()
for i in $(seq 0 $((N-1))); do
  logf="$LOGDIR/app-$i.log"
  LOGS+=("$logf"); NAMES+=("${APP_REPO[$i]}")
  build_one "$i" "${APP_CTX[$i]}" "${APP_REPO[$i]}" "${APP_DF[$i]}" "$logf" &
  PIDS+=("$!")
done

echo "==> Buildando ${N} app(s) em paralelo..."
FAIL=0
for i in $(seq 0 $((N-1))); do
  if ! wait "${PIDS[$i]}"; then FAIL=1; fi
done

echo
echo "================= RESULTADO ================="
for i in $(seq 0 $((N-1))); do
  status="OK ✅"
  if grep -q "FALHA" "${LOGS[$i]}"; then status="FALHA ❌"; fi
  echo "----- ${NAMES[$i]} : $status -----"
  tail -n 20 "${LOGS[$i]}"
  echo
done
echo "============================================="

rm -rf "$LOGDIR" 2>/dev/null || true

if [[ $FAIL -ne 0 ]]; then
  echo "RESULTADO GERAL: FALHA ❌ (ao menos um app não concluiu)"
  exit 1
fi
echo "RESULTADO GERAL: OK ✅  (todos os apps buildaram e deram push com tag '$TAG')"
exit 0
