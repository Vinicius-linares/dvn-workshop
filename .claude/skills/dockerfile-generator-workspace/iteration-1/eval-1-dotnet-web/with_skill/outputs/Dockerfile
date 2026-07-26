# ---- build ----
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# restore primeiro, para aproveitar o cache de layer
COPY ["MyApp.csproj", "./"]
RUN dotnet restore "MyApp.csproj"

# código e publish (sem apphost: rodamos via `dotnet MyApp.dll`)
COPY . .
RUN dotnet publish "MyApp.csproj" -c Release -o /app/publish /p:UseAppHost=false

# ---- runtime ----
# aspnet slim (Debian) permite um HEALTHCHECK interno REAL contra /health via curl.
# Trade-off consciente: chiseled seria ~2x menor, mas não tem shell/curl e não
# poderia marcar `healthy` de dentro. Como o requisito é ter healthcheck de verdade,
# usamos slim + curl (imagem ainda enxuta) e mantemos usuário não-root.
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# curl apenas para o HEALTHCHECK interno; limpamos o cache do apt na mesma layer
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/publish .

# Kestrel no .NET 8 escuta na 8080 por padrão dentro do container
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

# usuário não-root `app` (UID 1654) já existe nas imagens .NET 8+
USER app

# HEALTHCHECK real: exercita o endpoint /health que a app expõe
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["dotnet", "MyApp.dll"]
