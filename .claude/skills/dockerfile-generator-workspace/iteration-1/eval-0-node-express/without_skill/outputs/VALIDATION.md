# Validação — Dockerfile (Node/Express)

## App
- Runtime: Node.js + Express (`express@^4.19.2`)
- Sem passo de build (JS puro) — roda `server.js` direto
- Gerenciador de pacotes: **npm** (`package-lock.json` presente) → `npm ci`
- HTTP na porta **3000**, endpoint de health **`/health`** já existente (retorna 200 `{status:"ok"}`)

## Decisões do Dockerfile
- **Base mínima:** `node:22-alpine` — Express é JS puro, sem dependência nativa que exija glibc, então alpine é seguro.
- **Rootless:** usa o usuário `node` (já existe na imagem oficial, unprivileged) via `USER node` antes do `CMD`. Não roda como root.
- **Layer caching:** copia `package.json` + `package-lock.json` e roda `npm ci --omit=dev` antes de copiar o código-fonte.
- **Só deps de produção:** `npm ci --omit=dev` + `npm cache clean --force`.
- **PID 1 correto:** `CMD ["node", "server.js"]` (não `npm start`) para encaminhamento de SIGTERM.
- **Healthcheck real:** exercita `GET /health` via `http` nativo do Node (alpine não traz curl/wget).
- **`.dockerignore`:** exclui `node_modules`, `.git`, `.env*`, `*.md`, `Dockerfile`, `.DS_Store`, etc.
- **Sem segredos** embutidos na imagem.

> Nota: não foi criado nenhum endpoint de health — a app já expunha `/health`. Single-stage foi
> suficiente porque não há passo de build (nada de SDK/toolchain para descartar).

## Resultado da validação (build + run + healthcheck)

Executado via `scripts/validate_dockerfile.sh <ctx> 3000 /health`:

| Etapa | Resultado |
|-------|-----------|
| `docker build` | OK |
| Container sobe | OK (`fixture app listening on 3000`) |
| `HEALTHCHECK` do Docker | **healthy** |
| `curl` externo em `/health` (host → porta publicada) | **ok** (HTTP 200) |
| Roda como não-root | Sim (`USER node`) |
| Tamanho final da imagem | **237 MB** |

`npm ci` reportou **0 vulnerabilidades**.

**Veredito: OK** — imagem builda, container sobe, healthcheck fica `healthy` e o endpoint responde.

## Como reproduzir
```bash
docker build -t node-express-fixture .
docker run -d -p 3000:3000 --name app node-express-fixture
docker inspect --format '{{.State.Health.Status}}' app   # -> healthy
curl -fsS http://127.0.0.1:3000/health                     # -> {"status":"ok"}
```
