# syntax=docker/dockerfile:1

# ---- deps ----
# Estágio dedicado para instalar apenas as dependências de produção.
FROM node:22-alpine AS deps
WORKDIR /app

# Copia primeiro os manifestos para aproveitar o cache de layer:
# alterar o código-fonte não invalida a instalação de dependências.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# ---- runtime ----
FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

# node_modules (só produção) vindo do estágio de deps, com dono correto
COPY --from=deps --chown=node:node /app/node_modules ./node_modules

# código da aplicação
COPY --chown=node:node package.json server.js ./

# usuário unprivileged já presente na imagem oficial node
USER node
EXPOSE 3000

# Healthcheck via http nativo do Node (imagem alpine não traz curl/wget).
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:3000/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

# node direto como PID 1 (não npm) para encaminhamento correto de sinais.
CMD ["node", "server.js"]
