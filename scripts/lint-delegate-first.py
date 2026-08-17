#!/usr/bin/env python3
"""
scripts/lint-delegate-first.py — B-07 + B-02 린터 (표준 라이브러리만 사용).

Check A (B-07): `.claude/agents/*.md` frontmatter ↔ `enforce-subagent-model.cjs`의
  MODEL_PINNED_TYPES 정합성. 가장 중요한 검출 대상은 fail-open 드리프트다 —
  tier 에이전트 정의는 그대로 두고 frontmatter의 model을 제거하거나 inherit로
  바꿨는데 pinned 목록에는 이름이 잔존하는 경우, 화이트리스트가 그대로
  통과시켜 세션 모델 상속이 조용히 재개된다.

Check B (B-02): 위임 로그(기본 docs/handoff/delegation-log.md)의 마크다운 표가
  `날짜 | agent | role | model | effort | 실행경로 | 결과` 7컬럼 스키마를
  지키는지 검사한다.

이 훅(enforce-subagent-model.cjs)과 달리 이 린터는 fs를 읽는 것이 목적이므로
require/fs 금지 서약의 대상이 아니다 — 그 서약은 PreToolUse 훅 전용이다.

종료 코드: FAIL 1건 이상 → 1. WARN만 있으면 0 (--strict 지정 시 1).
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_AGENTS_DIR = REPO_ROOT / ".claude" / "agents"
DEFAULT_HOOK_PATH = REPO_ROOT / ".claude" / "hooks" / "enforce-subagent-model.cjs"
DEFAULT_LOG_PATH = REPO_ROOT / "docs" / "handoff" / "delegation-log.md"

LOG_HEADER = ["날짜", "agent", "role", "model", "effort", "실행경로", "결과"]
ALLOWED_EXEC_PATHS = {"Agent(tier)", "Agent(ad-hoc)", "Workflow agent()", "codex exec"}
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
SEPARATOR_CELL_RE = re.compile(r"^:?-+:?$")
PENDING_MARKER = "(리뷰 대기)"
MAX_PENDING = 2


class Finding:
    def __init__(self, level: str, path: Path, line: Optional[int], message: str):
        self.level = level  # "FAIL" | "WARN"
        self.path = path
        self.line = line
        self.message = message

    def render(self) -> str:
        loc = f"{self.path}:{self.line}" if self.line is not None else str(self.path)
        return f"[{self.level}] {loc} — {self.message}"


def _display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(Path.cwd().resolve()))
    except ValueError:
        return str(path)


# ---------------------------------------------------------------------------
# Check A — tier ↔ pinned drift
# ---------------------------------------------------------------------------

def parse_agent_frontmatter(path: Path) -> Optional[dict]:
    """Simple line parser for `key: value` frontmatter — no YAML lib.

    Returns a dict of key -> (value, line_no) or None if the file has no
    frontmatter fence at the top.
    """
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    fields: dict = {}
    for i in range(1, len(lines)):
        stripped = lines[i].strip()
        if stripped == "---":
            return fields
        m = re.match(r"^([A-Za-z_]+):\s*(.*)$", lines[i])
        if m:
            key = m.group(1)
            value = m.group(2).strip().strip('"').strip("'")
            fields[key] = (value, i + 1)  # 1-indexed line number
    return fields  # unterminated frontmatter — still return what we parsed


def extract_pinned_types(hook_path: Path):
    """Extract (name, line_no) pairs from the MODEL_PINNED_TYPES Set literal."""
    lines = hook_path.read_text(encoding="utf-8").splitlines()
    entries = []
    in_block = False
    for i, line in enumerate(lines, start=1):
        if not in_block:
            if "MODEL_PINNED_TYPES" in line and "new Set([" in line:
                in_block = True
            continue
        stripped = line.strip()
        if stripped.startswith("]);"):
            break
        # 실제 배열 항목만 스캔 대상으로 삼는다 — `//` 라인 주석 안의 따옴표
        # (예: 주석 문장에 "훅 공급망 고지"처럼 한국어 인용부호가 들어간 경우)를
        # Set 항목으로 오인하지 않도록, 코드 스캔 전에 트레일링 주석을 잘라낸다.
        code_part = line.split("//", 1)[0]
        for m in re.finditer(r'["\']([^"\']+)["\']', code_part):
            entries.append((m.group(1), i))
    return entries


def check_a(agents_dir: Path, hook_path: Path) -> list:
    findings: list = []

    if not agents_dir.is_dir():
        findings.append(Finding("FAIL", agents_dir, None,
                                 "agents 디렉터리를 찾을 수 없음 — Check A 중단"))
        return findings
    if not hook_path.is_file():
        findings.append(Finding("FAIL", hook_path, None,
                                 "훅 파일을 찾을 수 없음 — Check A 중단"))
        return findings

    agent_files = sorted(agents_dir.glob("*.md"))
    pinned_entries = extract_pinned_types(hook_path)

    # 비공허성 자기검사 — 0건 매칭을 "통과"로 보고하지 않는다.
    if not agent_files:
        findings.append(Finding("FAIL", agents_dir, None,
                                 "agents 파일을 하나도 찾지 못함 — 비공허성 자기검사 실패, Check A 중단"))
        return findings
    if not pinned_entries:
        findings.append(Finding("FAIL", hook_path, None,
                                 "MODEL_PINNED_TYPES에서 항목을 하나도 파싱하지 못함 — 비공허성 자기검사 실패, Check A 중단"))
        return findings

    agent_stems = {p.stem for p in agent_files}
    pinned_names_seen = set()

    for name, line_no in pinned_entries:
        if ":" in name:
            # 네임스페이스 항목 — 이 레포 밖 정의, 검사 대상 제외.
            continue
        pinned_names_seen.add(name)
        agent_file = agents_dir / f"{name}.md"
        if not agent_file.exists():
            findings.append(Finding(
                "WARN", hook_path, line_no,
                f"pinned 이름 '{name}'에 대응하는 agents 파일이 {agents_dir}에 없음 "
                f"(다른 프로젝트/전역 정의일 수 있음, 이 레포에서는 확인 불가)"))
            continue

        fm = parse_agent_frontmatter(agent_file)
        if fm is None:
            findings.append(Finding(
                "FAIL", agent_file, 1,
                f"frontmatter(--- 펜스)를 찾을 수 없음 — pinned 이름 '{name}'의 model 상태를 판정 불가"))
            continue

        model_entry = fm.get("model")
        if model_entry is None or model_entry[0].lower() == "inherit":
            anchor_line = model_entry[1] if model_entry else 1
            reason = "model 필드 없음" if model_entry is None else "model: inherit"
            findings.append(Finding(
                "FAIL", agent_file, anchor_line,
                f"FAIL-OPEN: pinned 이름 '{name}'의 정의가 {reason} 상태인데 "
                f"훅({hook_path}:{line_no})의 pinned 목록엔 여전히 남아 있음 — "
                f"화이트리스트가 세션 모델 상속을 그대로 통과시킴"))

        effort_entry = fm.get("effort")
        if model_entry is not None and effort_entry is None:
            findings.append(Finding(
                "WARN", agent_file, model_entry[1],
                f"'{name}' 정의에 model은 있으나 effort가 없음 — tier 계약상 둘 다 있어야 함"))

    for agent_file in agent_files:
        name = agent_file.stem
        if name not in pinned_names_seen:
            findings.append(Finding(
                "WARN", agent_file, None,
                f"'{name}'이 agents/에 있지만 훅 pinned 목록엔 없음 "
                f"(fail-closed라 안전하지만 의도된 것인지 확인 필요)"))

    return findings


# ---------------------------------------------------------------------------
# Check B — delegation log schema
# ---------------------------------------------------------------------------

def split_row(line: str) -> list:
    cells = line.strip()
    if cells.startswith("|"):
        cells = cells[1:]
    if cells.endswith("|"):
        cells = cells[:-1]
    return [c.strip() for c in cells.split("|")]


def is_separator_row(cells: list) -> bool:
    return len(cells) > 0 and all(SEPARATOR_CELL_RE.match(c) for c in cells)


def check_b(log_path: Path) -> list:
    findings: list = []

    if not log_path.is_file():
        findings.append(Finding("FAIL", log_path, None,
                                 "위임 로그 파일을 찾을 수 없음 — Check B 중단"))
        return findings

    lines = log_path.read_text(encoding="utf-8").splitlines()

    header_idx = None
    for i, line in enumerate(lines):
        if line.strip().startswith("|") and "날짜" in line:
            header_idx = i
            break

    if header_idx is None:
        findings.append(Finding("FAIL", log_path, None,
                                 "마크다운 표 헤더('날짜' 포함하는 | 행)를 찾지 못함 — Check B 중단"))
        return findings

    header_cells = split_row(lines[header_idx])
    if header_cells != LOG_HEADER:
        findings.append(Finding(
            "FAIL", log_path, header_idx + 1,
            f"헤더가 {LOG_HEADER}가 아님 (실제: {header_cells})"))

    # 헤더 다음 줄(구분선)은 검증하지 않고 건너뛴다.
    row_start = header_idx + 2
    data_rows = []
    for i in range(row_start, len(lines)):
        line = lines[i]
        if not line.strip().startswith("|"):
            break
        cells = split_row(line)
        if is_separator_row(cells):
            continue
        data_rows.append((i + 1, cells))

    if not data_rows:
        findings.append(Finding("WARN", log_path, None, "데이터 행이 0건 — 빈 로그"))
        return findings

    pending_lines = []
    for line_no, cells in data_rows:
        if len(cells) != 7:
            findings.append(Finding(
                "FAIL", log_path, line_no,
                f"행이 {len(cells)}컬럼임 (7컬럼 필요: {LOG_HEADER})"))
            continue

        date, agent, role, model, effort, exec_path, result = cells

        empty_cols = [name for name, val in zip(LOG_HEADER, cells) if val == ""]
        if empty_cols:
            findings.append(Finding(
                "FAIL", log_path, line_no,
                f"빈 셀 있음: {empty_cols}"))

        if date and not DATE_RE.match(date):
            findings.append(Finding(
                "FAIL", log_path, line_no,
                f"날짜 형식이 YYYY-MM-DD가 아님: '{date}'"))

        if exec_path and exec_path not in ALLOWED_EXEC_PATHS:
            findings.append(Finding(
                "FAIL", log_path, line_no,
                f"실행경로 '{exec_path}'가 허용 집합 {sorted(ALLOWED_EXEC_PATHS)}에 없음"))

        if result.strip() == PENDING_MARKER:
            pending_lines.append(line_no)

    if len(pending_lines) > MAX_PENDING:
        findings.append(Finding(
            "WARN", log_path, None,
            f"'{PENDING_MARKER}'로 남은 행이 {len(pending_lines)}개 (>{MAX_PENDING}) — "
            f"라인 {pending_lines} — 오래 열린 위임이 쌓이고 있음"))

    return findings


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        prog="lint-delegate-first.py",
        description="B-07(tier↔훅 pinned 드리프트) + B-02(위임 로그 스키마) 린터",
    )
    parser.add_argument("--agents-dir", type=Path, default=DEFAULT_AGENTS_DIR,
                         help=f"tier 에이전트 정의 디렉터리 (기본: {DEFAULT_AGENTS_DIR})")
    parser.add_argument("--hook-path", type=Path, default=DEFAULT_HOOK_PATH,
                         help=f"enforce-subagent-model.cjs 경로 (기본: {DEFAULT_HOOK_PATH})")
    parser.add_argument("--log-path", type=Path, default=DEFAULT_LOG_PATH,
                         help=f"위임 로그 경로 (기본: {DEFAULT_LOG_PATH}) — 프로젝트 파라미터")
    parser.add_argument("--strict", action="store_true",
                         help="WARN이 하나라도 있으면 종료 코드 1")
    args = parser.parse_args()

    findings_a = check_a(args.agents_dir, args.hook_path)
    findings_b = check_b(args.log_path)

    print("=== Check A: tier ↔ hook pinned drift (B-07) ===")
    if findings_a:
        for f in findings_a:
            print(f.render())
    else:
        print("(위반 없음)")

    print()
    print("=== Check B: delegation log schema (B-02) ===")
    if findings_b:
        for f in findings_b:
            print(f.render())
    else:
        print("(위반 없음)")

    all_findings = findings_a + findings_b
    fail_count = sum(1 for f in all_findings if f.level == "FAIL")
    warn_count = sum(1 for f in all_findings if f.level == "WARN")

    print()
    if fail_count:
        status = f"FAIL {fail_count} (WARN {warn_count})"
    elif warn_count:
        status = f"WARN {warn_count}"
    else:
        status = "PASS"
    print(f"=== Summary: {status} ===")

    if fail_count:
        return 1
    if warn_count and args.strict:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
