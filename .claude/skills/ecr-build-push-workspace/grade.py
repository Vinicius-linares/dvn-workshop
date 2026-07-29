#!/usr/bin/env python3
"""Grader programático para a skill ecr-build-push (iteração 1).

Lê o RESULT.md de cada run e avalia as assertions. Escreve grading.json em cada run.
"""
import json
import sys
from pathlib import Path

ITER = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "iteration-1"
REGISTRY = "654654554686.dkr.ecr.us-east-1.amazonaws.com"


def read(out: Path) -> str:
    f = out / "RESULT.md"
    try:
        return f.read_text(encoding="utf-8", errors="ignore")
    except FileNotFoundError:
        return ""


def has_platform(t: str) -> bool:
    tl = t.lower()
    return "linux/amd64" in tl or "--platform" in tl


def no_real_push(t: str) -> bool:
    tl = t.lower()
    # sinais de que ficou em plano/dry-run; e ausência de confirmação de push efetivado
    planned = "dry-run" in tl or "dry run" in tl or "não foi" in tl or "nada foi" in tl or "plano" in tl
    return planned


def grade_multi(out: Path):
    t = read(out); tl = t.lower()
    c = []
    def add(text, ok, ev): c.append({"text": text, "passed": bool(ok), "evidence": ev})
    add("RESULT.md foi gerado", bool(t.strip()), f"{len(t)} bytes" if t else "ausente")
    add("Registry ECR correto (654654554686.dkr.ecr.us-east-1.amazonaws.com)", REGISTRY in t,
        "registry presente" if REGISTRY in t else "faltando")
    add("Menciona login único no ECR via get-login-password", "get-login-password" in tl,
        "get-login-password presente" if "get-login-password" in tl else "faltando")
    add("Cobre AMBOS os apps (backend e frontend)", "backend" in tl and "frontend" in tl,
        "backend+frontend" if ("backend" in tl and "frontend" in tl) else "faltando um")
    add("Usa a tag v1.2.0", "v1.2.0" in tl, "v1.2.0 presente" if "v1.2.0" in tl else "faltando")
    add("Especifica --platform (linux/amd64) para o build", has_platform(t),
        "linux/amd64" if has_platform(t) else "faltando")
    add("Descreve build/push em paralelo (simultâneo)",
        any(w in tl for w in ["paralel", "simultan", "bake", "background", "&", "ao mesmo tempo"]),
        "paralelismo mencionado")
    add("Não fez push real (dry-run / apenas plano)", no_real_push(t), "dry-run/plano")
    return c


def grade_single(out: Path):
    t = read(out); tl = t.lower()
    c = []
    def add(text, ok, ev): c.append({"text": text, "passed": bool(ok), "evidence": ev})
    add("RESULT.md foi gerado", bool(t.strip()), f"{len(t)} bytes" if t else "ausente")
    add("Registry ECR correto (654654554686.dkr.ecr.us-east-1.amazonaws.com)", REGISTRY in t,
        "registry presente" if REGISTRY in t else "faltando")
    add("Menciona login no ECR via get-login-password", "get-login-password" in tl,
        "get-login-password presente" if "get-login-password" in tl else "faltando")
    add("Repo de destino devops-na-nuvem/prod/backend", "devops-na-nuvem/prod/backend" in tl,
        "repo presente" if "devops-na-nuvem/prod/backend" in tl else "faltando")
    add("Usa a tag rc-5", "rc-5" in tl, "rc-5 presente" if "rc-5" in tl else "faltando")
    add("Especifica --platform (linux/amd64) para o build", has_platform(t),
        "linux/amd64" if has_platform(t) else "faltando (baseline pode omitir em host amd64)")
    add("URI completo da imagem reportado (.../backend:rc-5)",
        "backend:rc-5" in tl, "URI presente" if "backend:rc-5" in tl else "faltando")
    add("Não fez push real (dry-run / apenas plano)", no_real_push(t), "dry-run/plano")
    return c


GRADERS = {"eval-0-multi-app-parallel": grade_multi, "eval-1-single-app-inline": grade_single}

for ed in sorted(ITER.iterdir()):
    if not ed.is_dir() or ed.name not in GRADERS:
        continue
    g = GRADERS[ed.name]
    for v in ("with_skill", "without_skill"):
        out = ed / v / "outputs"
        if not out.exists():
            continue
        checks = g(out)
        passed = sum(1 for x in checks if x["passed"])
        (ed / v / "grading.json").write_text(json.dumps(
            {"eval_id": ed.name, "variant": v, "pass_count": passed,
             "total": len(checks), "expectations": checks},
            ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"{ed.name}/{v}: {passed}/{len(checks)}")
