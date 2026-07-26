# Referência: .NET (ASP.NET Core / console / worker)

## Armadilhas específicas

- **Imagens oficiais separam SDK de runtime.** Use `mcr.microsoft.com/dotnet/sdk:<ver>` no estágio
  de build e `mcr.microsoft.com/dotnet/aspnet:<ver>` (web) ou `runtime:<ver>` (console/worker) no
  estágio final. O SDK é grande (~800 MB+); ele **jamais** deve ir para a imagem final.
- **Usuário não-root já existe nas imagens .NET 8+.** As imagens trazem o usuário `app` (UID 1654).
  Basta `USER app` — não precisa criar. Em .NET 8+ há também as variantes `-chiseled` (Ubuntu
  Chiseled, distroless-like), que já rodam como não-root por padrão e são as mais enxutas/seguras.
- **Alpine em .NET usa musl.** Existem tags `-alpine`, mas exigem o runtime musl e às vezes
  `InvariantGlobalization`. Para a maioria dos casos, `-slim`/Debian ou **`-chiseled`** dão o melhor
  equilíbrio entre tamanho e compatibilidade. Prefira chiseled quando disponível para o TFM.
- **Porta padrão.** No .NET 8+ o Kestrel escuta na **8080** por padrão dentro do container (não mais
  80), sob o usuário não-root. Confirme via `ASPNETCORE_URLS`/`ASPNETCORE_HTTP_PORTS` e faça o
  `EXPOSE` bater com a porta real.
- **Publique com `--no-restore` após um `restore` em separado** para aproveitar o cache: copie o
  `.csproj`, rode `dotnet restore`, depois copie o resto e `dotnet publish`. Assim mudar código não
  refaz o restore.
- **`curl` não existe** nas imagens aspnet/runtime nem no chiseled. Para o HEALTHCHECK, ou adicione
  um endpoint de health e cheque via um pequeno utilitário, ou instale `curl` só no caso não-chiseled.
  A forma mais limpa é expor `/health` (via `Microsoft.AspNetCore.Diagnostics.HealthChecks`, já
  incluso no ASP.NET Core) e checar de fora (o `curl` do host, que o script de validação faz).

## Detecção do perfil

- **Web (ASP.NET Core)** → `Sdk="Microsoft.NET.Sdk.Web"` no `.csproj`, ou pacotes `Microsoft.AspNetCore.*`.
  Tem HTTP → healthcheck HTTP.
- **Console/Worker** → `Sdk="Microsoft.NET.Sdk"` ou `Microsoft.NET.Sdk.Worker`. Sem HTTP → healthcheck
  de processo (ver `healthcheck.md`).
- O **TargetFramework** (`<TargetFramework>net8.0</TargetFramework>`) define a tag de imagem: `net8.0`
  → `:8.0`, `net9.0` → `:9.0`.

## Template — Web (ASP.NET Core), chiseled, porta 8080

```dockerfile
# ---- build ----
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# restore primeiro, para cache
COPY ["MyApp.csproj", "./"]
RUN dotnet restore "MyApp.csproj"

# código e publish
COPY . .
RUN dotnet publish "MyApp.csproj" -c Release -o /app/publish /p:UseAppHost=false

# ---- runtime ----
FROM mcr.microsoft.com/dotnet/aspnet:8.0-noble-chiseled AS runtime
WORKDIR /app
COPY --from=build /app/publish .

# chiseled já roda como não-root (usuário app); porta padrão 8080
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/app/MyApp", "--healthcheck"] || exit 1

ENTRYPOINT ["dotnet", "MyApp.dll"]
```

> Nota sobre o HEALTHCHECK acima: imagens chiseled não têm shell nem curl. As opções realistas são:
> (a) expor `/health` e deixar o **script de validação** checar de fora com o `curl` do host — recomendado;
> (b) se precisar de check interno, usar uma imagem base não-chiseled que tenha shell e instalar `curl`.
> Escolha (a) por padrão: mantém a imagem mínima e ainda valida o health de verdade.

## Template — Web com HEALTHCHECK interno (base slim com curl, porta 8080)

Use quando você precisa que o próprio Docker marque `healthy` a partir de dentro (ex.: orquestrador
que depende do status do container) e aceita uma imagem um pouco maior:

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["MyApp.csproj", "./"]
RUN dotnet restore "MyApp.csproj"
COPY . .
RUN dotnet publish "MyApp.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/publish .

ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
USER app

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["dotnet", "MyApp.dll"]
```

## Endpoint de health no ASP.NET Core

Se a app ainda não tem `/health`, é trivial adicionar (não requer pacote extra):

```csharp
builder.Services.AddHealthChecks();
// ...
app.MapHealthChecks("/health");
```

Mencione isso ao usuário se você configurar o healthcheck para uma rota que ainda não existe — não
deixe o Dockerfile apontar para um endpoint fantasma.
