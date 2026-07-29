#!/usr/bin/env python3
"""Grader programático para a skill dockerfile-generator (iteração 1).

Lê o Dockerfile / .dockerignore / VALIDATION.md de cada run e avalia as assertions
definidas nos eval_metadata.json. Escreve grading.json em cada diretório de run.
"""
import json
import re
import sys
from pathlib import Path

ITER = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "iteration-1"


def read(p: Path) -> str:
    try:
        return p.read_text(encoding="utf-8", errors="ignore")
    except FileNotFoundError:
        return ""


def grade_node(out: Path):
    df = read(out / "Dockerfile")
    di = read(out / ".dockerignore")
    val = read(out / "VALIDATION.md").lower()
    dfl = df.lower()
    # versão sem comentários, para checar instruções reais (ex.: CMD) sem falso match
    dfl_nc = "\n".join(l for l in dfl.splitlines() if not l.strip().startswith("#"))
    checks = []

    def add(text, passed, evidence):
        checks.append({"text": text, "passed": bool(passed), "evidence": evidence})

    add("Dockerfile existe no diretório de outputs", bool(df.strip()),
        f"{len(df)} bytes" if df else "ausente")
    add("Usa base mínima node alpine ou slim (não imagem full)",
        re.search(r"from\s+node:\S*(alpine|slim)", dfl) is not None,
        next((l for l in df.splitlines() if l.lower().startswith("from")), ""))
    add("Define USER não-root antes do CMD/ENTRYPOINT (rootless)",
        re.search(r"^\s*user\s+node", dfl, re.M) is not None
        or re.search(r"^\s*user\s+(?!root)\w+", dfl, re.M) is not None,
        next((l for l in df.splitlines() if l.strip().lower().startswith("user")), "sem USER"))
    add("Contém instrução HEALTHCHECK", "healthcheck" in dfl,
        "HEALTHCHECK presente" if "healthcheck" in dfl else "ausente")
    add("Instala dependências antes de copiar todo o código (cache de layer)",
        re.search(r"copy\s+.*package.*json", dfl) is not None
        and dfl.index("npm ci") < (dfl.index("copy . .") if "copy . ." in dfl else len(dfl))
        if "npm ci" in dfl else "package" in dfl,
        "copia package*.json antes do código" )
    add("Gera .dockerignore cobrindo node_modules", "node_modules" in di,
        "node_modules no .dockerignore" if "node_modules" in di else "faltando/ausente")
    add("Não usa 'npm start' como CMD (usa node diretamente para PID 1 correto)",
        'cmd ["npm"' not in dfl_nc and "cmd npm start" not in dfl_nc and "npm start" not in dfl_nc,
        next((l for l in df.splitlines()
              if l.strip().lower().startswith(("cmd", "entrypoint"))), ""))
    add("VALIDATION.md reporta healthcheck healthy e curl OK",
        "healthy" in val and ("200" in val or "curl" in val and "ok" in val),
        "healthy+curl reportados" if "healthy" in val else "não reportado")
    return checks


def grade_dotnet(out: Path):
    df = read(out / "Dockerfile")
    di = read(out / ".dockerignore")
    val = read(out / "VALIDATION.md").lower()
    dfl = df.lower()
    checks = []

    def add(text, passed, evidence):
        checks.append({"text": text, "passed": bool(passed), "evidence": evidence})

    add("Dockerfile existe no diretório de outputs", bool(df.strip()),
        f"{len(df)} bytes" if df else "ausente")
    add("Multi-stage: build com SDK e runtime com aspnet (sem SDK na imagem final)",
        "dotnet/sdk" in dfl and "dotnet/aspnet" in dfl
        and dfl.rfind("dotnet/sdk") < dfl.rfind("dotnet/aspnet"),
        "sdk no build, aspnet no runtime")
    add("Define USER não-root (app) — rootless",
        re.search(r"^\s*user\s+app", dfl, re.M) is not None or "chiseled" in dfl,
        next((l for l in df.splitlines() if l.strip().lower().startswith("user")),
             "chiseled (não-root por padrão)" if "chiseled" in dfl else "sem USER"))
    add("Contém instrução HEALTHCHECK", "healthcheck" in dfl,
        "HEALTHCHECK presente" if "healthcheck" in dfl else "ausente")
    add("Roda dotnet restore antes de copiar todo o código (cache de layer)",
        "dotnet restore" in dfl and dfl.index("dotnet restore") < (
            dfl.index("copy . .") if "copy . ." in dfl else len(dfl)),
        "restore antes do código" if "dotnet restore" in dfl else "sem restore separado")
    add("Gera .dockerignore cobrindo bin/ e obj/",
        "bin" in di and "obj" in di,
        "bin/ e obj/ no .dockerignore" if ("bin" in di and "obj" in di) else "faltando/ausente")
    add("Porta 8080 (padrão Kestrel .NET 8) configurada/exposta", "8080" in dfl,
        "8080 presente" if "8080" in dfl else "ausente")
    add("VALIDATION.md reporta healthcheck healthy e curl OK",
        "healthy" in val and ("200" in val or ("curl" in val and "ok" in val)),
        "healthy+curl reportados" if "healthy" in val else "não reportado")
    return checks


GRADERS = {"eval-0-node-express": grade_node, "eval-1-dotnet-web": grade_dotnet}

for eval_dir in sorted(ITER.iterdir()):
    if not eval_dir.is_dir() or eval_dir.name not in GRADERS:
        continue
    grader = GRADERS[eval_dir.name]
    for variant in ("with_skill", "without_skill"):
        out = eval_dir / variant / "outputs"
        if not out.exists():
            continue
        checks = grader(out)
        passed = sum(1 for c in checks if c["passed"])
        grading = {
            "eval_id": eval_dir.name,
            "variant": variant,
            "pass_count": passed,
            "total": len(checks),
            "expectations": checks,
        }
        (eval_dir / variant / "grading.json").write_text(
            json.dumps(grading, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"{eval_dir.name}/{variant}: {passed}/{len(checks)}")
