#!/usr/bin/env python3
"""Enhanced repository validator for the Hermes Environment Check skill.

Run locally with:
    uv run --no-project --with pyyaml python scripts/validate-repo.py
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

import yaml


def collect_text_references(text: str) -> set[str]:
    return set(m.group(1) for m in re.finditer(r"references/([A-Za-z0-9_\-]+\.md)", text))


def collect_anchor_references(text: str) -> dict[str, set[str]]:
    """Collect `references/file.md#anchor` references: {file: {anchor, ...}}."""
    result: dict[str, set[str]] = {}
    for m in re.finditer(r"references/([A-Za-z0-9_\-]+\.md)#([A-Za-z0-9_\-]+)", text):
        result.setdefault(m.group(1), set()).add(m.group(2))
    return result


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    issues: list[str] = []

    # 1. Required files
    for req in ["SKILL.md", "README.md", "LICENSE", "SECURITY.md", "CHANGELOG.md"]:
        if not (root / req).is_file():
            issues.append(f"Missing required file: {req}")

    # 2. SKILL.md frontmatter
    skill_path = root / "SKILL.md"
    skill_text = skill_path.read_text(encoding="utf-8")
    if not skill_text.startswith("---"):
        issues.append("SKILL.md missing frontmatter")
    else:
        try:
            fm = yaml.safe_load(skill_text.split("---", 2)[1])
            for key in ["name", "description", "version", "author", "license", "platforms"]:
                if key not in fm:
                    issues.append(f"SKILL.md frontmatter missing '{key}'")
        except Exception as exc:
            issues.append(f"SKILL.md frontmatter YAML parse error: {exc}")

    # 3. Reference files
    refs_dir = root / "references"
    ref_files = set(p.name for p in refs_dir.glob("*.md")) if refs_dir.is_dir() else set()

    # 4. Broken links (CHANGELOG.md exempt: it documents past history and may
    # reference files renamed/removed later)
    all_texts = {p: p.read_text(encoding="utf-8", errors="ignore") for p in root.rglob("*.md")}
    referenced: set[str] = set()
    for path, text in all_texts.items():
        if path.name == "CHANGELOG.md":
            continue
        refs_in_text = collect_text_references(text)
        for ref in refs_in_text:
            referenced.add(ref)
            if ref not in ref_files:
                issues.append(f"Broken reference in {path.relative_to(root)}: references/{ref}")

    # 4b. Anchor-level references (references/file.md#anchor): the anchor must
    # exist as a heading in the target file. CHANGELOG.md documents past history
    # and may reference files renamed/removed later, so it is exempt.
    for path, text in all_texts.items():
        if path.name == "CHANGELOG.md":
            continue
        for ref_file, anchors in collect_anchor_references(text).items():
            if ref_file not in ref_files:
                issues.append(
                    f"Anchor reference to missing file in {path.relative_to(root)}: references/{ref_file}"
                )
                continue
            target_text = (refs_dir / ref_file).read_text(encoding="utf-8", errors="ignore")
            headings = set(re.findall(r"^#+\s+(.+?)\s*$", target_text, re.MULTILINE))
            for anchor in anchors:
                if anchor not in headings:
                    issues.append(
                        f"Missing anchor #{anchor} in references/{ref_file} "
                        f"(referenced by {path.relative_to(root)})"
                    )

    # 5. Zombie references (not referenced by SKILL.md or another reference)
    skill_refs = collect_text_references(skill_text)
    all_refs_except_self = set()
    for path, text in all_texts.items():
        if path.name == "SKILL.md":
            continue
        all_refs_except_self.update(collect_text_references(text))
    zombies = ref_files - skill_refs - all_refs_except_self
    if zombies:
        issues.append(f"Zombie references (not linked anywhere): {sorted(zombies)}")

    # 6. Every reference must have frontmatter
    for ref_name in sorted(ref_files):
        ref_path = refs_dir / ref_name
        text = ref_path.read_text(encoding="utf-8", errors="ignore")
        if not text.startswith("---"):
            issues.append(f"Reference missing frontmatter: references/{ref_name}")
        else:
            try:
                yaml.safe_load(text.split("---", 2)[1])
            except Exception as exc:
                issues.append(f"Reference frontmatter YAML error in {ref_name}: {exc}")

    # 7. Python syntax
    for py in (root / "scripts").glob("*.py"):
        try:
            compile(py.read_text(encoding="utf-8"), str(py), "exec")
        except SyntaxError as exc:
            issues.append(f"Python syntax error in {py.name}: {exc}")

    # 8. Report
    if issues:
        print("Validation FAILED")
        for issue in issues:
            print(f"  - {issue}")
        return 1

    print("Validation PASSED")
    print(f"  References: {len(ref_files)}")
    print(f"  Linked from SKILL.md: {len(skill_refs)}")
    print(f"  Zombie references: {len(zombies)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
