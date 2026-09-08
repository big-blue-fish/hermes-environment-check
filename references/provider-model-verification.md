---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# Verifying a provider/model actually works (live API probe)

When the question is "does this provider/model exist / will it 4xx?", the definitive
answer is a **live chat-completions probe**, not reading docs, not a GitHub review, not
the config. A model listed in docs may be stale; a model missing from docs may work
(bundled runtime can be newer than the upstream repo). Three independent sources,
in increasing authority:

1. **Upstream repo / PR review comments** — LEAST authoritative. They describe the
   `hermes-agent` upstream mainline allow-list (`hermes_cli/models.py`), which may
   differ from the CN Desktop bundled backend you actually run.
2. **`_internal/agent/models_dev_snapshot.json`** — the bundled snapshot (173 providers,
   provider→models dict). If the model id appears here, the runtime considers it valid.
   This is the runtime's own allow-list.
3. **Live API call** — MOST authoritative. If `/chat/completions` returns HTTP 200 with
   a completion, the model works *right now* on that endpoint with that key, regardless
   of what any list says.

Real example: a GitHub PR review claimed a model was "not in the allow-list, will
4xx"; the bundled runtime's `models_dev_snapshot.json` listed it, AND a live
probe returned HTTP 200. The review was stale relative to the installed backend.
Trust the probe.

## Recipe (Windows CN Desktop)

Read the api_key from config.yaml (never echo it — Hermes redacts it; print only length):

```bash
KEY=$(uv run --no-project --with pyyaml python -c "import yaml;print(yaml.safe_load(open(r'<HERMES_HOME>\config.yaml',encoding='utf-8'))['providers']['<provider>']['api_key'])")
echo "key_len=${#KEY}"
```

Then probe with **curl + browser UA**:

```bash
curl -s -m 60 \
  -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"<model>","messages":[{"role":"user","content":"say OK"}],"max_tokens":5}' \
  "<base_url>/chat/completions" -w "\n[HTTP %{http_code}]"
```

## Pitfalls

- **Python urllib gets Cloudflare-blocked** (HTTP 403, body `error code: 1010`). The
  default `Python-urllib` UA is refused by the Cloudflare front on opencode.ai. Use
  `curl` with a browser UA instead. This is NOT a model/provider problem — don't
  conclude "the model is broken" from a 1010.
- **`/models` and `/v1/models` list endpoints may return 403 Forbidden** even when the
  model works — many OpenAI-compatible endpoints don't expose model listing to the
  probe. Skip straight to `/chat/completions`.
- **Python does NOT accept MSYS `/e/...` paths** — `open('/e/Hermes...')` → FileNotFoundError.
  Use Windows `E:\...` (raw string `r'E:\...'`) or `E:/...`.
- **`yaml` may not be importable** in the default `uv run` interpreter → add `--with pyyaml`.

## Finding the bundled snapshot

```bash
find <HERMES_CN_DESKTOP>/data/versions -name "models_dev_snapshot.json"
# e.g. .../0.19.0-cn.7/_internal/agent/models_dev_snapshot.json
# inspect a provider: uv run --no-project python -c "import json;print(json.dumps(json.load(open(<path>))['opencode-go']['models'],ensure_ascii=False,indent=2))"
```
