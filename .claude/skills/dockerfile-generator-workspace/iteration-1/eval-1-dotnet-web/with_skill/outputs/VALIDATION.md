# Validação do Dockerfile — MyApp (ASP.NET Core net8.0)

Validação executada de verdade com o script da skill:

```
scripts/validate_dockerfile.sh <outputs> 8080 /health
```

## Perfil da aplicação

- Runtime: .NET 8 / ASP.NET Core (`Sdk="Microsoft.NET.Sdk.Web"`, `TargetFramework=net8.0`)
- Assembly: `MyApp` → entrypoint `dotnet MyApp.dll`
- Endpoints: `/` (Hello) e `/health` (`AddHealthChecks` + `MapHealthChecks`)
- Porta: Kestrel escuta em `8080` dentro do container (padrão .NET 8)

## Resultado

| Etapa                       | Resultado |
|-----------------------------|-----------|
| Imagem buildou              | Sim ✅    |
| Container subiu             | Sim ✅ (log: `Now listening on: http://[::]:8080`) |
| Status do HEALTHCHECK       | `healthy` ✅ |
| Curl externo `GET /health`  | `ok` ✅ (HTTP 200, `text/plain`) |
| Tamanho final da imagem     | 359 MB |
| Usuário em runtime          | não-root (`USER app`, UID 1654) ✅ |

Veredito do script: `RESULTADO: OK ✅ (healthcheck=healthy, curl=ok)`

## Decisões e trade-offs

- **Multi-stage**: build no `sdk:8.0`, runtime no `aspnet:8.0`. A imagem final não
  carrega o SDK.
- **Rootless**: usa o usuário não-root `app` (já presente nas imagens .NET 8+) via
  `USER app` antes do `ENTRYPOINT`.
- **Cache de layers**: `COPY MyApp.csproj` + `dotnet restore` antes de copiar o código.
- **HEALTHCHECK real**: `curl -fsS http://127.0.0.1:8080/health` — exercita o endpoint
  HTTP que a app realmente expõe (não apenas "o processo está vivo").
- **Trade-off de imagem base**: foi usada a base `aspnet:8.0` (Debian slim) em vez da
  `-chiseled` (que seria ~2x menor). Motivo: a chiseled não tem shell nem `curl`, então
  não é possível marcar o container como `healthy` de dentro. Como o requisito explícito
  era ter um healthcheck de verdade, optou-se por slim + `curl` (instalado só para o
  healthcheck, com o cache do apt limpo na mesma layer). O `/health` continua sendo
  validado de fora pelo script também.

  Alternativa mais enxuta: trocar para `mcr.microsoft.com/dotnet/aspnet:8.0-noble-chiseled`
  e delegar o health à checagem externa do orquestrador — reduz o tamanho, mas o Docker
  não reporta `healthy` internamente.

> Nota sobre o tamanho: 359 MB é o total reportado pelo BuildKit para o build
> multi-plataforma (inclui manifesto de attestation). A imagem de runtime efetiva
> (aspnet:8.0 + app + curl) fica em torno de ~230 MB por plataforma.
