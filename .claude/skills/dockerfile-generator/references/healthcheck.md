# Referência: Detecção e configuração de HEALTHCHECK

O objetivo do `HEALTHCHECK` é dar ao Docker (e ao orquestrador) um sinal confiável de que a app
está **funcional**, não só de que o processo existe. Escolha a estratégia pelo perfil da app.

## Passo 1 — a app expõe HTTP?

Procure sinais de servidor HTTP:
- Node: `app.listen(...)`, Express/Fastify/Nest, variável de porta, `EXPOSE`.
- .NET: `Sdk="...Web"`, `Microsoft.AspNetCore.*`, `ASPNETCORE_URLS`/`ASPNETCORE_HTTP_PORTS`.

Se **sim** → healthcheck HTTP. Se **não** (worker, consumidor de fila, CLI, cron) → healthcheck de
processo/comando.

## Passo 2 — descobrir a rota de health

Procure por rotas já existentes, em ordem de preferência: `/health`, `/healthz`, `/api/health`,
`/actuator/health`, `/ping`, `/`.

- Se existe uma rota dedicada de health, use-a.
- Se só existe `/`, pode usá-la, mas prefira sugerir ao usuário adicionar um `/health` dedicado que
  não dependa de renderizar a home inteira — é mais barato e mais estável como sinal.
- Se **não existe nenhuma** e a app é HTTP, adicione uma rota trivial de health (ver referências de
  Node/.NET) em vez de apontar o healthcheck para um endpoint inexistente.

## Estratégias de comando

### HTTP sem curl (Node alpine) — use o runtime da própria app

`node:alpine` não traz curl. Use o http nativo:

```dockerfile
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:PORT/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"
```

### HTTP com curl (base que tenha curl, ex.: Debian slim)

```dockerfile
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:PORT/health || exit 1
```

`-f` faz o curl retornar erro em status HTTP >= 400; `-sS` silencia o progresso mas mostra erro real.

### HTTP em imagem distroless/chiseled (sem shell nem curl)

Não dá para rodar curl nem `|| exit`. Duas saídas:
- Deixar o **script de validação checar de fora** (o `curl` roda no host, contra a porta publicada) —
  recomendado, mantém a imagem mínima.
- Ou embutir um pequeno binário/util de health no build. Só faça isso se o orquestrador exigir o
  status do HEALTHCHECK do próprio Docker.

### Worker/CLI sem HTTP — check de processo ou de liveness

Sem porta para bater. Opções, da mais simples à mais expressiva:

1. **Arquivo de liveness**: a app toca `/tmp/healthy` (via `touch`) a cada ciclo de trabalho; o
   healthcheck confere que o arquivo foi atualizado recentemente. Melhor que checar só o PID, porque
   detecta app "travada mas viva".
2. **Comando próprio**: muitos workers têm um subcomando de health (`myapp --healthcheck`) que valida
   conexão com broker/DB e sai com 0/1.
3. **Último recurso** — checar que o processo principal está no ar (`pgrep`), ciente de que isso não
   detecta deadlock. Prefira 1 ou 2 quando possível.

```dockerfile
# exemplo: arquivo de liveness tocado pelo worker
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD test -f /tmp/healthy && test $(( $(date +%s) - $(stat -c %Y /tmp/healthy) )) -lt 60 || exit 1
```

## Ajuste dos tempos

- `--start-period` — janela de graça no boot; durante ela, falhas não contam. Apps .NET/JVM sobem
  mais devagar; dê `10s`–`30s`. Se o container ficar "unhealthy" logo no início, quase sempre é
  start-period curto demais.
- `--interval` — frequência do check. `15s`–`30s` é razoável; muito curto gera ruído e carga.
- `--timeout` — quanto esperar por cada check. `3s`–`5s`.
- `--retries` — quantas falhas seguidas para marcar `unhealthy`. `3` é um bom padrão.

## Regra de ouro

Não invente rota nem porta. O healthcheck tem que exercitar **o que a app realmente expõe**. Se você
precisou criar um endpoint de health para viabilizar o check, diga isso explicitamente ao usuário.
