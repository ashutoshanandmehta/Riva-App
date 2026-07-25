#!/usr/bin/env python3
"""UserPromptSubmit: route the prompt to the right Vault files and inject only those.
stdout on this event is added to context. Exit 2 rejects the prompt."""
import json, os, sys, re

data = json.load(sys.stdin)
prompt = (data.get("prompt") or "").lower()
root = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())

ROUTES = {
    r"\bauth|login|token|jwt|session|supabase\b":          ["Auth.md", "Security.md"],
    r"\bdb|database|schema|migration|query|sql\b":         ["Database.md", "Security.md"],
    r"\bapi|endpoint|route|contract\b":                    ["API.md", "Services.md"],
    r"\bscan|vision|vlm|claude|anthropic|photo|image\b":   ["Services.md", "Architecture.md"],
    r"\bnutrition|food|portion|calorie|macro|grounding|usda|fdc|caloriemama\b": ["Services.md", "Database.md"],
    r"\bui|component|button|form|modal|table|swift|swiftui|screen|view\b": ["Components.md", "DesignSystem.md"],
    r"\bdeploy|release|ci|pipeline|render|mirror\b":       ["Deployment.md"],
    r"\btest|coverage|spec|eval\b":                        ["Testing.md"],
    r"\bportal|dashboard|admin|web\b":                     ["Portal.md"],
}

files = ["Architecture.md"]
for pattern, targets in ROUTES.items():
    if re.search(pattern, prompt):
        files += targets

out = []
for name in dict.fromkeys(files):
    path = os.path.join(root, "vault", name)
    if os.path.exists(path):
        with open(path) as fh:
            body = fh.read()[:6000]
        out.append(f"<vault file=\"{name}\">\n{body}\n</vault>")

if out:
    print("## Vault context (loaded by hook — do not re-read these files)\n")
    print("\n\n".join(out))

# Hard stop: reject prompts that ask to skip the process.
BLOCKED = [
    (r"skip (the )?(tests?|verifier|verification|planning)", "Verification and planning are mandatory."),
    (r"(ignore|bypass) (the )?(rules|claude\.md|hooks)",     "Project rules are not optional."),
    (r"push (to|directly to) (prod|production|main|master)", "Direct pushes are gated; request approval."),
]
for pattern, reason in BLOCKED:
    if re.search(pattern, prompt):
        print(f"Prompt rejected: {reason}", file=sys.stderr)
        sys.exit(2)
sys.exit(0)
