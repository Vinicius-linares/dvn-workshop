# Regra: Padrões de Criação de Manifestos Kubernetes

Toda escrita ou revisão de manifestos Kubernetes **deve** seguir estas
convenções. O objetivo é garantir workloads resilientes, observáveis e prontos
para produção por padrão.

Referências canônicas:
- https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/
- https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- https://kubernetes.io/docs/tasks/run-application/configure-pdb/

## 1. Deployment sempre acompanhado de Service NodePort

- **Toda vez** que um `Deployment` for criado, crie **também** um `Service` do
  tipo `NodePort` que o exponha. Nunca entregue um Deployment sem o Service
  correspondente.
- O `selector` do Service **deve** casar exatamente com os labels de seleção do
  Deployment (`spec.selector.matchLabels`).
- Não fixe o campo `nodePort` a menos que haja exigência explícita; deixe o
  Kubernetes alocar a porta automaticamente. Quando fixar, use valores no range
  válido (`30000`–`32767`).
- Nomeie as `ports` do Service (`name:`) para permitir referência simbólica nas
  probes e em outros recursos.

## 2. Labels de boas práticas (recomendados pelo Kubernetes)

Todo objeto (Deployment, Service, PDB e o template do Pod) **deve** carregar o
conjunto de labels padrão `app.kubernetes.io/*`:

- `app.kubernetes.io/name` — o nome da aplicação (ex.: `youtube-live-app`).
- `app.kubernetes.io/instance` — identificador único desta instância/release.
- `app.kubernetes.io/version` — a versão da aplicação (ex.: `1.2.0`).
- `app.kubernetes.io/component` — o papel do componente (ex.: `backend`,
  `frontend`, `api`, `cache`).
- `app.kubernetes.io/part-of` — o nome do sistema/aplicação de nível mais alto.
- `app.kubernetes.io/managed-by` — a ferramenta que gerencia o recurso (ex.:
  `Helm`, `kustomize`, `terraform`).

Regras de uso:

- Use um **subconjunto estável** desses labels em `spec.selector.matchLabels` do
  Deployment e no `selector` do Service — tipicamente
  `app.kubernetes.io/name` + `app.kubernetes.io/instance`. **Nunca** inclua
  labels mutáveis (como `version`) no selector, pois selectors são imutáveis.
- Replique os labels de seleção no `spec.template.metadata.labels` do Pod,
  acrescentando os demais labels informativos (`version`, `component`, etc.).
- O `Service` e o `PodDisruptionBudget` devem carregar o mesmo conjunto de
  labels de identificação para consistência.

## 3. Readiness e Liveness Probes (obrigatórias)

- **Todo** container principal de um Deployment **deve** especificar
  `readinessProbe` **e** `livenessProbe`. Não entregue Deployment sem ambas.
- Escolha o mecanismo adequado (`httpGet`, `tcpSocket` ou `exec`), preferindo
  `httpGet` para aplicações web/HTTP. Aponte a probe para a porta **nomeada** do
  container.
- Diferencie as duas probes:
  - **Readiness** — indica se o Pod está pronto para receber tráfego; ao falhar,
    o Pod é removido dos endpoints do Service (sem reinício).
  - **Liveness** — indica se o container está saudável; ao falhar, o Pod é
    reiniciado. Use endpoints/checagens mais baratos e tolerantes aqui para
    evitar reinícios em cascata.
- Sempre defina explicitamente os parâmetros de tempo em vez de confiar apenas
  nos defaults: `initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`,
  `failureThreshold` (e `successThreshold` quando aplicável).
- Quando a aplicação tiver inicialização lenta, prefira uma `startupProbe` para
  proteger a liveness durante o boot, em vez de inflar `initialDelaySeconds`.

## 4. Réplicas mínimas

- **Sempre** garanta `spec.replicas >= 2` em Deployments, para disponibilidade e
  rolling updates sem downtime. Nunca entregue um Deployment com `replicas: 1`.
- Se um HPA (`HorizontalPodAutoscaler`) for usado, seu `minReplicas` também
  **deve** ser `>= 2`, e o `replicas` do Deployment não deve conflitar com o HPA
  (deixe o HPA gerenciar após o valor inicial).

## 5. PodDisruptionBudget (obrigatório)

- **Sempre** crie um `PodDisruptionBudget` (PDB) para cada workload com múltiplas
  réplicas, garantindo disponibilidade durante disrupções voluntárias (drains,
  upgrades de nó, etc.).
- O `selector` do PDB **deve** casar com os labels de seleção do Pod.
- Especifique `minAvailable` **ou** `maxUnavailable` (nunca ambos):
  - Com o mínimo de 2 réplicas, prefira `minAvailable: 1` (ou
    `maxUnavailable: 1`) para permitir manutenção sem derrubar todo o serviço.
  - Ajuste o valor proporcionalmente conforme o número de réplicas cresce.

## 6. Layout e organização dos manifestos

- Um workload é composto, no mínimo, por: `Deployment` + `Service` (NodePort) +
  `PodDisruptionBudget`. Trate esses recursos como um conjunto coeso.
- Separe os manifestos por componente/aplicação em arquivos ou diretórios
  próprios; não concentre workloads distintos num único arquivo gigante.
- Ao usar múltiplos recursos no mesmo arquivo YAML, separe-os com `---` e
  mantenha uma ordem previsível (ex.: Deployment, Service, PDB).
- Use `list_api_versions` (ou a doc oficial) para confirmar o `apiVersion`
  correto de cada `kind` antes de escrever o manifesto.

## 7. Checklist ao criar um Deployment

Ao gerar um novo Deployment, confirme **todos** os itens abaixo:

- [ ] `Service` do tipo `NodePort` criado, com `selector` casando o Pod.
- [ ] Labels `app.kubernetes.io/*` presentes em Deployment, Pod, Service e PDB.
- [ ] Selectors usam apenas labels estáveis (`name` + `instance`).
- [ ] `readinessProbe` **e** `livenessProbe` definidas no container principal.
- [ ] Parâmetros de tempo das probes explícitos.
- [ ] `replicas >= 2`.
- [ ] `PodDisruptionBudget` criado, com `minAvailable`/`maxUnavailable` coerente.
