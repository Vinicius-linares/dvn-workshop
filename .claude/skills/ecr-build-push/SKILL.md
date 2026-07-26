---
name: ecr-build-push
description: >-
  Faz login no Amazon ECR e builda + dá push de imagens Docker para repositórios ECR, com
  suporte a MÚLTIPLAS aplicações em PARALELO. Resolve conta/região/registry automaticamente,
  autentica uma única vez e envia cada app com sua tag. Use esta skill sempre que o usuário
  quiser "buildar e subir/enviar imagem para o ECR", "fazer push para o ECR", "publicar a
  imagem no registry da AWS", "login no ECR", "subir backend e frontend para o ECR", ou
  qualquer variação de construir e publicar imagens de container no Amazon Elastic Container
  Registry — mesmo que não diga "ECR" com todas as letras, mas fique claro que o registry é
  da AWS. Assume que os repositórios ECR já existem (não os cria). Tag vem por argumento.
---

# ECR Build & Push

Autentica no Amazon ECR e faz **build + push** de uma ou mais imagens Docker, em **paralelo**.
O objetivo é sair de "tenho Dockerfiles" para "imagens publicadas no ECR" com um único comando,
sem repetir login nem serializar builds que poderiam rodar juntos.

## Premissas desta skill

- **Os repositórios ECR já existem.** Esta skill não cria repositório. Se o repo não existir, o
  push falha e o erro da AWS é reportado — nesse caso, oriente o usuário a criar o repo (ou peça
  confirmação antes de criar com `aws ecr create-repository`).
- **A tag vem do usuário** (argumento `--tag`). Não invente uma tag silenciosamente; se o usuário
  não deu uma, pergunte ou proponha uma explícita (ex.: o git sha curto) e confirme.
- **Credenciais AWS** vêm do ambiente ou de um profile (`--profile`). Confirme a identidade antes
  de empurrar para não publicar na conta errada.

## O porquê das decisões

- **Um login serve o registry inteiro.** O token do ECR (`get-login-password`) autentica no
  `<conta>.dkr.ecr.<região>.amazonaws.com` como um todo — não por repositório. Por isso a skill
  faz login **uma vez** e reaproveita para todos os apps. Repetir login por app é desperdício.
- **`buildx build --push` em vez de `build` + `push` separados.** O buildx builda e envia num só
  passo, sem materializar a imagem no daemon local — mais rápido e com menos I/O. E como cada
  invocação é independente, dá para rodar **vários em paralelo** de verdade.
- **Paralelismo com processos em background + `wait`.** Cada app builda no seu próprio processo,
  com log isolado; no fim agregamos os resultados. Assim o tempo total é o do app mais lento, não
  a soma de todos. Builds de apps diferentes não compartilham estado, então paralelizar é seguro.
- **Tag imutável (recomende git sha).** Uma tag que aponta sempre para o mesmo conteúdo permite
  rollback confiável e rastreabilidade (qual commit está em produção?). `:latest` é conveniente
  mas ambíguo — ofereça-o como adicional (`--also-latest`), não como única tag.
- **`--platform linux/amd64`.** A maioria dos clusters (EKS, ECS) roda amd64. Buildar num Mac
  ARM sem fixar a plataforma gera uma imagem arm64 que não roda no cluster — um erro comum e
  difícil de diagnosticar. Fixe a plataforma-alvo explicitamente.

## Fluxo de trabalho

### 1. Confirmar contexto AWS e identidade

Antes de empurrar qualquer coisa, saiba **para qual conta/região** vai. Rode
`aws sts get-caller-identity` (com o profile certo) e confirme a conta com o usuário se houver
qualquer dúvida. Push para o ECR é uma ação de saída (publica artefato) — vale confirmar.

O registry é sempre `<account_id>.dkr.ecr.<region>.amazonaws.com`. A skill deriva isso sozinha.

### 2. Descobrir os apps (o que buildar e para qual repo)

Cada imagem precisa de dois dados: o **contexto de build** (diretório com o Dockerfile) e o
**repositório ECR** de destino. O nome do repo ECR normalmente **não** é derivável do path de
forma confiável, então use uma destas fontes, nesta ordem:

1. **Manifesto `ecr-apps.json`** (preferido para repositórios com vários apps) — declara o
   mapeamento contexto → repositório de forma versionada. Formato:
   ```json
   {
     "apps": [
       { "context": "dvn-workshop-apps/backend/YoutubeLiveApp", "repository": "meu-org/backend" },
       { "context": "dvn-workshop-apps/frontend/youtube-live-app", "repository": "meu-org/frontend" }
     ]
   }
   ```
   Caminhos de `context` são relativos à pasta do manifesto. `dockerfile` é opcional (default
   `Dockerfile`). Se o repo ainda não tem esse arquivo mas tem vários Dockerfiles, **proponha
   criá-lo** listando os Dockerfiles encontrados (`find . -name Dockerfile` ignorando
   `node_modules/bin/obj` e diretórios de teste como `*-workspace/`), e peça ao usuário os nomes
   dos repositórios ECR de cada um. Não adivinhe o nome do repo.

2. **Apps inline** via `--app <contexto>:<repo>` (pode repetir) — bom para um comando pontual sem
   criar arquivo. Ex.: `--app apps/api:meu-org/api --app apps/web:meu-org/web`.

Se você encontrar Dockerfiles mas não souber o repo de destino de cada um, **pergunte** — é o
único dado que a skill não consegue inferir com segurança.

### 3. Rodar o build & push (login + paralelo) com o script bundled

Use o script, que faz login uma vez e builda/empurra todos em paralelo:

```bash
scripts/ecr_build_push.sh --tag <tag> [--region <region>] [--profile <profile>] \
  [--manifest <arquivo> | --app <ctx>:<repo> ...] [--also-latest] [--dry-run]
```

- Comece com `--dry-run` quando quiser mostrar ao usuário exatamente o que será feito (login,
  quais imagens, quais tags) **sem** publicar. Útil para confirmar antes de uma publicação real.
- Leia `scripts/ecr_build_push.sh` para todos os parâmetros. O script já:
  resolve conta/registry, faz um único `docker login`, builda cada app em paralelo com log
  próprio, agrega e retorna código de saída != 0 se qualquer app falhar.

### 4. Reportar

Ao final, informe ao usuário, por app: o **URI completo da imagem** publicada
(`<registry>/<repo>:<tag>`), se o push foi OK, e o resultado geral. Se algum app falhou, mostre a
causa (do log do script) — ex.: repo inexistente (`RepositoryNotFoundException`), credencial sem
permissão `ecr:PutImage`, ou erro de build. Não declare sucesso se algum push falhou.

## Erros comuns e como agir

- **`RepositoryNotFoundException` / `name unknown`** → o repo ECR não existe. A skill não cria por
  padrão; ofereça criar com `aws ecr create-repository --repository-name <repo>` (com
  `--image-scanning-configuration scanOnPush=true`) após confirmação, ou peça o nome correto.
- **`no basic auth credentials` / `denied`** → o login expirou ou foi para o registry errado.
  Refaça o login (o script já faz) e confira conta/região.
- **`exec format error` ao rodar no cluster** → imagem buildada para a arquitetura errada. Garanta
  `--platform linux/amd64` (o script já fixa isso).
- **`AccessDenied` no push** → a policy do usuário/role não tem `ecr:PutImage`,
  `ecr:InitiateLayerUpload`, etc. Reporte qual permissão falta.

## Checklist

- [ ] Identidade/conta/região confirmadas antes do push
- [ ] Cada app tem contexto + repositório ECR definidos (manifesto ou `--app`)
- [ ] Login feito uma única vez no registry
- [ ] Build com `--platform` da arquitetura-alvo (amd64 por padrão)
- [ ] Tag explícita (não silenciosa); `:latest` só como adicional
- [ ] Apps buildados em paralelo, resultados agregados
- [ ] Reportado o URI publicado de cada imagem e o status real (sem falso sucesso)
