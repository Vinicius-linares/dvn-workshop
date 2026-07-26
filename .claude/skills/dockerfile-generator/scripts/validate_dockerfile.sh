#!/usr/bin/env bash
#
# validate_dockerfile.sh — builda, sobe e valida um Dockerfile de verdade.
#
# Faz: docker build -> docker run -> aguarda HEALTHCHECK ficar "healthy" ->
# (se HTTP) curl na rota de health a partir do host -> limpa tudo.
#
# Uso:
#   scripts/validate_dockerfile.sh <contexto> [porta] [rota_health] [dockerfile]
#
#   <contexto>     Caminho do diretório de build (onde está o Dockerfile). Obrigatório.
#   [porta]        Porta HTTP que a app expõe dentro do container (ex.: 3000, 8080).
#                  Se omitida, valida só via status do HEALTHCHECK (sem curl externo).
#   [rota_health]  Rota HTTP de health (default: /health). Só usada se [porta] for dada.
#   [dockerfile]   Caminho do Dockerfile (default: <contexto>/Dockerfile).
#
# Saída: 0 se a imagem builda, o container sobe e fica healthy (e o curl passa, se aplicável).
#        != 0 caso contrário, com logs do container impressos para diagnóstico.
#
set -uo pipefail

CONTEXT="${1:-}"
PORT="${2:-}"
HEALTH_PATH="${3:-/health}"
DOCKERFILE="${4:-}"

if [[ -z "$CONTEXT" ]]; then
  echo "ERRO: informe o diretório de contexto de build." >&2
  echo "uso: $0 <contexto> [porta] [rota_health] [dockerfile]" >&2
  exit 2
fi
if [[ ! -d "$CONTEXT" ]]; then
  echo "ERRO: contexto '$CONTEXT' não é um diretório." >&2
  exit 2
fi
if [[ -z "$DOCKERFILE" ]]; then
  DOCKERFILE="$CONTEXT/Dockerfile"
fi
if [[ ! -f "$DOCKERFILE" ]]; then
  echo "ERRO: Dockerfile não encontrado em '$DOCKERFILE'." >&2
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERRO: docker não está instalado/no PATH. Não é possível validar em runtime." >&2
  exit 3
fi
if ! docker info >/dev/null 2>&1; then
  echo "ERRO: o daemon do Docker não está acessível. Suba o Docker e tente de novo." >&2
  exit 3
fi

# Tags/nomes únicos e determinísticos por PID para não colidir nem depender de random.
TAG="dockerfile-validate:$$"
NAME="dockerfile-validate-$$"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker rmi -f "$TAG" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> [1/4] Build da imagem ($TAG)"
if ! docker build -f "$DOCKERFILE" -t "$TAG" "$CONTEXT"; then
  echo "FALHA: docker build falhou. Corrija o Dockerfile e rode de novo." >&2
  exit 1
fi

echo "==> [2/4] Subindo o container ($NAME)"
RUN_ARGS=(-d --name "$NAME")
if [[ -n "$PORT" ]]; then
  # publica em porta efêmera do host para o curl externo
  RUN_ARGS+=(-p "127.0.0.1:0:$PORT")
fi
if ! docker run "${RUN_ARGS[@]}" "$TAG"; then
  echo "FALHA: docker run falhou." >&2
  exit 1
fi

# Descobre a porta publicada no host (se houver)
HOST_PORT=""
if [[ -n "$PORT" ]]; then
  HOST_PORT="$(docker port "$NAME" "$PORT/tcp" 2>/dev/null | head -1 | sed 's/.*://')"
fi

echo "==> [3/4] Aguardando o HEALTHCHECK ficar 'healthy' (até 90s)"
HAS_HC="$(docker inspect --format '{{if .Config.Healthcheck}}yes{{else}}no{{end}}' "$NAME" 2>/dev/null)"

deadline=$(( $(date +%s) + 90 ))
final_state=""
if [[ "$HAS_HC" == "yes" ]]; then
  while [[ $(date +%s) -lt $deadline ]]; do
    state="$(docker inspect --format '{{.State.Health.Status}}' "$NAME" 2>/dev/null || echo unknown)"
    running="$(docker inspect --format '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)"
    if [[ "$running" != "true" ]]; then
      echo "FALHA: o container parou antes de ficar healthy." >&2
      final_state="exited"
      break
    fi
    if [[ "$state" == "healthy" ]]; then
      final_state="healthy"
      break
    fi
    if [[ "$state" == "unhealthy" ]]; then
      final_state="unhealthy"
      break
    fi
    sleep 3
  done
  [[ -z "$final_state" ]] && final_state="timeout"
  echo "    status do healthcheck: $final_state"
else
  echo "    (imagem não define HEALTHCHECK — pulando espera; verifique se isso é intencional)"
  # Sem healthcheck, ao menos confirme que o container continua de pé após alguns segundos
  sleep 5
  running="$(docker inspect --format '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)"
  if [[ "$running" == "true" ]]; then final_state="running-no-hc"; else final_state="exited"; fi
fi

echo "==> [4/4] Checagem HTTP externa (curl)"
curl_ok="skip"
if [[ -n "$PORT" && -n "$HOST_PORT" ]]; then
  if command -v curl >/dev/null 2>&1; then
    url="http://127.0.0.1:${HOST_PORT}${HEALTH_PATH}"
    echo "    GET $url"
    if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
      curl_ok="ok"
    else
      curl_ok="fail"
    fi
    echo "    curl: $curl_ok"
  else
    echo "    (curl não disponível no host — pulando checagem externa)"
    curl_ok="no-curl"
  fi
else
  echo "    (sem porta informada — pulando checagem externa)"
fi

echo
echo "----- docker images (tamanho da imagem) -----"
docker images "$TAG" --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}'
echo
echo "----- últimos logs do container -----"
docker logs --tail 40 "$NAME" 2>&1 || true
echo "---------------------------------------------"

# Veredito
echo
if [[ "$final_state" == "healthy" && ( "$curl_ok" == "ok" || "$curl_ok" == "skip" || "$curl_ok" == "no-curl" ) ]]; then
  echo "RESULTADO: OK ✅  (healthcheck=healthy, curl=$curl_ok)"
  exit 0
elif [[ "$final_state" == "running-no-hc" && "$curl_ok" == "ok" ]]; then
  echo "RESULTADO: OK ✅  (sem HEALTHCHECK, mas curl externo passou — considere adicionar HEALTHCHECK)"
  exit 0
else
  echo "RESULTADO: FALHA ❌  (healthcheck=$final_state, curl=$curl_ok)"
  echo "Analise os logs acima, ajuste o Dockerfile (porta, usuário, start-period, rota de health) e rode de novo." >&2
  exit 1
fi
