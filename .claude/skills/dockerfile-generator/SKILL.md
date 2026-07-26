---
name: dockerfile-generator
description: >-
  Gera Dockerfiles production-ready, otimizados e seguros, analisando a linguagem/runtime
  da aplicação. Aplica multi-stage build, imagens mínimas (alpine/slim), execução rootless
  (usuário unprivileged), HEALTHCHECK apropriado e valida de verdade — faz build, sobe o
  container e testa o healthcheck. Use esta skill sempre que o usuário quiser "dockerizar",
  "conteinerizar" ou "criar/melhorar um Dockerfile" para uma app, ou mencionar container,
  imagem Docker, multi-stage, imagem menor/mais leve, rodar container como não-root/rootless,
  hardening de imagem, ou healthcheck de container — mesmo que não diga "Dockerfile"
  explicitamente. Cobre bem Node.js e .NET; use o mesmo processo para outras linguagens
  adaptando a referência mais próxima.
---

# Dockerfile Generator

Gera um Dockerfile **production-ready** para a aplicação atual e o **valida de verdade**:
builda a imagem, sobe o container e confirma que o `HEALTHCHECK` fica `healthy`. Um Dockerfile
que "parece certo" mas não sobe não vale nada — por isso a validação é parte da skill, não um
extra opcional.

## Princípios (o porquê)

Estes princípios guiam todas as decisões. Quando uma referência de linguagem não cobrir um
caso, volte aqui e raciocine a partir deles.

- **Multi-stage build** — separe o estágio de build (com SDK, compiladores, devDependencies)
  do estágio final (só o runtime + artefato). A imagem que vai para produção não deve carregar
  ferramenta de build nenhuma. Isso reduz tamanho e superfície de ataque ao mesmo tempo.
- **Imagem base mínima** — prefira `alpine` ou `-slim`/`-distroless` para o estágio final.
  Menos pacotes = menos CVEs e menos peso. Cuidado com alpine quando há dependências que
  precisam de glibc (ver referências).
- **Rootless / unprivileged** — o container **nunca** deve rodar como root em produção. Crie um
  usuário sem privilégios e use `USER` antes do `CMD`/`ENTRYPOINT`. Se um processo comprometido
  estiver rodando como root dentro do container, o raio de impacto é muito maior. Rootless é a
  linha de base, não um luxo.
- **HEALTHCHECK real** — o Docker precisa saber se a app está viva. Configure um `HEALTHCHECK`
  que exercite o caminho real da aplicação (um endpoint HTTP quando existir), não só "o processo
  está no ar".
- **Layer caching** — copie primeiro os manifestos de dependência (`package.json`, `*.csproj`)
  e instale as deps **antes** de copiar o código-fonte. Assim, mudar uma linha de código não
  invalida o cache de instalação de dependências. Builds ficam muito mais rápidos.
- **Sem segredos na imagem** — nunca embuta tokens, `.env` com segredos, chaves. Use build args
  efêmeros ou secrets do BuildKit se precisar de credencial em build-time.
- **`.dockerignore`** — sempre gere/atualize um `.dockerignore` para não mandar `node_modules`,
  `bin/`, `obj/`, `.git`, etc. para o contexto de build. Contexto menor = build mais rápido e
  menos risco de vazar arquivo indevido.

## Fluxo de trabalho

### 1. Detectar a linguagem e o perfil da app

Investigue o repositório para descobrir o runtime e como a app roda. Sinais úteis:

- **Node.js** → `package.json`. Veja `scripts` (`start`, `build`), o gerenciador de pacotes
  (presença de `package-lock.json` → npm, `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn), e se há
  passo de build (TypeScript, bundler, framework como Next/Nest).
- **.NET** → `*.csproj` / `*.sln` / `global.json`. Veja o `TargetFramework` (ex.: `net8.0`), se é
  web (ASP.NET Core) ou console/worker, e o nome do assembly de saída.
- Outra linguagem? Use a referência mais próxima como molde e aplique os princípios acima.

Determine também o **perfil de health**: a app expõe HTTP (tem porta/endpoint)? Procure por
`/health`, `/healthz`, `/actuator/health`, configuração de porta, `app.listen`, `EXPOSE`,
`ASPNETCORE_URLS`. Se for um worker/CLI sem HTTP, o healthcheck será baseado em processo/comando.

### 2. Ler a referência da linguagem

Leia o arquivo de referência correspondente **antes** de escrever o Dockerfile — cada runtime tem
armadilhas específicas (usuário não-root pré-existente, glibc vs musl, porta padrão, etc.):

- Node.js → `references/nodejs.md`
- .NET → `references/dotnet.md`
- Detecção de healthcheck (todas as linguagens) → `references/healthcheck.md`

### 3. Escrever o Dockerfile + `.dockerignore`

Gere o `Dockerfile` na raiz da app (ou onde o usuário indicar) seguindo a referência e os
princípios. Sempre gere/atualize também o `.dockerignore`. Não deixe valores sensíveis hard-coded.

### 4. Validar de verdade (build + run + healthcheck)

Esta etapa é o coração da skill. Use o script bundled, que faz todo o ciclo e limpa depois:

```bash
scripts/validate_dockerfile.sh <caminho-do-contexto> [porta] [rota-health]
```

O script: builda a imagem, sobe o container, aguarda o `HEALTHCHECK` reportar `healthy`
(fazendo polling em `docker inspect`), e, se houver HTTP, também faz um `curl` direto na rota de
health para confirmar de fora. Ao final, derruba e remove o container e reporta sucesso/falha.

Leia `scripts/validate_dockerfile.sh` para os parâmetros exatos. Se a validação falhar:
- **Não** entregue o Dockerfile como pronto. Leia os logs (`docker logs`) que o script imprime,
  entenda a causa (porta errada, usuário sem permissão de escrita, binário não encontrado,
  healthcheck com timing curto demais) e **corrija o Dockerfile**, então rode a validação de novo.
- Itere até ficar `healthy`. Um Dockerfile que não passou na validação não está pronto.

Se o Docker não estiver disponível no ambiente, diga isso claramente ao usuário e entregue o
Dockerfile marcando que a validação de runtime não pôde ser executada — não finja que validou.

### 5. Reportar

Ao final, mostre ao usuário: o Dockerfile gerado, o `.dockerignore`, o resultado da validação
(imagem buildou, container subiu, healthcheck `healthy`, curl OK) e o **tamanho final da imagem**
(`docker images`), já que tamanho é um dos objetivos. Aponte qualquer trade-off que você fez
(ex.: usou `-slim` em vez de alpine por causa de dependência nativa).

## Checklist de qualidade

Antes de considerar o Dockerfile pronto, confirme:

- [ ] Multi-stage: estágio final não contém SDK/ferramenta de build
- [ ] Base mínima (alpine/slim/distroless) apropriada ao runtime
- [ ] `USER` não-root definido antes do `CMD`/`ENTRYPOINT`
- [ ] Dependências instaladas antes de copiar o código (cache de layer)
- [ ] `HEALTHCHECK` presente e coerente com o perfil da app
- [ ] `.dockerignore` cobre `node_modules`, `bin/`, `obj/`, `.git`, `.env`
- [ ] Nenhum segredo embutido na imagem
- [ ] Validação build+run+healthcheck passou (ou foi explicitamente reportado que Docker faltou)
