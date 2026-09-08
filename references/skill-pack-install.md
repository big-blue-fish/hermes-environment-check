---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# Installing Skill Packs from ZIP Attachments (CN Desktop)

Verified with batch installs of multiple skill-pack zips from
`<workspace>/.hermes/desktop-attachments/` (or any dir) into
`$HERMES_HOME/skills/` (= `<HERMES_HOME>/skills/`).

## 1. Reconnaissance — zip layouts vary

`unzip -l <zip>` first. Three shapes exist:

- **Top-level SKILL.md** (most packs): unzip straight into a named dir.
- **One nested dir** (e.g. `news-aggregator-skill/`, `投资顾问/`,
  `academic-radar-v3-extract/`): extract to temp, `mv` the inner dir.
- **Multi-skill pack** (e.g. `ima-skills`): top SKILL.md + `notes/SKILL.md`
  + `knowledge-base/SKILL.md` — each sub-dir is its own skill; keep the
  whole tree and fix frontmatter in EACH sub-skill.

## 2. Dedup vs installed skills (BEFORE installing)

```bash
S="<HERMES_HOME>/skills"
ls "$S"; find "$S" -maxdepth 2 -name SKILL.md
```

Diff the zip's SKILL.md against the installed one:

```bash
diff "$S/<existing>/SKILL.md" <(unzip -p <zip> SKILL.md) && echo SAME || echo DIFF
```

Decision table:
- **SAME → skip** (already installed).
- **DIFF → compare frontmatter `version:`** — SKILL.md frontmatter version is
  AUTHORITATIVE; `_meta.json` version can lag badly (e.g. `_meta.json` 的版本
  可能落后于已安装版本).
  Installed newer → skip. Zip newer → overwrite the existing dir.
- **Old subset trap**: 压缩包内 SKILL.md 可能是已安装版本的旧子集（缺章节）→
  跳过. Check diff DIRECTION, not just whether it differs.

## 3. Install

```bash
S="<HERMES_HOME>/skills"
cd <attachment-dir>
unzip -q <zip> -d "$S/<skill-name>"          # top-level SKILL.md packs
# nested-dir packs:
TMP=/tmp/skills-install && rm -rf "$TMP" && mkdir -p "$TMP"
unzip -q <zip> -d "$TMP" && mv "$TMP/<inner-dir>" "$S/"
```

Name the target dir after the zip basename (strip version/hash suffix) or the
SKILL.md `name:` field — the skill index displays directory names, so keep
them recognizable (Chinese dir names like `投资顾问` work fine).

## 4. Frontmatter repair (common with community packs)

Many third-party packs ship SKILL.md with **NO YAML frontmatter** (file starts
directly with `# Heading`). Hermes cannot index those. Detect:
`head -c 200 "$S/<skill>/SKILL.md" | od -c` — first bytes must be `- - -`.

Prepend minimal frontmatter (name = ASCII slug, description = one line drawn
from the file's own intro):

```bash
prepend() { { printf -- "$1"; cat "$2"; } > "$2.tmp" && mv "$2.tmp" "$2"; }
prepend '---
name: <ascii-slug>
description: <one-line description from content>
---

' "$S/<skill>/SKILL.md"
```

## 5. Verify every SKILL.md parses

Write the checker via write_file to a WINDOWS path (see pitfall), then:

```bash
uv run --no-project --with pyyaml python "E:/<win-path>/verify.py"
```

Checker logic: for each new dir, `glob(os.path.join(base, d, "**", "SKILL.md"),
recursive=True)`; require text starts with `---`; `yaml.safe_load` the block
between the first two `---`; print `[name] path` per OK file and list BAD ones.
Re-run after frontmatter repairs until `BAD: 0`.

## Pitfalls

- **Windows Python cannot read MSYS `/tmp`**: `/tmp/verify.py` resolves to
  `C:\tmp\...` → `can't open file`. Same family as the `/e/...` → `E:\...` rule.
  Always write the .py with write_file to an `E:/...` path and run it there.
- **Never heredoc Python into the terminal** (REPL flood — see main SKILL.md
  pitfall). write_file + `uv run --no-project --with pyyaml` instead.
- **New skills only appear in NEW sessions**: the skill index is built at
  session start; CN Desktop has no `/reload-skills`. Tell the user to open a
  fresh chat. (Also: the system-prompt `<available_skills>` list is from the
  current session's snapshot — newly installed skills won't show there either.)
- Packs carry junk (`.pytest_cache/`, nested `.zip` artifacts, `.skillup-*`
  files, `.coverage`) — harmless, leave them.
- Runtime deps are NOT installed by the pack (e.g. akshare-stock needs
  `akshare`, agent-growth-tracker needs `python-dateutil`,
  news-aggregator-skill has `requirements.txt`). List them in the final report
  and install on first use, not during the batch.
