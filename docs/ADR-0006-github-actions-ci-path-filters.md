---
id: ADR-0006
titulo: Pipeline de CI de ponta a ponta no GitHub Actions com path filters por aplicação (backend e frontend independentes), autenticação via OIDC (sem access keys), build e push das imagens para os repositórios ECR existentes com tag pela SHA do commit, e write-back GitOps da nova tag no dvn-workshop-kubernetes/kustomization.yaml via kustomize edit set image (commit direto na main, serializado por concurrency) disparando a sincronização do Argo CD
status: Aprovado
data: 2026-07-26
substitui: N/A
aprovado_por: Kenerry Serain
aprovado_em: 2026-07-26
---

# ADR-0006 — Pipeline de CI de ponta a ponta (GitHub Actions): path filters, OIDC, push para o ECR e write-back do Kustomize

## 1. Contexto

Este ADR define o **pipeline de Continuous Integration completo** do projeto no **GitHub Actions**, do gatilho até o gatilho do CD. Cada workflow, ao terminar, produz dois efeitos: (a) a imagem de container publicada no ECR e (b) o **write-back** da nova tag no `dvn-workshop-kubernetes/kustomization.yaml`, cujo commit na `main` é o que faz o **Argo CD** (ADR-0005) reconciliar o cluster. O write-back **não** é uma decisão arquitetural separada — é o **passo final** do mesmo workflow, na sequência: **OIDC assume-role → login ECR → build → push (tag `github.sha`) → `kustomize edit set image` → commit & push do manifesto**.

> Este ADR **consolida** o conteúdo que antes vivia no ADR-0007 (estratégia de tag por SHA e write-back do Kustomize). O ADR-0007 foi removido; toda a decisão de CI de ponta a ponta passa a ser deste ADR-0006.

Estado atual **já implementado** (verificado nesta sessão):
- **Apps** em `dvn-workshop-apps/`:
  - **backend**: `dvn-workshop-apps/backend/YoutubeLiveApp` (ASP.NET `net8.0`, `Dockerfile` multi-stage pronto, porta 8080, health `/backend/health`, usuário não-root `app` UID 1654).
  - **frontend**: `dvn-workshop-apps/frontend/youtube-live-app` (Next.js 14 standalone, `Dockerfile` pronto, porta 3000, health `/api/health`, usuário `node`).
- **Repositórios ECR existentes** (criados na `02`, ADR-0003): `654654554686.dkr.ecr.us-east-1.amazonaws.com/dvn-workshop/production/backend` e `.../frontend`. Conta `654654554686`, região `us-east-1`.
- **ADR-0004** cria a **federação OIDC GitHub→AWS**: um IAM OIDC provider + uma IAM Role (`role-to-assume`) com permissões mínimas de push no ECR, exposta no output `github_actions_role_arn`.
- **`dvn-workshop-kubernetes/kustomization.yaml`** (raiz) contém o bloco `images:`:
  ```yaml
  # ILUSTRATIVO — não copiar para o repositório
  images:
    - name: dvn-workshop/production/backend
      newName: 654654554686.dkr.ecr.us-east-1.amazonaws.com/dvn-workshop/production/backend
      newTag: v2
    - name: dvn-workshop/production/frontend
      newName: 654654554686.dkr.ecr.us-east-1.amazonaws.com/dvn-workshop/production/frontend
      newTag: v1
  ```
  Os `deployment.yaml` de backend/frontend referenciam a imagem pelo **nome lógico** (`dvn-workshop/production/backend|frontend`); o `newTag` do bloco `images:` é o que efetivamente define a tag aplicada. **É este `newTag` que o write-back atualiza.**
- **Argo CD (ADR-0005)**: uma Application única aponta para `path = dvn-workshop-kubernetes`, `targetRevision = main`, `syncPolicy.automated { prune, selfHeal }`. Qualquer commit que altere o `kustomization.yaml` na `main` dispara reconciliação automática.
- **Repositório GitHub** `kenerry-serain/dvn-workshop-julho`, branch `main`; **não há diretório `.github/` ainda**.
- **Divergência conhecida**: `dvn-workshop-apps/ecr-apps.json` cita repos `devops-na-nuvem/prod/*`, que **não** correspondem aos repos ECR reais (`dvn-workshop/production/*`). Este ADR adota os repos reais como fonte da verdade (ver ADR-0004, item 2).

### Requisitos definidos pelo usuário
1. **Path filters**: o job/workflow do **frontend** só roda com mudanças em `dvn-workshop-apps/frontend/**`; o do **backend** só com mudanças em `dvn-workshop-apps/backend/**`. Decidir **um workflow com dois jobs condicionais** vs. **dois workflows separados** — justificar.
2. Passos por app: **assumir a role via OIDC** (`aws-actions/configure-aws-credentials` com `role-to-assume`, **sem** secrets de chave), **login no ECR**, **docker build & push** para os repositórios **existentes**, **taguear com a SHA do commit** (`github.sha`).
3. Após build/push, **atualizar** o `dvn-workshop-kubernetes/kustomization.yaml` com a nova imagem usando **`kustomize edit set image`** (rodando `kustomize` no diretório `dvn-workshop-kubernetes`), e **commitar e dar push** da alteração de volta ao repositório — é esse commit no manifesto que faz o Argo CD detectar e sincronizar.
4. Decidir a **estratégia de write-back** (commit direto na branch, PR, ou bot/token) e as **permissões necessárias** (`id-token: write`, `contents: write`).

### Fatos verificados via docs oficiais / observados (2026-07-26)
- **OIDC no GitHub Actions**: exige `permissions: id-token: write` no workflow/job para o runner obter o token OIDC; a action `aws-actions/configure-aws-credentials` troca esse token por credenciais temporárias assumindo a role (`role-to-assume`), sem `AWS_ACCESS_KEY_ID`/`SECRET` estáticos (AWS docs — *Use IAM roles to connect GitHub Actions to actions in AWS*; ADR-0004).
- **Trust da role** (ADR-0004): condicionada a `:aud = sts.amazonaws.com` e `:sub = repo:kenerry-serain/dvn-workshop-julho:*` — logo o workflow **deve** rodar neste repositório.
- **Login no ECR**: padrão `aws ecr get-login-password | docker login` ou a action `aws-actions/amazon-ecr-login` (produz o registry e faz o login). As 6 permissões de push da role (ADR-0004) cobrem exatamente esse fluxo.
- **Tag por commit**: `github.sha` é o SHA do commit que disparou o workflow; usado como tag imutável da imagem (rastreabilidade 1:1 commit↔imagem).
- **Path filters**: o GitHub Actions suporta `on.push.paths`/`on.pull_request.paths` no nível do **workflow**, e filtros por caminho no nível de **job** exigem uma action de detecção de mudanças (ex.: `dorny/paths-filter`) ou workflows separados. (Comportamento do GitHub Actions; versões de actions de terceiros a pinar por SHA — ver Riscos.)
- **`kustomize edit set image`**: atualiza o bloco `images:` de um `kustomization.yaml` no diretório corrente. Sintaxe do override: `kustomize edit set image <name>=<newName>:<newTag>` (ou `<name>:<newTag>` para só a tag). Com os `name` lógicos existentes, o comando alveja exatamente as entradas `dvn-workshop/production/backend|frontend`. (Comportamento do Kustomize CLI; versão a fixar no runner — ver Riscos.)
- **Argo CD reconcilia por commit** (ADR-0005): `targetRevision = main` + `automated` → o push do write-back na `main` dispara o sync. Não há webhook obrigatório; o Argo CD faz polling (intervalo padrão ~3 min) — opcionalmente acelerável por webhook (fora do escopo).
- **GitHub Actions write-back**: um `git commit`/`git push` a partir do runner exige `contents: write`. O ator do commit pode ser o `GITHUB_TOKEN` (bot `github-actions[bot]`) ou um token/app dedicado. Commits feitos com o `GITHUB_TOKEN` **não** disparam novos workflows por default do GitHub (defesa contra loop).
- **Sem loop**: os workflows de **build** observam `dvn-workshop-apps/**`. O write-back toca `dvn-workshop-kubernetes/**` — **fora** desses paths — então **não** re-dispara os builds, desde que nenhum workflow de build observe `dvn-workshop-kubernetes/**`.

### Conflitos / divergências
1. **Nenhum ADR anterior contradiz.** Depende do ADR-0004 (role OIDC), alimenta o ADR-0005 (o commit de write-back dispara o Argo CD). Não substitui nada.
2. A rule `.claude/rules/kubernetes-manifests.md` e a `terraform-naming.md` **não se aplicam** a workflows YAML do GitHub Actions (não são manifests K8s nem Terraform). Segue-se, porém, o espírito de coesão e nomes descritivos.

## 2. Drivers da decisão

1. **Builds independentes e eficientes** (requisito 1): mudar só o frontend não deve rebuildar/republicar o backend, e vice-versa. Economiza tempo de CI e evita tags/deploys espúrios.
2. **Segurança — OIDC sem credenciais estáticas** (requisito 2): reutilizar a role do ADR-0004; `id-token: write` só onde necessário.
3. **Rastreabilidade commit↔imagem↔cluster**: tag = `github.sha` no ECR **e** no `newTag` do Kustomize, correlacionando imagem, commit e o estado sincronizado pelo Argo CD.
4. **Fechar o loop de CD sem passo manual** (requisitos 3–4): o write-back é o gatilho do CD; deve ser confiável e automático, com o mínimo de permissão de escrita.
5. **Robustez sob concorrência**: dois workflows (backend/frontend) podem tentar commitar no mesmo `kustomization.yaml` "ao mesmo tempo" — o write-back não pode perder atualizações nem travar em conflito.
6. **Sem loop de CI**: o commit de write-back não pode re-disparar os builds.
7. **Simplicidade e manutenção** (workshop): estrutura de workflows clara, fácil de estender para novos apps, com o mínimo de dependências de actions de terceiros (e essas pinadas).
8. **Compatibilidade com o CD**: o resultado do CI (imagem no ECR + tag) precisa encaixar no modelo de Application única do Argo CD (ADR-0005).

## 3. Opções consideradas

### Dimensão A — Estrutura dos workflows (path filters)

#### A1 — **Dois workflows separados**, um por app, cada um com `on.push.paths` — **escolhida**
`.github/workflows/backend.yml` com `on.push.paths: [dvn-workshop-apps/backend/**]` e `.github/workflows/frontend.yml` com `on.push.paths: [dvn-workshop-apps/frontend/**]`. Cada workflow builda/push/write-back apenas do seu app.

Trade-offs:
- **Isolamento total**: o filtro de caminho vive no gatilho (`on.push.paths`) — o workflow do backend **nem inicia** para mudanças só no frontend. Sem necessidade de action de detecção de mudanças.
- **Simplicidade**: cada arquivo é autocontido e legível; fácil dar manutenção/rollback por app.
- **Menos dependências de terceiros**: não precisa de `dorny/paths-filter`.
- **Duplicação**: passos comuns (OIDC login, ECR login, write-back) repetem entre os dois arquivos. Mitigável com um **composite action** local (`.github/actions/...`) ou um **reusable workflow** (`workflow_call`) compartilhado — o Engineer decide o "como".
- **Contra o write-back concorrente**: se um mesmo push tocar os dois apps, os dois workflows rodam em paralelo e **ambos** tentam commitar no `kustomization.yaml` — risco de conflito de push. **Tratado na Dimensão D** (serialização via `concurrency`/retry/rebase).

#### A2 — **Um workflow, dois jobs condicionais** com `dorny/paths-filter` — **descartada**
Um `.github/workflows/ci.yml` com um job "changes" (usando `dorny/paths-filter`) que seta outputs `backend`/`frontend`, e dois jobs `build-backend`/`build-frontend` com `if:` sobre esses outputs.

Trade-offs:
- **DRY**: passos comuns num só arquivo; um só ponto de manutenção.
- **Coordenação do write-back**: mais fácil serializar os commits (um workflow, `needs:` entre jobs).
- **Dependência de terceiros**: exige `dorny/paths-filter` (pinar por SHA); o workflow **sempre inicia** (mesmo que os jobs de build sejam skipped), consumindo um runner para o job de detecção.
- **Complexidade**: lógica condicional (`if:`, outputs) menos óbvia que dois arquivos independentes.
- **Descartada** por preferir o isolamento e a simplicidade do A1 (sem action de terceiros no gatilho); a coordenação de write-back é resolvível no A1 via `concurrency` (Dimensão D).

### Dimensão B — Login no ECR

#### B1 — Action `aws-actions/amazon-ecr-login` (após `configure-aws-credentials`) — **escolhida**
Padrão oficial AWS: `configure-aws-credentials` (OIDC) → `amazon-ecr-login` (faz `docker login` no registry e expõe o registry como output).

Trade-offs: **oficial, conciso, mantido pela AWS**; uma dependência a mais (pinar por SHA). Menos código que o comando cru.

#### B2 — `aws ecr get-login-password | docker login` cru — **alternativa aceitável**
Sem action de login; usa o AWS CLI já presente no runner.

Trade-offs: **zero dependência de action de login**, porém mais verboso. Fica registrado como equivalente; o Engineer pode optar por ele para minimizar actions de terceiros.

### Dimensão C — Ferramenta de build

#### C1 — `docker/build-push-action` (Buildx) — **escolhida**
Build + push num passo, com cache de layers (`cache-from`/`cache-to`) e suporte a `tags` múltiplas.

Trade-offs: **cache eficiente** (importante para o SDK .NET e o build Next.js), oficial Docker; dependência a pinar. Reduz tempo de CI.

#### C2 — `docker build` + `docker push` crus — **alternativa aceitável**
Trade-offs: sem dependência extra, mas sem cache gerenciado. Registrado como fallback.

### Dimensão D — Estratégia de tag e write-back do Kustomize

#### D1 (tag) — `newTag = github.sha` (mesma tag do push ao ECR) — **escolhida**
O write-back grava no `newTag` a **SHA do commit** que originou a imagem — a **mesma** tag usada no push ao ECR.

Trade-offs:
- **Rastreabilidade máxima**: 1:1 entre commit de código, imagem no ECR e estado sincronizado pelo Argo CD.
- **Imutabilidade prática**: cada deploy referencia uma tag única; rollback = apontar o `newTag` de volta para a SHA anterior (via `git revert` do write-back).
- **Legibilidade**: SHA é menos "humano" que `v2`; mitigável com histórico Git e/ou tag semântica adicional (fora do escopo).

#### D2 (tag) — Tag semântica incremental (`v3`, `v4`, ...) — **descartada**
Continuar a sequência `vN` do bloco atual.

Trade-offs: **legível**, mas exige **gerar/rastrear o próximo número** (estado fora do Git ou parsing do atual) e **não** correlaciona diretamente com o commit. Mais lógica, menos rastreabilidade. **Descartada**; o requisito 2 já fixou `github.sha`.

#### D3 (ator do write-back) — **Commit direto na `main`** com o `GITHUB_TOKEN` (bot `github-actions[bot]`) — **escolhida (base, workshop)**
O próprio workflow, com `permissions: contents: write`, roda `kustomize edit set image` e faz `git commit`/`git push` na `main` usando o `GITHUB_TOKEN` padrão (ator `github-actions[bot]`).

Trade-offs:
- **Simplicidade máxima**: sem token/app extra; fecha o loop imediatamente (Argo CD sincroniza sem aprovação).
- **Segurança**: `GITHUB_TOKEN` é efêmero e escopado ao repo/execução; melhor que um PAT pessoal. Ainda assim, `contents: write` permite escrever em qualquer caminho — mitigável restringindo por branch protection/CODEOWNERS no diretório de manifests.
- **Sem gate humano**: o deploy é automático — desejado no workshop; em produção pode-se querer revisão (ver D4).
- **Branch protection**: se a `main` exigir PR/checks, o commit direto do bot **falha**; exige exceção para o bot ou usar D4/D5. Ver Riscos.

#### D4 (ator do write-back) — **Abrir um Pull Request** com a mudança de tag (merge manual ou automerge) — **descartada como base**
O workflow cria um branch e abre PR com o write-back.

Trade-offs: **gate humano/revisão** e trilha de auditoria por PR; bom para produção. Porém **quebra o CD 100% automático** (a menos que automerge), adicionando latência e passos. Para o workshop é overhead. **Descartada como base**; registrada como evolução para produção (novo ADR/ambiente).

#### D5 (ator do write-back) — **GitHub App/deploy token dedicado** com escopo mínimo (contents write só neste repo) — **escolhida (complementar/produção)**
Usar um GitHub App (ou fine-grained PAT) com permissão **apenas** de conteúdo neste repositório, em vez do `GITHUB_TOKEN`.

Trade-offs: **least privilege explícito** e ator dedicado (não o bot genérico). Nota: o `GITHUB_TOKEN` **não** dispara workflows em cascata (bom para evitar loop aqui); um app dedicado **poderia** disparar — logo, ao adotar D5, manter o path filter/`[skip ci]` como defesa. **Mais setup** (criar/instalar o app, guardar a credencial como secret). **Complementar**: adotar se o time quiser ator dedicado/branch protection; caso contrário D3 basta.

### Dimensão E — Concorrência do write-back

#### E1 — `concurrency` **compartilhado** + `git pull --rebase` com retry — **escolhida**
Serializar os pushes de write-back (grupo de `concurrency` **compartilhado** entre os dois workflows, ex.: `group: kustomize-writeback`, `cancel-in-progress: false`) e, no passo de push, fazer `pull --rebase` + retry em caso de rejeição (não-fast-forward).

Trade-offs:
- **Robustez**: evita perder a atualização de um app quando o outro commita quase simultaneamente; o `rebase` reaplica a mudança sobre o topo atualizado.
- **Simplicidade moderada**: exige o mesmo `concurrency.group` nos dois workflows e um pequeno laço de retry no push.
- **Latência**: com `cancel-in-progress: false`, um write-back espera o outro terminar — aceitável.

#### E2 — Sem coordenação (cada workflow commita livre) — **descartada**
Trade-offs: simples, mas **corre risco real** de push rejeitado/atualização perdida quando ambos os apps mudam no mesmo push. **Descartada** por violar o driver 5.

## 4. Decisão

**A1 + B1 + C1 + D1 + D3 (base) + D5 (complementar/produção) + E1** (com B2/C2 aceitáveis se o time preferir minimizar actions de terceiros).

O pipeline completo de cada workflow é a sequência: **checkout → OIDC assume-role → login ECR → build → push (tag `github.sha`) → `kustomize edit set image` → commit & push do manifesto**.

1. **Dois workflows separados** em `.github/workflows/`:
   - `backend.yml` — `on: push: { branches: [main], paths: [dvn-workshop-apps/backend/**] }`.
   - `frontend.yml` — `on: push: { branches: [main], paths: [dvn-workshop-apps/frontend/**] }`.
   - (Opcional) espelhar `on.pull_request.paths` para buildar/validar em PR **sem** push/write-back (build de verificação; só publica e escreve na `main`).

2. **Permissões mínimas do workflow**: `permissions: { id-token: write, contents: write }` — `id-token: write` para o OIDC; `contents: write` para o commit de write-back.

3. **Concorrência (E1)**: os dois workflows compartilham um `concurrency.group` de write-back (ex.: `kustomize-writeback`), `cancel-in-progress: false`; o passo de push faz `git pull --rebase origin main` e **retry** em caso de rejeição não-fast-forward.

4. **Passos por workflow** (backend/frontend análogos):
   1. `actions/checkout` (fetch do repo).
   2. `aws-actions/configure-aws-credentials` com `role-to-assume = <github_actions_role_arn do ADR-0004>`, `aws-region = us-east-1`, **sem** `aws-access-key-id`/`secret`. (O ARN da role vem de um **secret/variable do repositório** — ex.: `vars.AWS_GHA_ROLE_ARN` — não hard-coded; ver Premissas.)
   3. `aws-actions/amazon-ecr-login` (B1) ou `aws ecr get-login-password | docker login` (B2).
   4. `docker/build-push-action` (C1) com:
      - `context = dvn-workshop-apps/backend/YoutubeLiveApp` (frontend: `dvn-workshop-apps/frontend/youtube-live-app`),
      - `file = <context>/Dockerfile`,
      - `push = true`,
      - `tags = 654654554686.dkr.ecr.us-east-1.amazonaws.com/dvn-workshop/production/backend:${{ github.sha }}` (frontend: `.../frontend:${{ github.sha }}`),
      - cache de layers habilitado.
   5. **Write-back** — instalar/fixar o `kustomize` no runner (versão pinada); `cd dvn-workshop-kubernetes`; rodar `kustomize edit set image` atualizando **apenas a entrada do app do workflow**:
      - backend: `kustomize edit set image dvn-workshop/production/backend=654654554686.dkr.ecr.us-east-1.amazonaws.com/dvn-workshop/production/backend:${{ github.sha }}`
      - frontend: análogo para `.../frontend`.
   6. **Commit & push do manifesto** — configurar o git user (bot), `git add kustomization.yaml`, `git commit -m "chore(cd): backend image -> ${{ github.sha }} [skip ci]"` (o `[skip ci]` é defesa em profundidade além do path filter), e push com `git pull --rebase origin main` + retry (E1). É este commit que dispara o Argo CD.

5. **Tag = `github.sha`** (requisito) tanto no push ao ECR quanto no `newTag` do Kustomize (D1): imagem imutável por commit, correlação 1:1 commit↔imagem↔cluster. (Registry ECR está como `MUTABLE` na `02`; a imutabilidade da correlação vem de usar a SHA como tag, não de sobrescrever `vN`.)

6. **Ordem obrigatória**: a tag só é escrita no `kustomization.yaml` **após** o push da imagem ao ECR ter sucesso, no mesmo job — o Deployment nunca aponta para uma tag inexistente.

7. **Sem loop de CI (driver 6)**: o commit de write-back toca só `dvn-workshop-kubernetes/**`, **fora** dos `paths` (`dvn-workshop-apps/**`) dos workflows de build; além disso, commits do `GITHUB_TOKEN` **não** disparam novos workflows por default do GitHub; e `[skip ci]` reforça. Tripla proteção.

8. **Gatilho do Argo CD**: o push na `main` altera o `kustomization.yaml`; o Argo CD (ADR-0005, `targetRevision = main`, `automated`) detecta e sincroniza os Deployments para a nova tag. (Opcional: webhook do GitHub para o Argo CD para reduzir latência de polling — fora do escopo.)

9. **Repositórios ECR = os reais da `02`** (`dvn-workshop/production/backend|frontend`), **não** os do `ecr-apps.json`. Fonte da verdade da tag = o `kustomization.yaml` (nomes lógicos `dvn-workshop/production/*`).

10. **Write-back via `GITHUB_TOKEN` / `github-actions[bot]` (D3)** como base; **D5 (GitHub App/token dedicado)** disponível/recomendado se o time exigir ator dedicado ou branch protection na `main`.

11. **DRY**: os passos comuns (checkout, OIDC, ECR login, write-back) **podem** ser extraídos para um **composite action local** (`.github/actions/...`) ou **reusable workflow** — decisão de "como" do Engineer; o contrato é: dois gatilhos com path filter distintos.

Justificativa frente aos drivers:
- **Driver 1**: `on.push.paths` isola os builds no gatilho — backend e frontend nunca rebuildam um pelo outro.
- **Driver 2**: OIDC via `configure-aws-credentials` + `id-token: write`; nenhuma access key. Role do ADR-0004.
- **Driver 3**: tag `github.sha` no ECR e no `newTag` do Kustomize correlaciona commit↔imagem↔cluster.
- **Driver 4**: commit direto (D3) + Argo CD automated = deploy sem passo manual; `contents: write` como única permissão de escrita; D5 disponível para least privilege explícito.
- **Driver 5**: `concurrency` compartilhado + rebase/retry (E1).
- **Driver 6**: path filter + `GITHUB_TOKEN` não encadeia workflows + `[skip ci]`.
- **Driver 7**: dois arquivos simples, sem action de detecção no gatilho; passos comuns fatoráveis.
- **Driver 8**: imagem+tag no ECR e o `newTag` escrito alimentam o Argo CD (ADR-0005).

## 5. Consequências

Positivas:
- Builds independentes e rápidos; sem deploys espúrios do app que não mudou.
- CI sem credenciais de longa duração (OIDC).
- Loop de CD fechado: push de código → imagem no ECR → write-back → Argo CD sincroniza, sem intervenção.
- Rastreabilidade 1:1 commit↔imagem↔cluster via `github.sha`; rollback simples (`git revert` do write-back).
- Estrutura fácil de estender (novo app = novo workflow com seu path filter); concorrência tratada; sem loop de CI.

Negativas / dívida técnica aceita:
- **Duplicação de passos** entre `backend.yml` e `frontend.yml` (mitigável por composite/reusable workflow).
- **Commit direto na `main` sem revisão** (D3): qualquer build na `main` altera o estado desejado do cluster automaticamente. Aceito para workshop; produção usaria D4 (PR) ou branch protection + D5.
- **`contents: write` no workflow**: o runner pode escrever no repo — superfície ampliada. **Mitigação**: escopo mínimo, ator bot, mensagem rastreável, branch protection/CODEOWNERS no diretório de manifests; D5 para ator dedicado.
- **Write-back concorrente**: um push que toque os dois apps roda os dois workflows em paralelo, ambos commitando no `kustomization.yaml`. **Mitigação**: `concurrency` compartilhado + retry com rebase (E1).
- **Poluição do histórico**: cada deploy gera um commit de bot no `kustomization.yaml`. Aceito (é a trilha de auditoria do GitOps); mitigável com mensagens padronizadas.
- **Latência de polling do Argo CD** (~3 min) até sincronizar. Aceito; webhook opcional reduz.
- **Dependência de actions de terceiros** (`configure-aws-credentials`, `amazon-ecr-login`, `build-push-action`, e — se A2 fosse escolhido — `paths-filter`) e da **versão do `kustomize`** no runner: risco de supply chain / reprodutibilidade. **Mitigação**: **pinar actions por SHA de commit** e **fixar a versão do kustomize**.
- **`ecr-apps.json` desatualizado** permanece até correção fora deste ADR; se um workflow usá-lo por engano, aponta ao repo errado.
- **ECR `MUTABLE`**: tags podem ser sobrescritas; como usamos `github.sha` (único por commit), o risco prático é baixo. Endurecer para `IMMUTABLE` seria um ajuste na `02` (fora do escopo).

## 6. Plano de implementação

Passos atômicos. Os arquivos são **workflows do GitHub Actions** (YAML) e, opcionalmente, um composite action local — **não** são manifests K8s nem Terraform, então as rules `terraform-naming.md`/`kubernetes-manifests.md` não se aplicam; segue-se coesão e nomes descritivos.

0. **Criar o diretório `.github/workflows/`** no repositório.
   *Conclusão:* diretório existe no repo.

1. **Publicar o ARN da role do ADR-0004** como **variable/secret do repositório** (ex.: `vars.AWS_GHA_ROLE_ARN`), obtido do output `github_actions_role_arn`. (Config do repo GitHub, não arquivo.)
   *Conclusão:* a variable/secret existe e contém o ARN da role.

2. **Criar `.github/workflows/backend.yml`** com o pipeline completo:
   - `on.push` (branch `main`, `paths: [dvn-workshop-apps/backend/**]`);
   - `permissions: { id-token: write, contents: write }`;
   - `concurrency: { group: kustomize-writeback, cancel-in-progress: false }` (mesmo grupo do frontend);
   - passos: checkout → `configure-aws-credentials` (OIDC, `role-to-assume = vars.AWS_GHA_ROLE_ARN`, região `us-east-1`) → ECR login → build/push (`context = dvn-workshop-apps/backend/YoutubeLiveApp`, tag `:${{ github.sha }}` para `.../dvn-workshop/production/backend`) → instalar/fixar kustomize → `cd dvn-workshop-kubernetes` + `kustomize edit set image dvn-workshop/production/backend=...:${{ github.sha }}` → `git commit`/push com rebase+retry.
   *Conclusão:* push tocando `dvn-workshop-apps/backend/**` na `main` publica a imagem `:<sha>` no ECR do backend e grava `images[backend].newTag = <sha>` no `kustomization.yaml` com um commit do bot; o frontend permanece intocado.

3. **Criar `.github/workflows/frontend.yml`** análogo (`paths: [dvn-workshop-apps/frontend/**]`, `context = dvn-workshop-apps/frontend/youtube-live-app`, tag e `kustomize edit set image` para `.../frontend`, mesmo `concurrency.group`).
   *Conclusão:* push tocando `dvn-workshop-apps/frontend/**` publica a imagem `:<sha>` e grava `images[frontend].newTag = <sha>`; o backend permanece intocado.

4. **Garantir a ordem write-after-push**: o passo de `kustomize edit set image`/commit vem **depois** do push da imagem no mesmo job (só escreve a tag após o push bem-sucedido).
   *Conclusão:* nunca há commit de tag sem a imagem correspondente já no ECR.

5. **Implementar retry com rebase** no passo de push (laço: `git pull --rebase origin main` → `git push`; repetir N vezes em rejeição não-fast-forward).
   *Conclusão:* um teste que force concorrência (push nos dois apps no mesmo commit) resulta em **ambos** os `newTag` atualizados.

6. **(Opcional, DRY) Extrair passos comuns** para `.github/actions/<nome>/action.yml` (composite) ou um reusable workflow (`workflow_call`); referenciar nos dois workflows.
   *Conclusão:* os dois workflows reutilizam o passo comum sem duplicar lógica.

7. **(Opcional D5) Trocar o `GITHUB_TOKEN` por um GitHub App/token dedicado** com contents:write só neste repo, se o time exigir ator dedicado/branch protection.
   *Conclusão:* commits de write-back aparecem sob o ator dedicado; branch protection satisfeita.

8. **Pinar todas as actions de terceiros por SHA** de commit e **fixar a versão do kustomize** no runner.
   *Conclusão:* nenhuma action referenciada por tag flutuante (ex.: `@v4`); versão do kustomize fixa.

9. **Garantir ausência de loop**: confirmar que nenhum workflow de build observa `dvn-workshop-kubernetes/**` e que o commit do bot não encadeia workflows.
   *Conclusão:* o write-back **não** dispara novos builds.

10. **Testar isolamento, push, write-back e reconciliação** (Seção 11).

## 7. Layout de diretórios

Não é Terraform nem manifest K8s. Estrutura proposta para o CI:

```
.github/
├── workflows/
│   ├── backend.yml           # on.push.paths: dvn-workshop-apps/backend/**  -> build+push ECR backend + kustomize edit set image (backend) -> commit main
│   └── frontend.yml          # on.push.paths: dvn-workshop-apps/frontend/** -> build+push ECR frontend + kustomize edit set image (frontend) -> commit main
└── actions/                  # (opcional) composite action local para passos comuns (OIDC + ECR login + write-back)
    └── ecr-login/
        └── action.yml

dvn-workshop-kubernetes/
└── kustomization.yaml        # bloco images: (newTag) atualizado pelo write-back de cada workflow; observado pelo Argo CD (ADR-0005)
```

Observações:
- Um workflow por app, gatilho com `paths` distinto — o isolamento vive no `on.push.paths`.
- O contexto de build de cada app aponta para o diretório do respectivo `Dockerfile` já existente.
- O `kustomize edit set image` roda **no diretório `dvn-workshop-kubernetes`** (raiz do Kustomize que contém o bloco `images:`); cada workflow altera **apenas a entrada do seu app**, evitando que um app sobrescreva a tag do outro.

## 8. Boas práticas aplicáveis

- **Rastreabilidade ADR**: embora workflows do GitHub Actions **não** sejam recursos AWS taggáveis, **as imagens publicadas por eles vão para repositórios ECR criados sob `adr=ADR-0003`**. Recomenda-se comentar no topo de cada workflow a referência ao **ADR-0006** (e ao ADR-0004 para a role); usar mensagem de commit de write-back padronizada referenciando o app e a `github.sha` (e, se desejado, `ADR-0006`). Se desejado, adicionar uma label OCI na imagem (`org.opencontainers.image.revision = github.sha`) no build. **Todo recurso AWS eventualmente criado a partir deste ADR deve carregar a tag `adr=ADR-0006`.**
- **Segurança / least privilege**:
  - `permissions` **mínimas** e **explícitas** por workflow (`id-token: write` para o OIDC; `contents: write` **só** por causa do write-back).
  - **Nenhuma** access key AWS estática; só a role do ADR-0004. `GITHUB_TOKEN` efêmero (ou GitHub App de escopo mínimo em D5); nunca um PAT pessoal amplo.
  - Considerar branch protection/CODEOWNERS restringindo escrita ao diretório de manifests.
  - **Pinar actions de terceiros por SHA** (supply chain); **fixar a versão do kustomize** no runner.
  - Restringir os workflows à branch `main` no gatilho (`branches: [main]`), coerente com o `:sub`/`targetRevision` (ADR-0004/0005).
- **Idempotência/rastreabilidade da tag**: `newTag = github.sha` (único por commit); rollback determinístico via `git revert`.
- **Robustez**: `concurrency` compartilhado + `pull --rebase`/retry para não perder atualizações concorrentes.
- **Ordem write-after-push**: só escrever a tag no manifesto **após** o push da imagem, para o Deployment nunca apontar para tag inexistente (reforçado pelo `prune`/`selfHeal` do Argo CD, que faria o Deployment falhar o pull).
- **Sem loop de CI**: write-back fora dos `paths` de build; `GITHUB_TOKEN` não encadeia workflows; marcador `[skip ci]` como defesa extra.
- **Eficiência**: cache de layers no build; path filters evitam CI desnecessário.
- **Fonte da verdade**: `dvn-workshop/production/{backend,frontend}` (da `02`) e o `kustomization.yaml` (nomes lógicos), **não** o `ecr-apps.json`.
- **Consistência com o CD**: a tag publicada é exatamente a que o write-back grava no `newTag` e que o Argo CD (ADR-0005) reconcilia; `targetRevision = main` casa com o commit direto na `main`.

## 9. Riscos e mitigações

- **[NÃO VERIFICADO] Versões/SHAs das actions de terceiros** (`aws-actions/configure-aws-credentials`, `aws-actions/amazon-ecr-login`, `docker/build-push-action`, eventual `dorny/paths-filter`) — não fixadas nesta sessão. **Mitigação**: o Engineer pina cada uma pela SHA da release estável mais recente ao implementar; não usar tags móveis.
- **[NÃO VERIFICADO] Versão/instalação do `kustomize` no runner** e o comportamento exato de `edit set image` com os `name` lógicos atuais — não executado nesta sessão. **Mitigação**: fixar a versão do kustomize; testar o comando localmente contra o `kustomization.yaml` real antes de habilitar o push.
- **Write-back concorrente** (dois workflows commitando no `kustomization.yaml`) — **mitigação**: `concurrency.group` compartilhado + `cancel-in-progress: false` + `pull --rebase`/retry (E1). Validar com teste de concorrência.
- **`contents: write` amplia a superfície** do runner — **mitigação**: escopo mínimo, ator bot, mensagem rastreável, branch protection/CODEOWNERS; D5 (app dedicado) para least privilege explícito.
- **Branch protection na `main`** bloqueando commit direto do bot — **mitigação**: exceção para o bot/app, ou migrar para D4 (PR + automerge) / D5 (app dedicado). Confirmar a config de proteção da `main` (Premissa).
- **Loop de CI infinito** (o commit de write-back dispara outro workflow) — **mitigação**: o write-back toca `dvn-workshop-kubernetes/**`, **fora** dos `paths` (`dvn-workshop-apps/**`); commits do `GITHUB_TOKEN` não disparam workflows; `[skip ci]`. Confirmar que nenhum workflow observa `dvn-workshop-kubernetes/**` para build.
- **Trust da role restrito ao repo** (ADR-0004): se o workflow rodar de um fork/PR de fork, o OIDC token não é emitido por default do GitHub → o `configure-aws-credentials` falha. **Mitigação**: é o comportamento desejado (segurança); builds de verificação de forks não publicam.
- **Commit direto sem revisão publica no cluster automaticamente** — **mitigação**: aceitável em workshop; produção usa PR/gate (D4) e/ou ambientes separados (novo ADR).
- **`prune`/`selfHeal` do Argo CD (ADR-0005)** reforçam a autoridade do Git: um write-back errado (tag inexistente) faz o Deployment falhar o pull da imagem. **Mitigação**: garantir a ordem write-after-push no workflow.
- **Latência de polling** do Argo CD — **mitigação**: opcional webhook GitHub→Argo CD (fora do escopo).
- **Divergência `ecr-apps.json`** — **mitigação**: usar os repos reais / o `kustomization.yaml`; ignorar/corrigir o `ecr-apps.json`.
- **PR builds sem push/write-back**: se habilitar `on.pull_request`, garantir que **não** haja push/write-back em PR (só na `main`). **Mitigação**: condicionar push/write-back a `github.ref == refs/heads/main`.

## 10. Rollback

- **Reverter os workflows**: como não há estado provisionado, basta remover/editar os arquivos `.github/workflows/*.yml` (via commit). Sem os workflows, o CI para; o Argo CD continua reconciliando o último estado do Git.
- **Reverter um deploy ruim**: como a tag é `github.sha`, um `git revert` do commit de write-back restaura o `newTag` anterior no `kustomization.yaml`; o Argo CD reconcilia de volta para a imagem boa, que continua no ECR. Este é o mecanismo primário de rollback do CD.
- **Desligar o write-back**: remover o passo de `kustomize edit set image`/commit dos workflows — o CI volta a só buildar/push sem mexer no manifesto; o Argo CD mantém o último estado.
- **Reverter para D4 (PR)**: trocar o passo de commit direto por criação de PR — sem estado a desfazer, só edição do workflow.
- **Reverter a serialização**: remover/ajustar `concurrency` (não recomendado; reintroduz risco de conflito).
- **Desabilitar temporariamente um workflow**: desabilitar pelo UI do GitHub Actions ou remover o gatilho `on.push` — sem afetar o outro app.
- **Reverter a variable do ARN da role**: remover/atualizar `vars.AWS_GHA_ROLE_ARN`; os workflows falham no OIDC até reconfigurar (pausa segura do CI).
- **Fixar temporariamente uma tag**: um commit manual no `kustomization.yaml` (fora do CI) fixa o `newTag`; com `selfHeal` do Argo CD, o cluster segue o Git.

## 11. Validação

O Engineer deve comprovar ao final:
1. **Isolamento por path**: um commit tocando **apenas** `dvn-workshop-apps/backend/**` dispara **só** `backend.yml`; um tocando apenas `frontend/**` dispara **só** `frontend.yml`; um tocando ambos dispara os dois.
2. **OIDC sem chave estática**: o passo `configure-aws-credentials` assume a role do ADR-0004 via OIDC; **não** há `AWS_ACCESS_KEY_ID`/`SECRET` em secrets nem no log.
3. **Login e push no ECR**: a imagem é publicada em `654654554686.dkr.ecr.us-east-1.amazonaws.com/dvn-workshop/production/{backend|frontend}` com tag `= github.sha` (verificar em `aws ecr describe-images` / console).
4. **Write-back correto**: após um build na `main` que muda o backend, o `kustomization.yaml` tem `images[backend].newTag = <github.sha>` e há um commit do bot; o frontend permanece intocado (e vice-versa).
5. **Ordem correta**: a tag só é escrita **após** o push da imagem ao ECR ter sucesso (o Deployment nunca aponta para uma tag inexistente).
6. **Gatilho do Argo CD**: o commit de write-back faz o Argo CD (ADR-0005) sair de `OutOfSync` para `Synced` e atualizar o Deployment do app para a nova tag, **sem** ação manual.
7. **Concorrência**: um push que altere backend **e** frontend resulta em **ambos** os `newTag` atualizados (nenhuma atualização perdida); os pushes serializam via `concurrency`.
8. **Sem loop**: o commit de write-back em `dvn-workshop-kubernetes/**` **não** re-dispara os workflows de build.
9. **Permissões mínimas / least privilege**: `permissions` do workflow contém `id-token: write` (+ `contents: write` para o write-back); ator do commit = `github-actions[bot]` (ou o app dedicado de D5); nenhum PAT amplo; nada além do necessário.
10. **Actions pinadas por SHA** (nenhuma tag móvel) e versão do kustomize fixa.
11. **Kustomize sanidade**: `kustomize build dvn-workshop-kubernetes` renderiza a imagem com a nova tag corretamente após o `edit set image`.
12. **Rollback**: um `git revert` do write-back reverte o Deployment para a imagem anterior via Argo CD.
13. **Fonte da verdade correta**: os workflows apontam para `dvn-workshop/production/*`, não para `devops-na-nuvem/prod/*`.
14. (Se `on.pull_request` habilitado) PRs buildam mas **não** publicam/escrevem; publicação e write-back só na `main`.

## 12. Premissas

Como o pedido foi para planejar diretamente:

1. **Repositório** `kenerry-serain/dvn-workshop-julho`, branch de deploy `main`, alinhada ao `targetRevision` do Argo CD (ADR-0005) e ao `:sub` da role (ADR-0004). Confirmar.
2. **ARN da role do ADR-0004** disponibilizado como variable/secret do repo (ex.: `vars.AWS_GHA_ROLE_ARN`). Confirmar o nome e que o ADR-0004 estará aplicado antes.
3. **Repos ECR** = `dvn-workshop/production/{backend,frontend}` (da `02`), **não** `ecr-apps.json`. Fonte da verdade da tag = o `kustomization.yaml`. Confirmar e corrigir o `ecr-apps.json`.
4. **Dois workflows separados** (A1) é o desejado, com passos comuns opcionalmente fatorados. Confirmar (vs. um workflow com jobs condicionais, A2).
5. **Build e write-back apenas na `main`** (com PR opcional só para verificação). Confirmar a política de PR.
6. **[Ponto de validação] Branch protection na `main`**: assume-se que **permite** commit direto do `github-actions[bot]` (D3). Se a `main` exigir PR/checks, adotar D4 (PR) ou D5 (app dedicado + exceção). Confirmar a configuração de proteção.
7. **Deploy automático sem gate humano** é aceitável (workshop). Confirmar; produção pode exigir PR/aprovação.
8. **`kustomize` disponível/fixável no runner** (versão pinada). Confirmar a versão a usar.

---

> **Bloqueado para implementação.** Este ADR aguarda revisão e aprovação humana.
> Para liberar a execução, edite o cabeçalho: `status: Aprovado`, preencha `aprovado_por` e `aprovado_em`, e faça commit em `docs/`.
