# syntax=docker/dockerfile:1

# ---- build stage ----
# SDK image (large, ~800MB) — never ships to production.
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Restore first, using only the manifest, so a code change doesn't bust the
# dependency-restore layer cache.
COPY ["MyApp.csproj", "./"]
RUN dotnet restore "MyApp.csproj"

# Now bring in the source and publish.
COPY . .
RUN dotnet publish "MyApp.csproj" \
    -c Release \
    -o /app/publish \
    /p:UseAppHost=false

# ---- runtime stage ----
# aspnet runtime (no SDK/build tools). We install curl so Docker itself can run
# the HEALTHCHECK from inside the container and report healthy/unhealthy.
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/publish .

# Kestrel default in .NET 8 containers is 8080, bound as non-root.
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

# Run as the pre-existing non-root "app" user (UID 1654) shipped in .NET 8 images.
USER app

# /health is provided by the app (AddHealthChecks + MapHealthChecks("/health")).
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["dotnet", "MyApp.dll"]
