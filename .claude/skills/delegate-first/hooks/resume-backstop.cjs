#!/usr/bin/env node
/**
 * PreToolUse hook (matcher: Agent) — resume 백스톱.
 *
 * 결함: SKILL.md frontmatter `hooks`로 등록한 Agent 차단 훅은 같은 프로세스의
 *   `/compact` 뒤에는 유지되지만, resume(`claude --resume`, `claude -p --resume`)
 *   뒤에는 꺼진다. 재개 세션에서는 effort 없는 Agent 호출이 그대로 실행된다
 *   (실측 .delegate/20261030-delegate-first-v2/evidence-tmp/v2-10-persist/).
 *
 * 동작: 전역 ~/.claude/settings.json에 등록되어 모든 세션의 Agent 호출에서 돈다.
 *   등록 command는 $HOME 사본 resume-backstop.sh 래퍼를 거쳐 $HOME 사본인 이
 *   스크립트만 실행한다. 프로젝트 경로의 사본은 실행하지 않는다.
 *   stdin의 transcript_path(JSONL)를 줄 단위로 읽어 이 세션이 delegate-first를
 *   실제로 호출한 기록이 있는지 본다. resume은 같은 전사 파일에 이어 쓰고,
 *   compact 경계 앞의 레코드도 파일에 남는다(위 실측 세션 전사로 확인).
 *   - 인정하는 기록 (가): 메인 체인의 type "user" 레코드 중 content(문자열이나
 *     text 블록을 이은 것)가 `<command-`로 시작하고, 그 안 첫 `<command-name>` 값이
 *     `/delegate-first`(플러그인 접두 `/<plugin>:delegate-first` 포함)인 것. 슬래시
 *     명령 레코드다. 다른 명령의 args나 뒤 블록에 든 태그는 기록이 아니다.
 *   - 인정하는 기록 (나): 메인 체인의 type "assistant" 레코드 중 tool_use name
 *     "Skill", input.skill이 "delegate-first"(또는 "<plugin>:delegate-first")인 것.
 *   - 인정하지 않는 것: tool_result 블록, 팀메이트·작업 알림처럼 다른 태그로
 *     시작하는 메시지 안의 인용, compact 요약, 사이드체인(서브에이전트) 레코드.
 *   기록이 있으면 스킬의 enforce-subagent-model.cjs를 같은 stdin으로 실행하고
 *   그 종료 코드를 전달한다(0·2 밖의 코드와 실행 실패는 2). 스크립트는 $HOME
 *   사본을 쓴다. $HOME 사본이 없을 때만 ${CLAUDE_PROJECT_DIR} 사본을 쓰고, 둘 다
 *   없으면 2다. 두 사본이 모두 있고 sha256이 다르면 stderr에 경고 한 줄을 낸다.
 *   기록이 없으면 0이다(스킬 밖 세션은 강제하지 않는다).
 *
 * 한계: 전사를 읽지 못하면(경로 없음·권한·stdin 파싱 실패) stderr에 경고 한 줄을
 *   내고 0으로 통과시킨다. 처음 연 세션은 frontmatter 훅이 fail-closed로 지키므로
 *   이 경로가 여는 틈은 "전사를 못 읽는 재개 세션" 하나다. 스킬 호출 세션에서는
 *   frontmatter 훅과 이 백스톱이 enforce를 두 번 실행한다(판정은 같다).
 *
 * 성능: 스트림으로 읽고 첫 매치에서 멈춘다. JSON.parse 전에 문자열 사전 필터를
 *   둔다(cwd에 delegate-first가 든 레포에서는 거의 모든 줄이 이 이름을 담는다).
 *
 * 공급망 서약(README.md "훅 공급망 고지"): enforce-subagent-model.cjs와 달리 이
 *   스크립트는 fs로 전사 파일과 enforce 사본을 읽기 전용으로 열고(사본은 sha256
 *   비교용), child_process로 같은 node에서 enforce 스크립트 하나만 실행한다.
 *   쓰기·네트워크·eval은 하지 않는다.
 */
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const readline = require("readline");
const { spawnSync } = require("child_process");

const TAG = "[delegate-first] resume 백스톱";
const ENFORCE_REL = path.join(".claude", "skills", "delegate-first", "hooks", "enforce-subagent-model.cjs");
const COMMAND_NAME_RE = /<command-name>([^<]*)<\/command-name>/;
const COMMAND_RE = /^\/(?:[A-Za-z0-9_.-]+:)?delegate-first$/;
const SKILL_RE = /^(?:[A-Za-z0-9_.-]+:)?delegate-first$/;

function isInvocation(line) {
  // 사전 필터: 두 기록 중 하나가 될 수 있는 줄만 파싱한다.
  const maybeCommand = line.includes("delegate-first</command-name>");
  const maybeSkill = line.includes('"Skill"') && line.includes("delegate-first");
  if (!maybeCommand && !maybeSkill) return false;
  let r;
  try {
    r = JSON.parse(line);
  } catch (e) {
    return false;
  }
  if (r === null || typeof r !== "object" || r.isSidechain === true || r.isCompactSummary === true) return false;
  const content = r.message && r.message.content;
  if (r.type === "user" && maybeCommand) {
    const texts = typeof content === "string" ? [content]
      : Array.isArray(content) ? content.filter((b) => b && b.type === "text" && typeof b.text === "string").map((b) => b.text)
      : [];
    const text = texts.join("\n").trimStart();
    const m = text.startsWith("<command-") ? COMMAND_NAME_RE.exec(text) : null;
    return m !== null && COMMAND_RE.test(m[1].trim());
  }
  if (r.type === "assistant" && maybeSkill && Array.isArray(content)) {
    return content.some((b) => b && b.type === "tool_use" && b.name === "Skill" &&
      b.input && typeof b.input.skill === "string" && SKILL_RE.test(b.input.skill.trim()));
  }
  return false;
}

function hasInvocation(file) {
  return new Promise((resolve, reject) => {
    const stream = fs.createReadStream(file, { encoding: "utf8" });
    const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });
    let found = false;
    stream.on("error", reject);
    rl.on("error", reject);
    rl.on("line", (line) => {
      if (found || !isInvocation(line)) return;
      found = true;
      rl.close();
      stream.destroy();
    });
    rl.on("close", () => resolve(found));
  });
}

function sha256(f) {
  return crypto.createHash("sha256").update(fs.readFileSync(f)).digest("hex");
}

// $HOME 사본이 우선이다. 프로젝트 사본은 $HOME 사본이 없을 때만 쓴다.
function findEnforce() {
  const at = (root) => {
    if (typeof root !== "string" || root === "") return null;
    const f = path.join(root, ENFORCE_REL);
    try {
      return fs.statSync(f).isFile() ? f : null; // FIFO·장치 파일은 해시 읽기에서 멈추므로 사본으로 보지 않는다
    } catch (e) {
      return null;
    }
  };
  const home = at(process.env.HOME);
  const project = at(process.env.CLAUDE_PROJECT_DIR);
  if (home && project && home !== project && sha256(home) !== sha256(project)) {
    process.stderr.write(`${TAG}: 프로젝트 사본(${project})의 sha256이 $HOME 사본과 다르다. $HOME 사본으로 검사한다.\n`);
  }
  return home || project;
}

async function main() {
  let raw;
  let transcript;
  try {
    raw = fs.readFileSync(0);
    transcript = JSON.parse(raw.toString("utf8")).transcript_path;
  } catch (e) {
    process.stderr.write(`${TAG}: 입력을 읽지 못해 검사를 건너뛴다(${e.message}).\n`);
    return 0;
  }
  if (typeof transcript !== "string" || transcript === "") {
    process.stderr.write(`${TAG}: transcript_path가 없어 검사를 건너뛴다.\n`);
    return 0;
  }
  let invoked;
  try {
    invoked = await hasInvocation(transcript);
  } catch (e) {
    process.stderr.write(`${TAG}: 전사를 읽지 못해 검사를 건너뛴다(${e.code || e.message}: ${transcript}).\n`);
    return 0;
  }
  if (!invoked) return 0;

  const enforce = findEnforce();
  if (!enforce) {
    process.stderr.write(`${TAG}: 이 세션은 delegate-first를 호출했지만 차단 훅 스크립트를 찾지 못했다(프로젝트·전역 설치 모두 없음). Agent 호출을 막는다(fail-closed). scripts/reinstall.sh로 스킬을 다시 설치한다.\n`);
    return 2;
  }
  const res = spawnSync(process.execPath, [enforce], { input: raw, stdio: ["pipe", "inherit", "inherit"] });
  if (res.status === 0 || res.status === 2) return res.status;
  const why = res.error ? res.error.message : res.signal ? `신호 ${res.signal}` : `종료 코드 ${res.status}`;
  process.stderr.write(`${TAG}: 차단 훅이 예상 밖으로 끝났다(${why}). Agent 호출을 막는다(fail-closed).\n`);
  return 2;
}

main().then((code) => process.exit(code), (e) => {
  process.stderr.write(`${TAG}: 예상 밖 오류로 Agent 호출을 막는다(fail-closed): ${e && e.message}\n`);
  process.exit(2);
});
