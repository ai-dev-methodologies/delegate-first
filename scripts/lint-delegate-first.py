#!/usr/bin/env python3
"""
scripts/lint-delegate-first.py — B-07 + B-02 린터 (표준 라이브러리만 사용).

Check A (B-07 + B-09 + B-11): `.claude/agents/*.md` frontmatter ↔
  `enforce-subagent-model.cjs`의 MODEL_PINNED_TYPES 정합성. 가장 중요한 검출
  대상은 fail-open 드리프트다 — tier 에이전트 정의는 그대로 두고
  frontmatter의 model을 제거하거나 inherit로 바꿨는데 pinned 목록에는 이름이
  잔존하는 경우, 화이트리스트가 그대로 통과시켜 세션 모델 상속이 조용히
  재개된다. "model 없음"과 동등한 값(빈 문자열/inherit/null/~/none)도 모두
  fail-open으로 취급한다 — 이 레포의 훅(enforce-subagent-model.cjs)이
  `typeof model === "string" && model.trim()`로 공백 문자열도 미지정으로
  취급하는 것과 규약을 맞춘 것이다.

  B-09 보강: MODEL_PINNED_TYPES Set 항목은 "정적 문자열 리터럴 하나"만
  허용한다 — 문자열 연결(`"executor-" + "high"`), 템플릿 리터럴 보간
  (`` `executor-${x}` ``), 식별자, 함수 호출 등 정적으로 해석 불가한 형태가
  섞여 있으면 FAIL로 표면화한다(정규식으로 JS를 완전히 파싱하려는 시도는
  하지 않는다 — "정적 리터럴이 아니면 사람이 확인해야 한다"는 신호만 낸다).

  B-11 보강: 훅의 `TIER_EXPECTED_MODEL`(tier → 기대 model 정적 map)도 같은
  방식(정적 리터럴만 허용)으로 파싱하고, MODEL_PINNED_TYPES Set 목록 ↔
  TIER_EXPECTED_MODEL map ↔ agents/*.md frontmatter 3자가 서로 어긋나면
  FAIL로 표면화한다(예: pinned에는 있는 tier가 map에 없거나, map의 값이
  frontmatter model과 다른 경우 — 이건 훅이 조용히 잘못된 값으로 강등/승급을
  차단하거나 허용하게 만드는 새로운 드리프트 축이다).

Check B (B-02): 위임 로그(기본 docs/handoff/delegation-log.md)의 마크다운 표가
  `날짜 | agent | role | model | effort | 실행경로 | 결과` 7컬럼 스키마를
  지키는지 검사한다. 표 스캔은 첫 데이터 행부터 파일 끝까지 진행하며(빈 줄은
  건너뛰고, 파일 안에 표가 여러 개면 각각 별도로 검증한다), 셀 안의 이스케이프
  파이프(`\\|`)는 컬럼 구분자로 취급하지 않는다.

이 훅(enforce-subagent-model.cjs)과 달리 이 린터는 fs를 읽는 것이 목적이므로
require/fs 금지 서약의 대상이 아니다 — 그 서약은 PreToolUse 훅 전용이다.

종료 코드: FAIL 1건 이상 → 1. WARN만 있으면 0 (--strict 지정 시 1). INFO는
알려진 예외를 "무시했다"는 사실을 보여주기 위한 표시일 뿐, 종료 코드에
영향을 주지 않는다.
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime
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

# "model 없음"과 의미상 동일한 값들 — 대소문자 무시, 앞뒤 공백/따옴표 무시하고
# 비교한다. 훅 자신의 `typeof model === "string" && model.trim()` 규약과
# 맞춘 것 — 공백 문자열도 미지정으로 취급한다.
FAIL_OPEN_MODEL_VALUES = {"", "inherit", "null", "~", "none"}

# pinned 목록에는 있지만 이 레포 agents/ 에 정의 파일이 존재하는 것이
# 원리상 불가능한 항목들 — Claude Code 빌트인 타입 등. 사유를 항목마다
# 주석으로 남긴다.
KNOWN_EXTERNAL_PINNED = {
    # 빌트인 타입: Claude Code가 자체 제공하며 `.claude/agents/`에 정의
    # 파일이 존재하지 않는 것이 정상이다(영원히 생기지 않는다).
    "statusline-setup",
}


class ReadError(Exception):
    """파일 읽기 실패(인코딩/권한/기타 OS 오류)를 사람이 읽는 메시지로 감싼다."""


def read_text_safe(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError as e:
        raise ReadError(f"인코딩 오류로 읽기 실패: {path} — {e}") from e
    except PermissionError as e:
        raise ReadError(f"권한 오류로 읽기 실패: {path} — {e}") from e
    except OSError as e:
        raise ReadError(f"파일 읽기 실패: {path} — {e}") from e


class Finding:
    def __init__(self, level: str, path: Path, line: Optional[int], message: str):
        self.level = level  # "FAIL" | "WARN" | "INFO"
        self.path = path
        self.line = line
        self.message = message

    def render(self) -> str:
        loc = f"{self.path}:{self.line}" if self.line is not None else str(self.path)
        return f"[{self.level}] {loc} — {self.message}"


# ---------------------------------------------------------------------------
# Check A — tier ↔ pinned drift
# ---------------------------------------------------------------------------

def parse_agent_frontmatter(path: Path) -> Optional[dict]:
    """Simple line parser for `key: value` frontmatter — no YAML lib.

    Returns a dict of key -> (value, line_no) or None if the file has no
    frontmatter fence at the top, or the fence is never closed (F6: 닫는
    `---`가 없는 파일은 파싱 성공으로 보지 않는다 — 그렇지 않으면 본문 산문의
    `key: value` 형태 줄을 frontmatter 필드로 오인할 수 있다).
    """
    content = read_text_safe(path)
    lines = content.splitlines()
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
    # 닫는 --- 펜스를 끝내 찾지 못함 — 파싱 실패로 간주.
    return None


def classify_model_value(model_entry) -> tuple[bool, str]:
    """Returns (is_fail_open, reason). model_entry is (value, line_no) or None."""
    if model_entry is None:
        return True, "model 필드 없음"
    raw = model_entry[0]
    normalized = raw.strip().lower()
    if normalized in FAIL_OPEN_MODEL_VALUES:
        shown = raw if raw else "(빈 값)"
        return True, f"model: {shown}"
    return False, ""


def build_name_index(agent_files: list, findings: list) -> dict:
    """agents/*.md를 frontmatter `name` 필드로 색인한다.

    이 레포 규약: frontmatter `name`은 파일 stem과 일치해야 한다. 불일치·
    부재는 FAIL이며, 그런 파일은 색인에서 제외된다(대조 키로 신뢰할 수 없음).
    """
    name_index: dict = {}
    for agent_file in agent_files:
        stem = agent_file.stem
        try:
            fm = parse_agent_frontmatter(agent_file)
        except ReadError as e:
            findings.append(Finding("FAIL", agent_file, None, str(e)))
            continue
        if fm is None:
            findings.append(Finding(
                "FAIL", agent_file, 1,
                "frontmatter(닫는 --- 포함)를 찾을 수 없음 — name 규약 판정 불가"))
            continue
        name_entry = fm.get("name")
        if name_entry is None:
            findings.append(Finding(
                "FAIL", agent_file, 1,
                "frontmatter에 name 필드가 없음 — 이 레포 규약(파일 stem과 name 일치) 위반"))
            continue
        name_val, name_line = name_entry
        if name_val != stem:
            findings.append(Finding(
                "FAIL", agent_file, name_line,
                f"frontmatter name '{name_val}'이 파일명 stem '{stem}'과 다름 — "
                f"이 레포 규약(둘이 일치해야 함) 위반"))
            continue
        name_index[name_val] = (agent_file, fm)
    return name_index


SET_START_RE = re.compile(r"new\s+Set\(\s*\[")
MAP_START_RE = re.compile(r"TIER_EXPECTED_MODEL\s*=\s*\{")
# C7: 종결자는 세미콜론 유무와 무관하게 인식한다(`]);`와 `])`, `};`와 `}`
# 모두). 예전엔 리터럴 문자열 "]);"/"};" 서브스트링만 찾았는데, Prettier
# `semi:false` 스타일(세미콜론 없음)로 포매팅되면 이 레포의 실제 포매팅과
# 달라져 종결자를 영원히 못 찾고 파일 나머지 전체를 항목으로 오추출해
# FAIL 폭포를 냈다(실측). 세미콜론은 선택적으로만 소비한다.
CLOSE_SET_RE = re.compile(r"\]\s*\)\s*;?")
CLOSE_MAP_RE = re.compile(r"\}\s*;?")
STRING_LITERAL_RE = re.compile(r"""(['"`])((?:(?!\1).)*)\1""")
IDENT_RE = re.compile(r"^[A-Za-z0-9:_.-]+$")
# key(따옴표 리터럴): value(나머지 전부) — value는 이미 top-level comma로
# 분리된 조각이므로 콜론 뒤 텍스트 전체가 value 후보다.
KV_SPLIT_RE = re.compile(r"""^((?:'[^']*'|"[^"]*"|`[^`]*`))\s*:\s*(.*)$""")


def _strip_comments_stateful(line: str, in_block_comment: bool) -> tuple[str, bool]:
    """한 줄에서 `//`와 `/* ... */` 주석을 제거한다(블록 주석은 줄 경계를
    넘길 수 있으므로 in_block_comment 상태를 유지한다)."""
    result = []
    i = 0
    n = len(line)
    while i < n:
        if in_block_comment:
            end = line.find("*/", i)
            if end == -1:
                break
            in_block_comment = False
            i = end + 2
            continue
        two = line[i:i + 2]
        if two == "/*":
            in_block_comment = True
            i += 2
            continue
        if two == "//":
            break
        result.append(line[i])
        i += 1
    return "".join(result), in_block_comment


def split_top_level_commas(text: str) -> list:
    """텍스트를 따옴표(', ", `) 밖의 콤마 기준으로 분할한다.

    Set([...])나 {...} 안의 항목이 한 줄에 여럿(`"a", "b",`) 있어도, 문자열
    리터럴 내부의 콤마는 구분자로 취급하지 않는다. 이스케이프(`\\`)는 따옴표
    안에서만 다음 한 글자를 그대로 통과시킨다(문자열 종료 오판 방지).
    """
    items: list = []
    current: list = []
    quote: Optional[str] = None
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if quote:
            current.append(ch)
            if ch == "\\" and i + 1 < n:
                current.append(text[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"', '`'):
            quote = ch
            current.append(ch)
            i += 1
            continue
        if ch == ",":
            items.append("".join(current))
            current = []
            i += 1
            continue
        current.append(ch)
        i += 1
    if current:
        items.append("".join(current))
    return items


def classify_static_literal(item: str) -> tuple:
    """item(이미 앞뒤 공백 제거됨)이 "정적 문자열 리터럴 하나"인지 판정한다.

    B-09: 이 린터는 실제 JS 파서가 아니다(정규식으로 JS를 완전히 파싱하려는
    시도는 지는 싸움이다) — 그래서 "정적 리터럴이 아니면 FAIL로 표면화해
    사람이 확인하게 한다"는 좁고 안전한 계약만 구현한다. 연결 연산자
    (`"a" + "b"`), 식별자, 함수 호출처럼 STRING_LITERAL_RE 전체 일치에
    실패하는 형태는 전부 여기서 걸린다. 백틱 리터럴은 전체 일치에는 성공할
    수 있어도(백틱이 내부에 없으면 그 자체로 하나의 리터럴처럼 보이므로)
    `${...}` 보간이 포함돼 있으면 별도로 다시 FAIL 처리한다.

    Returns (value, error) — 성공 시 (문자열, None), 실패 시 (None, 사유).
    """
    m = STRING_LITERAL_RE.fullmatch(item)
    if not m:
        return None, f"정적 문자열 리터럴 하나가 아님(연결·식별자·함수호출 등으로 의심됨): {item!r}"
    quote, inner = m.group(1), m.group(2)
    if quote == "`" and "${" in inner:
        return None, f"템플릿 리터럴 보간(${{...}}) 포함, 정적 파싱 불가: {item!r}"
    return inner, None


def _scan_entries(text: str, line_no: int, entries: list, findings: list, hook_path: Path) -> None:
    """MODEL_PINNED_TYPES Set 블록의 한 줄(또는 종결자 앞 조각)을 항목으로
    분해한다. B-09: 항목 전체가 "정적 문자열 리터럴 하나"가 아니면(문자열
    연결·템플릿 보간·식별자·함수 호출 등) FAIL — 예전엔 STRING_LITERAL_RE를
    finditer로 돌려 조각난 리터럴(`"executor-" + "high"`의 "executor-"와
    "high")을 각각 별개의 유효 항목으로 오추출했다(B-09 실측 결함)."""
    for raw_item in split_top_level_commas(text):
        item = raw_item.strip()
        if not item:
            continue
        value, err = classify_static_literal(item)
        if err:
            findings.append(Finding(
                "FAIL", hook_path, line_no,
                f"MODEL_PINNED_TYPES 항목이 {err} — 이 린터는 정적 목록만 "
                f"검증할 수 있으므로 사람이 직접 확인해야 함"))
            continue
        if not IDENT_RE.match(value):
            findings.append(Finding(
                "FAIL", hook_path, line_no,
                f"MODEL_PINNED_TYPES 항목 이름이 예상 문자 집합([A-Za-z0-9:_.-])을 "
                f"벗어남: {value!r} — 파싱 폭주(Set 리터럴 종결자 누락 등) 의심, "
                f"조용히 통과시키지 않음"))
            continue
        entries.append((value, line_no))


def _scan_map_entries(text: str, line_no: int, entries: list, findings: list, hook_path: Path) -> None:
    """TIER_EXPECTED_MODEL 객체 블록의 한 줄(또는 종결자 앞 조각)을
    `key: value` 항목으로 분해한다(B-11/B-09). key와 value 모두 정적 문자열
    리터럴 하나여야 한다 — 계산된 프로퍼티(`[expr]: ...`), 식별자 키,
    연결·보간된 값은 전부 FAIL로 표면화한다."""
    for raw_item in split_top_level_commas(text):
        item = raw_item.strip()
        if not item:
            continue
        m = KV_SPLIT_RE.match(item)
        if not m:
            findings.append(Finding(
                "FAIL", hook_path, line_no,
                f"TIER_EXPECTED_MODEL 항목을 'key: value' 형태(key는 정적 문자열 "
                f"리터럴)로 정적 파싱할 수 없음 — 계산된 키·비-리터럴 형태로 "
                f"의심됨: {item!r}"))
            continue
        key_raw, value_raw = m.group(1), m.group(2).strip()
        key_value, key_err = classify_static_literal(key_raw)
        if key_err:
            findings.append(Finding(
                "FAIL", hook_path, line_no,
                f"TIER_EXPECTED_MODEL 키가 {key_err}"))
            continue
        if not IDENT_RE.match(key_value):
            findings.append(Finding(
                "FAIL", hook_path, line_no,
                f"TIER_EXPECTED_MODEL 키 이름이 예상 문자 집합([A-Za-z0-9:_.-])을 "
                f"벗어남: {key_value!r}"))
            continue
        val_value, val_err = classify_static_literal(value_raw)
        if val_err:
            findings.append(Finding(
                "FAIL", hook_path, line_no,
                f"TIER_EXPECTED_MODEL['{key_value}'] 값이 {val_err}"))
            continue
        entries.append((key_value, val_value, line_no))


def extract_pinned_types(hook_path: Path) -> tuple[list, list]:
    """MODEL_PINNED_TYPES Set 리터럴에서 (name, line_no) 목록을 추출한다.

    F3: `in_block = True`로 진입한 바로 그 줄도 반드시 스캔한다 — 이전에는
    진입 직후 `continue`로 그 줄 자체를 건너뛰어, `new Set([...]);`가 한
    줄로 포매팅되면 종결자(`]);`)를 영영 못 찾고 파일 나머지 전체를 항목으로
    긁어 들였다(포매터 한 번이면 재현). 이제 진입한 줄의 나머지 부분부터
    바로 스캔하고, 같은 줄에 종결자가 있으면 그 자리에서 블록을 닫는다.
    """
    content = read_text_safe(hook_path)
    lines = content.splitlines()
    entries: list = []
    findings: list = []
    in_block = False
    in_block_comment = False
    closed = False

    for i, raw_line in enumerate(lines, start=1):
        code_line, in_block_comment = _strip_comments_stateful(raw_line, in_block_comment)

        if not in_block:
            if "MODEL_PINNED_TYPES" in code_line and SET_START_RE.search(code_line):
                in_block = True
                start_m = SET_START_RE.search(code_line)
                code_line = code_line[start_m.end():]
            else:
                continue

        close_m = CLOSE_SET_RE.search(code_line)
        if close_m:
            _scan_entries(code_line[:close_m.start()], i, entries, findings, hook_path)
            in_block = False
            closed = True
            break
        _scan_entries(code_line, i, entries, findings, hook_path)

    if in_block and not closed:
        findings.append(Finding(
            "FAIL", hook_path, None,
            "MODEL_PINNED_TYPES Set 블록이 닫히지 않았다 — 파일 끝까지 "
            "']'+')' 종결자(세미콜론 유무 무관: '])' 또는 ']);')를 찾지 못함 — 파싱 실패"))

    return entries, findings


def extract_tier_expected_model(hook_path: Path) -> tuple:
    """TIER_EXPECTED_MODEL 객체 리터럴에서 (key, value, line_no) 목록을
    추출한다(B-11). extract_pinned_types와 동일한 구조 — 진입한 줄의 나머지
    부분부터 바로 스캔하고(F3와 같은 종류의 함정 방지), 같은 줄에 종결자
    (`};`)가 있으면 그 자리에서 블록을 닫는다.

    한계: 항목이 여러 줄에 걸쳐 쓰이면(예: key와 value가 다른 줄) 인식하지
    못한다 — 이 레포의 실제 포매팅(한 항목 = 한 줄)을 전제로 한다.
    """
    content = read_text_safe(hook_path)
    lines = content.splitlines()
    entries: list = []
    findings: list = []
    in_block = False
    in_block_comment = False
    closed = False

    for i, raw_line in enumerate(lines, start=1):
        code_line, in_block_comment = _strip_comments_stateful(raw_line, in_block_comment)

        if not in_block:
            if "TIER_EXPECTED_MODEL" in code_line and MAP_START_RE.search(code_line):
                in_block = True
                start_m = MAP_START_RE.search(code_line)
                code_line = code_line[start_m.end():]
            else:
                continue

        close_m = CLOSE_MAP_RE.search(code_line)
        if close_m:
            _scan_map_entries(code_line[:close_m.start()], i, entries, findings, hook_path)
            in_block = False
            closed = True
            break
        _scan_map_entries(code_line, i, entries, findings, hook_path)

    if in_block and not closed:
        findings.append(Finding(
            "FAIL", hook_path, None,
            "TIER_EXPECTED_MODEL 객체 블록이 닫히지 않았다 — 파일 끝까지 "
            "'}' 종결자(세미콜론 유무 무관: '}' 또는 '};')를 찾지 못함 — 파싱 실패"))

    return entries, findings


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

    # 비공허성 자기검사 — 0건 매칭을 "통과"로 보고하지 않는다.
    if not agent_files:
        findings.append(Finding("FAIL", agents_dir, None,
                                 "agents 파일을 하나도 찾지 못함 — 비공허성 자기검사 실패, Check A 중단"))
        return findings

    try:
        pinned_entries, extract_findings = extract_pinned_types(hook_path)
    except ReadError as e:
        findings.append(Finding("FAIL", hook_path, None, str(e)))
        return findings
    findings.extend(extract_findings)

    if not pinned_entries:
        findings.append(Finding("FAIL", hook_path, None,
                                 "MODEL_PINNED_TYPES에서 유효 항목을 하나도 파싱하지 못함 — "
                                 "비공허성 자기검사 실패, Check A 중단"))
        return findings

    name_index = build_name_index(agent_files, findings)
    pinned_names_seen = set()

    for name, line_no in pinned_entries:
        if ":" in name:
            # 네임스페이스 항목 — 이 레포 밖 정의, 검사 대상 제외.
            continue
        pinned_names_seen.add(name)

        if name in KNOWN_EXTERNAL_PINNED:
            findings.append(Finding(
                "INFO", hook_path, line_no,
                f"pinned 이름 '{name}'은 알려진 외부/빌트인 예외로 무시함 — "
                f"Claude Code 빌트인 타입이라 이 레포 {agents_dir}에 정의 파일이 "
                f"존재하지 않는 것이 정상"))
            continue

        entry = name_index.get(name)
        if entry is None:
            findings.append(Finding(
                "WARN", hook_path, line_no,
                f"pinned 이름 '{name}'에 대응하는(frontmatter name 필드 일치) agents 파일이 "
                f"{agents_dir}에 없음 (다른 프로젝트/전역 정의이거나, 위에서 name/stem "
                f"불일치로 이미 FAIL 처리됐을 수 있음)"))
            continue

        agent_file, fm = entry
        model_entry = fm.get("model")
        is_fail_open, reason = classify_model_value(model_entry)
        if is_fail_open:
            anchor_line = model_entry[1] if model_entry else 1
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

    for name_val, (agent_file, _fm) in name_index.items():
        if name_val not in pinned_names_seen:
            findings.append(Finding(
                "WARN", agent_file, None,
                f"'{name_val}'이 agents/에 있지만 훅 pinned 목록엔 없음 "
                f"(fail-closed라 안전하지만 의도된 것인지 확인 필요)"))

    # -----------------------------------------------------------------
    # B-11 + B-09: TIER_EXPECTED_MODEL map ↔ MODEL_PINNED_TYPES Set ↔
    # agents/*.md frontmatter 3자 정합성. 이 map은 훅이 tier의 model 값
    # 불일치(조용한 강등/승급)를 차단할 때 쓰는 진실의 원천이므로, 여기서
    # 드리프트되면 훅이 잘못된 값으로 정상 호출을 차단하거나(map이 stale)
    # 반대로 실제 강등을 놓칠 수 있다(map 자체가 frontmatter와 다른 값으로
    # 굳어 있으면 그 값과의 "일치"만 확인하므로 진짜 fail-open과는 다르지만
    # 여전히 훅의 판정 기준 자체가 틀린 상태다).
    try:
        map_entries, map_extract_findings = extract_tier_expected_model(hook_path)
    except ReadError as e:
        findings.append(Finding("FAIL", hook_path, None, str(e)))
        return findings
    findings.extend(map_extract_findings)

    if not map_entries:
        findings.append(Finding(
            "FAIL", hook_path, None,
            "TIER_EXPECTED_MODEL에서 유효 항목을 하나도 파싱하지 못함 — "
            "비공허성 자기검사 실패, map↔pinned↔frontmatter 교차검사 중단"))
        return findings

    map_dict: dict = {}
    for key, value, line_no in map_entries:
        if key in map_dict:
            findings.append(Finding(
                "FAIL", hook_path, line_no,
                f"TIER_EXPECTED_MODEL에 '{key}' 항목이 중복으로 존재함"))
            continue
        map_dict[key] = (value, line_no)

    # 정방향: pinned Set에 있고 이 레포 agents/에 정의 파일이 있는(=진짜
    # tier 에이전트) 이름은 반드시 map에도 있어야 한다.
    for name in sorted(pinned_names_seen):
        if name in KNOWN_EXTERNAL_PINNED:
            continue  # 빌트인 — map 대상 아님(이미 위에서 INFO 처리됨).
        entry = name_index.get(name)
        if entry is None:
            continue  # 이 레포 밖 정의 — 이미 위에서 WARN 처리됨.
        if name not in map_dict:
            findings.append(Finding(
                "FAIL", hook_path, None,
                f"pinned 목록의 tier '{name}'이 TIER_EXPECTED_MODEL map에 없음 — "
                f"이 tier에 대한 B-11 값 검증(조용한 강등/승급 차단)이 조용히 "
                f"미적용됨"))

    # 역방향: map에 있는 이름은 pinned Set에도, agents/ 정의 파일에도 있어야
    # 하고, map 값은 그 정의의 frontmatter model과 일치해야 한다.
    for name, (value, line_no) in map_dict.items():
        if name not in pinned_names_seen:
            findings.append(Finding(
                "FAIL", hook_path, line_no,
                f"TIER_EXPECTED_MODEL['{name}']이 MODEL_PINNED_TYPES Set 목록에 없음 — "
                f"map과 pinned 목록이 서로 어긋남"))

        entry = name_index.get(name)
        if entry is None:
            findings.append(Finding(
                "FAIL", hook_path, line_no,
                f"TIER_EXPECTED_MODEL['{name}']에 대응하는(frontmatter name 필드 "
                f"일치) agents 파일이 {agents_dir}에 없음"))
            continue

        agent_file, fm = entry
        model_entry = fm.get("model")
        is_fail_open, _reason = classify_model_value(model_entry)
        if is_fail_open:
            # 이미 위 fail-open 루프에서 이 조합에 대해 FAIL을 보고했다 —
            # 같은 근본 원인에 대한 중복 보고를 피한다.
            continue

        fm_value = model_entry[0].strip()
        if fm_value.lower() != value.strip().lower():
            findings.append(Finding(
                "FAIL", hook_path, line_no,
                f"TIER_EXPECTED_MODEL['{name}'] = {value!r}이 frontmatter model "
                f"{fm_value!r}({agent_file})과 다름 — map이 드리프트됨, 훅의 "
                f"강등/승급 차단 기준이 실제 tier 정의와 어긋나 있음"))

    return findings


# ---------------------------------------------------------------------------
# Check B — delegation log schema
# ---------------------------------------------------------------------------

CELL_SPLIT_RE = re.compile(r"(?<!\\)\|")


def split_row(line: str) -> list:
    """마크다운 표 행을 셀로 분할한다. 셀 안의 이스케이프 파이프(`\\|`)는
    컬럼 구분자로 취급하지 않는다(F6) — 분할 후 다시 `|`로 되돌린다."""
    body = line.strip()
    if body.startswith("|"):
        body = body[1:]
    if body.endswith("|"):
        body = body[:-1]
    raw_cells = CELL_SPLIT_RE.split(body)
    return [c.strip().replace("\\|", "|") for c in raw_cells]


def is_separator_row(cells: list) -> bool:
    return len(cells) > 0 and all(SEPARATOR_CELL_RE.match(c) for c in cells)


def is_valid_date(value: str) -> bool:
    """형식(YYYY-MM-DD)과 실존 여부(달력상 유효한 날짜)를 모두 검증한다
    (F6) — 정규식만으로는 `2026-13-45` 같은 값을 통과시킨다."""
    if not DATE_RE.match(value):
        return False
    try:
        datetime.strptime(value, "%Y-%m-%d")
        return True
    except ValueError:
        return False


def is_header_row(line: str) -> bool:
    """행이 위임 로그 헤더인지 판정한다.

    F1: 이전엔 행 전체에 부분문자열 "날짜"가 있으면 헤더로 오인했다 — 정상
    7컬럼 데이터 행의 role 셀에 "날짜"라는 부분문자열이 들어가면(예: role이
    "날짜 검증 로직 추가") 그 행을 새 표 헤더로 잘못 판정해 허위 FAIL을
    냈다. 이제는 행을 컬럼으로 분할했을 때 전체가 기대 헤더 시퀀스
    (LOG_HEADER)와 정확히 일치할 때만 헤더로 판정한다 — LOG_HEADER[0]이
    "날짜"이므로 첫 셀이 정확히 "날짜"인 조건도 이 비교에 포함된다.
    """
    if not line.strip().startswith("|"):
        return False
    return split_row(line) == LOG_HEADER


def find_next_header(lines: list, start_idx: int) -> Optional[int]:
    for i in range(start_idx, len(lines)):
        if is_header_row(lines[i]):
            return i
    return None


def parse_table_at(lines: list, header_idx: int, log_path: Path, findings: list) -> tuple[int, list]:
    """header_idx에서 시작하는 표 하나를 파싱한다.

    F2: (a) 헤더 다음 줄이 실제 구분선(`|---|` 형태)인지 검증한다 — 아니면
    FAIL이고, 그 줄을 건너뛰지 않고 데이터 행 취급으로 계속 스캔한다(첫
    데이터 행이 영구 미검증되는 것을 막는다). (b) 파일 끝까지 스캔한다 —
    빈 줄은 건너뛰되(표 뒤 빈 줄 다음 append된 행도 검사 대상에 포함),
    '|'로 시작하지 않는 비어있지 않은 줄을 만나면 이 표를 닫고 반환한다
    (헤더 행을 다시 만나면 호출자가 새 표로 처리). (c) '|'를 포함하지만
    앞/뒤 파이프가 빠진 줄은 FAIL로 보고한다.

    Returns (다음 스캔 시작 인덱스, 이 표의 데이터 행 목록).

    P-2: header_idx는 항상 find_next_header()가 반환한 인덱스이고,
    find_next_header는 is_header_row()(=split_row(line) == LOG_HEADER)가 참인
    줄만 반환한다. 즉 이 함수가 호출되는 시점엔 header_cells == LOG_HEADER가
    이미 보장돼 있어 "헤더가 LOG_HEADER가 아님" 분기는 영원히 거짓이다(실측:
    20개 회귀/음성 변형에서 0회 발생). 죽은 분기이므로 제거했다 — 헤더 자체가
    깨진 경우는 이제 P-1의 "미소속 표 잔여 검사"가 잡는다(is_header_row가
    거짓이면 애초에 표로 인식되지 않아 find_next_header를 통과하지 못하므로).
    """
    n = len(lines)
    sep_idx = header_idx + 1
    sep_ok = (
        sep_idx < n
        and lines[sep_idx].strip().startswith("|")
        and is_separator_row(split_row(lines[sep_idx]))
    )
    if sep_ok:
        i = sep_idx + 1
    else:
        findings.append(Finding(
            "FAIL", log_path, min(sep_idx, n - 1) + 1 if n else header_idx + 1,
            "헤더 다음 줄이 구분선('|---|...' 형태) 형식이 아님 — "
            "구분선 없이는 첫 데이터 행이 검증 없이 넘어갈 수 있었음"))
        i = sep_idx  # 구분선으로 소비하지 않고 데이터 행 스캔으로 넘긴다.

    data_rows: list = []
    while i < n:
        raw_line = lines[i]
        stripped = raw_line.strip()
        if stripped == "":
            i += 1
            continue
        if stripped.startswith("|"):
            if is_header_row(raw_line):
                break  # 새 표 헤더 — 이 표는 여기서 닫고 호출자에게 넘긴다.
            if not stripped.endswith("|"):
                findings.append(Finding(
                    "FAIL", log_path, i + 1,
                    f"표 행이 '|'로 시작하지만 '|'로 끝나지 않음(트레일링 파이프 누락): "
                    f"{stripped!r}"))
                i += 1
                continue
            cells = split_row(raw_line)
            if is_separator_row(cells):
                i += 1
                continue
            data_rows.append((i + 1, cells))
            i += 1
            continue
        # '|'로 시작하지 않는 비어있지 않은 줄.
        if "|" in stripped:
            findings.append(Finding(
                "FAIL", log_path, i + 1,
                f"표 행처럼 보이나 '|'로 시작하지 않음(리딩 파이프 누락): {stripped!r}"))
            i += 1
            continue
        break  # 진짜 표 밖 내용 — 이 표를 닫는다.

    return i, data_rows


def check_b(log_path: Path) -> list:
    findings: list = []

    if not log_path.is_file():
        findings.append(Finding("FAIL", log_path, None,
                                 "위임 로그 파일을 찾을 수 없음 — Check B 중단"))
        return findings

    try:
        content = read_text_safe(log_path)
    except ReadError as e:
        findings.append(Finding("FAIL", log_path, None, str(e)))
        return findings

    lines = content.splitlines()
    expected_header_str = "| " + " | ".join(LOG_HEADER) + " |"

    # C-1: 판정 기준(정확한 7컬럼 헤더 전체 일치)과 메시지를 맞춘다. 예전
    # 메시지("'날짜' 포함하는 | 행")는 부분문자열 판정 시절의 잔재라, 컬럼이
    # 깨졌지만 "날짜"라는 글자는 분명히 들어있는 헤더(예: `| 날짜 | agnet | ... |`)
    # 를 보고도 "찾지 못함"이라 말해 사용자를 오도했다.
    first_header = find_next_header(lines, 0)
    if first_header is None:
        findings.append(Finding(
            "FAIL", log_path, None,
            f"유효한 마크다운 표 헤더를 찾지 못함 — 정확히 다음 7컬럼과 일치해야 함: "
            f"{expected_header_str} (헤더 오타·컬럼 누락이 흔한 원인) — Check B 중단"))
        return findings

    all_data_rows: list = []
    consumed_ranges: list = []
    scan_idx = first_header
    while True:
        header_idx = find_next_header(lines, scan_idx)
        if header_idx is None:
            break
        next_idx, data_rows = parse_table_at(lines, header_idx, log_path, findings)
        all_data_rows.extend(data_rows)
        consumed_ranges.append((header_idx, next_idx))
        # 무한루프 방지: parse_table_at은 항상 header_idx보다 뒤로 진행해야
        # 한다(헤더 자체는 최소 1줄 소비).
        scan_idx = max(next_idx, header_idx + 1)

    # P-1: 어느 표에도 소속되지 않은 "비어있지 않은 | 시작 줄" 잔여 검사.
    # F1(헤더 판정을 부분문자열 "날짜" 포함 → is_header_row 전체 7컬럼 일치로
    # 좁힌 수정)이 만든 미탐을 봉합한다 — 헤더가 깨진 표는 이제 "잘못된
    # 헤더"가 아니라 "헤더 아님"으로 분류되므로 find_next_header가 그 줄을
    # 그냥 지나치고, 그 앞 표는 이미 파싱이 끝난(또는 애초에 시작되지 않은)
    # 뒤라 깨진 표 전체가 어느 스캔에도 걸리지 않은 채 조용히 넘어갈 수
    # 있었다(실측: 5종 회귀 케이스 전부 수정 전엔 exit 0). 각 표가 실제로
    # 소비한 줄 범위(헤더·구분선·데이터 행 전부 포함)를 기록해두고, 그 범위
    # 밖에서 여전히 표처럼 보이는(파이프로 시작하는 비어있지 않은) 줄이
    # 남아 있으면 FAIL로 표면화한다.
    consumed = set()
    for start, end in consumed_ranges:
        consumed.update(range(start, end))
    for i, line in enumerate(lines):
        if i in consumed:
            continue
        stripped = line.strip()
        if stripped and stripped.startswith("|"):
            findings.append(Finding(
                "FAIL", log_path, i + 1,
                f"표처럼 보이는 줄이 어느 유효한 헤더에도 소속된 표 안에 있지 않음 — "
                f"기대 헤더: {expected_header_str} (헤더 오타나 컬럼 누락으로 이 표 "
                f"전체가 스캔에서 누락됐을 수 있음): {stripped!r}"))

    if not all_data_rows:
        findings.append(Finding("WARN", log_path, None, "데이터 행이 0건 — 빈 로그"))
        return findings

    pending_lines = []
    for line_no, cells in all_data_rows:
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

        if date and not is_valid_date(date):
            findings.append(Finding(
                "FAIL", log_path, line_no,
                f"날짜 형식/값이 올바르지 않음(YYYY-MM-DD, 실존하는 날짜여야 함): '{date}'"))

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
