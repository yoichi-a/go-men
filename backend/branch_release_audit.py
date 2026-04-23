from pathlib import Path
import re
import py_compile

ROOT = Path(__file__).resolve().parent
APP = ROOT / "app" / "main.py"
SMOKE = ROOT / "consult_matrix_smoke.py"
MOBILE = ROOT.parent / "mobile" / "lib" / "main.dart"

REQUIRED = {
    ("couple", "連絡頻度"),
    ("couple", "お金"),
    ("couple", "約束"),
    ("couple", "嫉妬"),
    ("couple", "言い方がきつい"),
    ("couple", "距離感"),
    ("friend", "連絡頻度"),
    ("friend", "お金"),
    ("friend", "約束"),
    ("friend", "人間関係・温度差"),
    ("family", "言い方がきつい"),
    ("family", "お金"),
    ("family", "約束"),
    ("family", "パートナー経由の伝わり方"),
    ("family", "行事・付き合い"),
    ("inlaw", "行事・付き合い"),
}

REQUIRED_FUNCS = {
    "_compose_couple_best_reply",
    "_compose_friend_best_reply",
    "_compose_family_best_reply",
    "_compose_inlaw_best_reply",
    "_compose_relation_best_reply",
    "_apply_consult_reply_composer",
    "_soften_high_emotion_reply",
    "_polish_relation_reply",
}

def fail(msg: str) -> None:
    print("FAIL:", msg)
    raise SystemExit(1)

def ok(msg: str) -> None:
    print("OK  :", msg)

for path in [APP, SMOKE]:
    if not path.exists():
        fail(f"missing file: {path}")

for path in [APP, SMOKE]:
    try:
        py_compile.compile(str(path), doraise=True)
        ok(f"py_compile passed: {path.name}")
    except py_compile.PyCompileError as e:
        fail(f"py_compile failed: {path.name}\n{e}")

app_text = APP.read_text()
smoke_text = SMOKE.read_text()

defs = set(re.findall(r"^def\s+([A-Za-z_][A-Za-z0-9_]*)\(", app_text, re.MULTILINE))
for fn in sorted(REQUIRED_FUNCS):
    if fn not in defs:
        fail(f"missing function definition: {fn}")
    ok(f"function exists: {fn}")

ref_names = set(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\(", app_text))
for fn in sorted(name for name in ref_names if name.startswith("_compose_") and name.endswith("_best_reply")):
    if fn not in defs:
        fail(f"referenced but not defined: {fn}")
ok("all referenced _compose_*_best_reply functions are defined")

case_pattern = re.compile(
    r'\(\s*"[^"]+\s*/\s*[^"]+"\s*,\s*\{\s*"relation_type":\s*"([^"]+)"(?:.|\n)*?"theme":\s*"([^"]+)"',
    re.DOTALL,
)
covered = set(case_pattern.findall(smoke_text))

missing_in_smoke = REQUIRED - covered
extra_in_smoke = covered - REQUIRED

if missing_in_smoke:
    fail("missing smoke cases: " + ", ".join(f"{r}/{t}" for r, t in sorted(missing_in_smoke)))
ok(f"smoke covers all required branches ({len(REQUIRED)})")

if extra_in_smoke:
    print("INFO: extra smoke cases:", ", ".join(f"{r}/{t}" for r, t in sorted(extra_in_smoke)))
else:
    ok("no unexpected extra smoke cases")

if MOBILE.exists():
    mobile_text = MOBILE.read_text()

    rel_literals = {
        "couple": '"couple"' in mobile_text or "'couple'" in mobile_text,
        "friend": '"friend"' in mobile_text or "'friend'" in mobile_text,
        "family": '"family"' in mobile_text or "'family'" in mobile_text,
        "inlaw": '"inlaw"' in mobile_text or "'inlaw'" in mobile_text,
    }
    missing_rel = [rel for rel, present in rel_literals.items() if not present]
    if missing_rel:
        fail("mobile may be missing relation keys: " + ", ".join(missing_rel))
    ok("mobile contains relation keys for couple/friend/family/inlaw")

    missing_themes = [theme for _, theme in sorted(REQUIRED) if theme not in mobile_text]
    if missing_themes:
        fail("mobile may be missing theme literals: " + ", ".join(sorted(set(missing_themes))))
    ok("mobile contains all required theme labels")
else:
    print("INFO: mobile/lib/main.dart not found, skipped mobile audit")

print("\nPASS: backend branch coverage and basic mobile label presence look good.")
