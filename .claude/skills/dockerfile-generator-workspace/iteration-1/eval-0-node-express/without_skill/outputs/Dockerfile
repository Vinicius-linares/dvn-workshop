# syntax=docker/dockerfile:1

# JS puro (sem passo de build), Express HTTP na porta 3000, endpoint /health existente.
FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

# Deps primeiro (cache de layer). npm ci é determinístico e respeita o lockfile.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Código-fonte com dono correto para o usuário unprivileged.
COPY --chown=node:node . .

# Usuário 'node' já existe na imagem oficial e é unprivileged — nunca rodar como root.
USER node
EXPOSE 3000

# Healthcheck real: exercita o endpoint HTTP /health via runtime nativo do Node
# (node:alpine não traz curl/wget).
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:3000/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

# node direto como PID 1 (não 'npm start') para encaminhamento correto de SIGTERM.
CMD ["node", "server.js"]
