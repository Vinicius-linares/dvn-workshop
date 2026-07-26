# Validação do Dockerfile — MyApp (ASP.NET Core, net8.0)

## Aplicação

- Tipo: minimal API ASP.NET Core (`Sdk="Microsoft.NET.Sdk.Web"`, `TargetFramework=net8.0`).
- Assembly de saída: `MyApp.dll` (`AssemblyName=MyApp`).
- Endpoints: `/` (texto) e `/health` (via `AddHealthChecks()` + `MapHealthChecks("/health")`,
  já presentes no `Program.cs` — nenhuma alteração de código foi necessária).
- Porta: 8080 (Kestrel padrão do .NET 8 dentro do container, `ASPNETCORE_HTTP_PORTS=8080`).

## Decisões do Dockerfile

- **Multi-stage**: estágio de build usa `mcr.microsoft.com/dotnet/sdk:8.0`; o estágio final
  usa `mcr.microsoft.com/dotnet/aspnet:8.0` (só runtime, sem SDK/ferramenta de build).
- **Cache de layer**: copia o `.csproj` e roda `dotnet restore` antes de copiar o código; assim
  mudança de código não invalida o restore.
- **Rootless**: `USER app` (usuário não-root pré-existente nas imagens .NET 8+, UID 1654).
  Verificado em runtime: `uid=1654(app) gid=1654(app)`.
- **HEALTHCHECK real**: instrução `HEALTHCHECK` embutida na imagem, checando `GET /health`
  via `curl` a cada 15s (`--start-period=10s`, `--timeout=3s`, `--retries=3`). O `curl` é
  instalado no estágio final (a imagem aspnet Debian não traz curl).
- **Sem segredos** embutidos na imagem.
- **.dockerignore** cobre `bin/`, `obj/`, `publish/`, `.git/`, `.env`, `.vs/`, `.DS_Store`, etc.

### Trade-off de imagem base

Optou-se pela base `aspnet:8.0` (Debian slim) + `curl` para permitir um **HEALTHCHECK interno**
que o próprio Docker avalia (requisito explícito de "com healthcheck"). A alternativa
`aspnet:8.0-noble-chiseled` gera imagem ainda menor (~120–130MB) e mais segura, porém **não tem
shell nem curl**, então não suporta uma instrução `HEALTHCHECK` interna — o health teria de ser
checado de fora pelo orquestrador. Se o ambiente-alvo checa o health externamente (ex.: probes do
Kubernetes), o chiseled é preferível.

## Resultado da validação (build + run + healthcheck)

Executado via `scripts/validate_dockerfile.sh <contexto> 8080 /health`:

| Item                       | Resultado                                     |
|----------------------------|-----------------------------------------------|
| `docker build`             | OK                                            |
| `docker run` (container)   | OK, container permanece de pé                 |
| Usuário em runtime         | não-root — `uid=1654(app) gid=1654(app)`      |
| Status do HEALTHCHECK      | **healthy**                                   |
| Curl externo em `/health`  | **200 OK**                                    |
| Tamanho final da imagem    | **359 MB**                                     |

Logs confirmam `Now listening on: http://[::]:8080`, ambiente `Production`, e requisições
`GET /health` retornando `200`.

## Como reproduzir

```bash
cd <este-diretório>
# via script bundled da skill:
bash /Users/kenerry/Repositories/dvn-workshop-julho/.claude/skills/dockerfile-generator/scripts/validate_dockerfile.sh "$(pwd)" 8080 /health

# ou manualmente:
docker build -t myapp:latest .
docker run -d --name myapp -p 8080:8080 myapp:latest
docker inspect --format '{{.State.Health.Status}}' myapp   # -> healthy
curl -fsS http://127.0.0.1:8080/health                      # -> 200
docker rm -f myapp
```
