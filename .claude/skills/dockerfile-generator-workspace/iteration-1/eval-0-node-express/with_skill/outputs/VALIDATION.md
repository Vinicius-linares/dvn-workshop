# Validação do Dockerfile — node-express fixture

Validação executada com `scripts/validate_dockerfile.sh` da skill `dockerfile-generator`
(build + run + espera de HEALTHCHECK + curl externo).

## Perfil da aplicação

- Runtime: Node.js (Express `^4.19.2`), JS puro, **sem passo de build**.
- Gerenciador de pacotes: **npm** (presença de `package-lock.json`).
- Porta HTTP: **3000** (`app.listen`, `PORT` com default 3000).
- Endpoint de health: **`/health`** (já existente na app, retorna `{ status: 'ok' }` 200).

## Resultado

| Item                         | Resultado                                  |
|------------------------------|--------------------------------------------|
| Imagem buildou               | ✅ Sim                                     |
| Container subiu              | ✅ Sim (`fixture app listening on 3000`)   |
| Status do HEALTHCHECK        | ✅ `healthy`                               |
| Curl externo (`GET /health`) | ✅ `ok` (HTTP 200)                         |
| Tamanho final da imagem      | **234 MB** (base `node:22-alpine`)         |
| Veredito do script           | ✅ OK (`healthcheck=healthy, curl=ok`)     |

Comando utilizado:

```bash
scripts/validate_dockerfile.sh <outputs> 3000 /health
```

## Decisões de imagem (produção, enxuta e segura)

- **Multi-stage build**: estágio `deps` instala apenas dependências de produção
  (`npm ci --omit=dev`) e o estágio `runtime` recebe só `node_modules` + código.
  Nenhuma ferramenta de build/devDependency vai para a imagem final.
- **Base mínima**: `node:22-alpine`. App Express pura, sem dependências nativas
  que exijam glibc, então alpine é seguro (não foi necessário cair para `-slim`).
- **Rootless**: `USER node` (usuário unprivileged já presente na imagem oficial)
  definido antes do `CMD`. O container **não roda como root**.
- **Layer caching**: `package.json` + `package-lock.json` copiados e instalados
  antes do código-fonte.
- **PID 1 correto**: `CMD ["node", "server.js"]` (não `npm start`), para
  encaminhamento adequado de SIGTERM.
- **HEALTHCHECK real**: usa o `http` nativo do Node (alpine não traz curl/wget),
  batendo em `http://127.0.0.1:3000/health` e exigindo HTTP 200.
- **`.dockerignore`**: ignora `node_modules`, `.git`, `.env*`, `Dockerfile`, etc.,
  reduzindo o contexto de build e evitando vazamento de arquivos.
- **Sem segredos** embutidos na imagem.

## Observação sobre o tamanho

O `234 MB` é o tamanho reportado pelo BuildKit para o manifesto (inclui camadas
multi-arquitetura + attestation geradas no build local). O grosso do peso vem da
própria base `node:22-alpine`; a app e suas dependências de produção adicionam
pouco. Para reduzir ainda mais seria possível avaliar `node:22-alpine` +
`--platform` fixado a uma única arquitetura, ou uma base distroless de Node —
com trade-off de perder o shell e o HEALTHCHECK embutido.
