# Referência: Node.js

## Armadilhas específicas

- **Usuário `node` já existe** nas imagens oficiais `node:*` — não precisa criar um usuário do zero,
  basta `USER node`. Ele é unprivileged. Isso é mais simples e menos propenso a erro do que
  `adduser` manual.
- **Alpine usa musl, não glibc.** A maioria das apps Node puras roda bem em alpine. Mas se houver
  dependência nativa que compila contra glibc (algumas libs de imagem, `sharp` em certas versões,
  drivers específicos), o alpine pode quebrar em runtime de forma sutil. Nesse caso, prefira
  `node:22-slim` (Debian slim) — ainda enxuto, com glibc.
- **Não rode `npm` como PID 1.** `npm start` cria um processo filho e atrapalha o encaminhamento
  de sinais (SIGTERM), o que faz o container demorar para parar. Prefira `CMD ["node", "dist/app.js"]`
  diretamente. Se precisar de init para reaping de zumbis, use a flag `--init` do Docker.
- **Instale só deps de produção no estágio final.** Use `npm ci --omit=dev` (npm), `pnpm install
  --prod --frozen-lockfile`, ou `yarn install --production --frozen-lockfile`. `npm ci` é mais
  determinístico que `npm install` porque respeita o lockfile.
- **Copie o lockfile junto** do `package.json` para o cache funcionar e o `ci` ter o que travar.

## Detecção de gerenciador de pacotes

- `package-lock.json` → **npm** → `npm ci` / `npm ci --omit=dev`
- `pnpm-lock.yaml` → **pnpm** → habilite via `corepack enable`
- `yarn.lock` → **yarn** → `yarn install --frozen-lockfile`

## Detecção de build

Se `package.json` tem um script `build` (ex.: TypeScript, Next, Nest), há um passo de compilação:
instale **todas** as deps no estágio de build, rode `npm run build`, e no estágio final copie só o
artefato (`dist/`, `.next/`, `build/`) + as deps de produção. Se não há `build`, a app roda o
código-fonte JS direto.

## Template — app com build (TypeScript etc.), HTTP na porta 3000

```dockerfile
# ---- build ----
FROM node:22-alpine AS build
WORKDIR /app

# deps primeiro, para cache
COPY package.json package-lock.json ./
RUN npm ci

# código e build
COPY . .
RUN npm run build

# remove devDependencies para reaproveitar node_modules no estágio final
RUN npm prune --omit=dev

# ---- runtime ----
FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

# artefatos + deps de produção, com dono correto
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist
COPY --from=build --chown=node:node /app/package.json ./package.json

USER node
EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:3000/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "dist/app.js"]
```

## Template — app sem build (JS puro), HTTP na porta 3000

```dockerfile
FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --chown=node:node . .

USER node
EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:3000/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "server.js"]
```

## Notas sobre o HEALTHCHECK

- O comando de health usa **`node -e` com o http nativo** em vez de `curl`, porque a imagem
  `node:alpine` não traz `curl`/`wget` por padrão e assim você evita instalar pacote só para isso.
- Se a app não tem endpoint HTTP (worker/consumidor de fila), ver `healthcheck.md` para alternativas
  baseadas em processo.
- Ajuste porta e rota (`/health`, `/healthz`, etc.) ao que a app realmente expõe. Não invente uma
  rota que não existe — se não houver endpoint de health, adicione um trivial ou use check de processo.
