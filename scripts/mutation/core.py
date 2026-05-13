from __future__ import annotations

from dataclasses import asdict, dataclass
from fnmatch import fnmatch
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST_PATH = REPO_ROOT / "mutation" / "manifest.json"
DEFAULT_POLICY_PATH = REPO_ROOT / "mutation" / "policy.json"
DEFAULT_EQUIVALENTS_PATH = REPO_ROOT / "mutation" / "equivalents.json"

ALLOWED_OPERATORS = {
    "comparison_equality",
    "comparison_bounds",
    "logical_connector",
    "boolean_literal",
    "nil_guard_invert",
    "arithmetic_simple",
    "delete_return",
    "delete_local",
    "delete_assignment",
    "delete_call",
}

INVALID_OUTPUT_PATTERNS = (
    "FAILED TO LOAD FILE",
    "syntax error",
    "error loading module",
    "unfinished string",
    "unfinished long string",
    "unfinished long comment",
    "unexpected symbol near",
    "unexpected eof",
    "expected near",
)

DEFAULT_OVERLAY_EXCLUDED_PREFIXES = (
    ".mutation-",
    "mutation-plan",
    "mutation-shards",
    "mutation-aggregate",
)

OPERATOR_PRIORITY = {
    "nil_guard_invert": 0,
    "comparison_equality": 1,
    "comparison_bounds": 2,
    "logical_connector": 3,
    "boolean_literal": 4,
    "arithmetic_simple": 5,
    "delete_return": 6,
    "delete_local": 7,
    "delete_assignment": 8,
    "delete_call": 9,
}


class MutationError(RuntimeError):
    """Raised when the mutation runner encounters a configuration or runtime error."""


@dataclass(frozen=True)
class Token:
    kind: str
    value: str
    start: int
    end: int
    line: int
    column: int


@dataclass(frozen=True)
class MutationCandidate:
    mutant_id: str
    ordinal: int
    file_path: str
    operator: str
    line: int
    column: int
    start_offset: int
    end_offset: int
    original: str
    replacement: str
    selected_specs: list[str]
    source_excerpt: str


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def ensure_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def banner(title: str) -> None:
    print("", flush=True)
    print("=" * 80, flush=True)
    print(title, flush=True)
    print("=" * 80, flush=True)


def log(message: str) -> None:
    print(f"[mutation] {message}", flush=True)


def posix_relative(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def safe_name(path: str) -> str:
    return path.replace("/", "__").replace(".", "_")


def unique_preserve_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


def load_policy(path: Path) -> dict[str, Any]:
    policy = read_json(path)
    operators = set(policy.get("operators", []))
    unknown = operators - ALLOWED_OPERATORS
    if unknown:
        raise MutationError(f"Unknown operators in {path}: {sorted(unknown)}")
    return policy


def resolve_manifest(path: Path) -> dict[str, list[str]]:
    manifest = read_json(path)
    groups = manifest.get("groups", {})
    modules = manifest.get("modules", {})
    if not isinstance(groups, dict) or not isinstance(modules, dict):
        raise MutationError(f"Invalid manifest structure in {path}")

    resolved: dict[str, list[str]] = {}
    for module_path, entry in modules.items():
        if not isinstance(entry, dict):
            raise MutationError(f"Invalid manifest entry for {module_path}")
        specs: list[str] = []
        for group_name in entry.get("groups", []):
            group_specs = groups.get(group_name)
            if not isinstance(group_specs, list):
                raise MutationError(f"Unknown spec group '{group_name}' for {module_path}")
            specs.extend(group_specs)
        specs.extend(entry.get("specs", []))
        resolved[module_path] = unique_preserve_order(specs)
    return resolved


def load_equivalents(path: Path) -> dict[tuple[str, str, int, int, str], dict[str, Any]]:
    payload = read_json(path)
    equivalents = payload.get("equivalents", [])
    result: dict[tuple[str, str, int, int, str], dict[str, Any]] = {}
    for entry in equivalents:
        key = (
            entry["mutant_id"],
            entry["file_path"],
            entry["line"],
            entry["column"],
            entry["operator"],
        )
        result[key] = entry
    return result


def discover_included_files(policy: dict[str, Any]) -> list[str]:
    roots = policy.get("included_roots", [])
    exclusions = policy.get("excluded_paths", [])
    discovered: list[str] = []
    for root_name in roots:
        root = REPO_ROOT / root_name
        if not root.exists():
            raise MutationError(f"Included root does not exist: {root_name}")
        for path in sorted(root.rglob("*.lua")):
            relative = posix_relative(path)
            if any(fnmatch(relative, entry["path"]) for entry in exclusions):
                continue
            discovered.append(relative)
    return unique_preserve_order(discovered)


def validate_manifest_against_policy(
    included_files: list[str],
    module_specs: dict[str, list[str]],
) -> None:
    missing = sorted(set(included_files) - set(module_specs))
    if missing:
        raise MutationError(
            "Missing explicit mutation spec mappings for: " + ", ".join(missing)
        )
    empty = sorted(path for path, specs in module_specs.items() if not specs)
    if empty:
        raise MutationError(
            "Included files with zero mapped specs are not allowed: " + ", ".join(empty)
        )
    for specs in module_specs.values():
        for spec_path in specs:
            if not (REPO_ROOT / spec_path).exists():
                raise MutationError(f"Mapped spec does not exist: {spec_path}")


def line_offsets(source: str) -> list[tuple[int, int, str, str]]:
    offsets: list[tuple[int, int, str, str]] = []
    cursor = 0
    for raw_line in source.splitlines(keepends=True):
        line_body = raw_line.rstrip("\r\n")
        line_end = raw_line[len(line_body) :]
        offsets.append((cursor, cursor + len(line_body), line_body, line_end))
        cursor += len(raw_line)
    if source.endswith(("\n", "\r")):
        return offsets
    if not offsets:
        offsets.append((0, 0, "", ""))
    return offsets


def _long_bracket_end(source: str, start: int) -> int | None:
    if start >= len(source) or source[start] != "[":
        return None
    cursor = start + 1
    while cursor < len(source) and source[cursor] == "=":
        cursor += 1
    if cursor >= len(source) or source[cursor] != "[":
        return None
    closing = "]" + ("=" * (cursor - start - 1)) + "]"
    end = source.find(closing, cursor + 1)
    if end == -1:
        return len(source)
    return end + len(closing)


def _blank(masked: list[str], source: str, start: int, end: int) -> None:
    for index in range(start, min(end, len(masked))):
        if source[index] != "\n":
            masked[index] = " "


def tokenize_lua(source: str) -> tuple[str, list[Token]]:
    tokens: list[Token] = []
    masked = list(source)
    cursor = 0
    line = 1
    column = 1

    def advance(count: int) -> None:
        nonlocal cursor, line, column
        for _ in range(count):
            if cursor >= len(source):
                return
            if source[cursor] == "\n":
                line += 1
                column = 1
            else:
                column += 1
            cursor += 1

    def emit(kind: str, start: int, end: int, token_line: int, token_col: int) -> None:
        tokens.append(
            Token(
                kind=kind,
                value=source[start:end],
                start=start,
                end=end,
                line=token_line,
                column=token_col,
            )
        )

    while cursor < len(source):
        ch = source[cursor]
        nxt = source[cursor + 1] if cursor + 1 < len(source) else ""

        if ch == "-" and nxt == "-":
            comment_start = cursor
            bracket_end = _long_bracket_end(source, cursor + 2)
            if bracket_end is not None and cursor + 2 < len(source) and source[cursor + 2] == "[":
                _blank(masked, source, comment_start, bracket_end)
                advance(bracket_end - comment_start)
                continue
            comment_end = source.find("\n", cursor)
            if comment_end == -1:
                comment_end = len(source)
            _blank(masked, source, comment_start, comment_end)
            advance(comment_end - comment_start)
            continue

        if ch in ("'", '"'):
            quote = ch
            string_start = cursor
            advance(1)
            while cursor < len(source):
                if source[cursor] == "\\" and cursor + 1 < len(source):
                    advance(2)
                    continue
                if source[cursor] == quote:
                    advance(1)
                    break
                advance(1)
            _blank(masked, source, string_start, cursor)
            continue

        bracket_end = _long_bracket_end(source, cursor)
        if bracket_end is not None:
            string_start = cursor
            advance(bracket_end - string_start)
            _blank(masked, source, string_start, cursor)
            continue

        if ch.isspace():
            advance(1)
            continue

        token_line = line
        token_col = column
        two_char = source[cursor : cursor + 2]
        if two_char in {"==", "~=", "<=", ">="}:
            emit("operator", cursor, cursor + 2, token_line, token_col)
            advance(2)
            continue

        if ch.isalpha() or ch == "_":
            start = cursor
            advance(1)
            while cursor < len(source) and (source[cursor].isalnum() or source[cursor] == "_"):
                advance(1)
            emit("identifier", start, cursor, token_line, token_col)
            continue

        if ch.isdigit():
            start = cursor
            advance(1)
            while cursor < len(source) and re.match(r"[0-9A-Fa-fxXpP\._]", source[cursor]):
                advance(1)
            emit("number", start, cursor, token_line, token_col)
            continue

        if ch in "+-*/%<>=()[]{}.,:":
            emit("operator", cursor, cursor + 1, token_line, token_col)
            advance(1)
            continue

        advance(1)

    return "".join(masked), tokens


def _token_is_operand(token: Token | None) -> bool:
    if token is None:
        return False
    if token.kind in {"identifier", "number"}:
        return True
    return token.value in {")", "]"}


def _token_is_operand_start(token: Token | None) -> bool:
    if token is None:
        return False
    if token.kind in {"identifier", "number"}:
        return True
    return token.value in {"(", "["}


def _candidate_id(
    file_path: str,
    operator: str,
    line: int,
    column: int,
    original: str,
    replacement: str,
) -> str:
    digest = hashlib.sha1(
        f"{file_path}|{operator}|{line}|{column}|{original}|{replacement}".encode("utf-8")
    ).hexdigest()
    return digest[:12]


def compact_candidates(
    candidates: list[MutationCandidate],
    max_mutants_per_file: int,
) -> list[MutationCandidate]:
    def evenly_sample(
        operator_candidates: list[MutationCandidate],
        target_count: int,
    ) -> list[MutationCandidate]:
        if target_count >= len(operator_candidates):
            return list(operator_candidates)

        step = len(operator_candidates) / target_count
        sampled: list[MutationCandidate] = []
        seen: set[int] = set()
        for index in range(target_count):
            candidate_index = min(
                len(operator_candidates) - 1,
                int((index + 0.5) * step),
            )
            while candidate_index in seen and candidate_index < len(operator_candidates) - 1:
                candidate_index += 1
            while candidate_index in seen and candidate_index > 0:
                candidate_index -= 1
            if candidate_index in seen:
                continue
            seen.add(candidate_index)
            sampled.append(operator_candidates[candidate_index])
        return sampled

    grouped: dict[str, list[MutationCandidate]] = {}
    for candidate in candidates:
        grouped.setdefault(candidate.operator, []).append(candidate)

    for operator_candidates in grouped.values():
        operator_candidates.sort(
            key=lambda item: (item.line, item.column, item.start_offset, item.operator)
        )

    operator_order = sorted(grouped, key=lambda operator: (OPERATOR_PRIORITY[operator], operator))

    if max_mutants_per_file > 0:
        quotas = {operator: 0 for operator in operator_order}
        remaining = max_mutants_per_file
        while remaining > 0:
            progressed = False
            for operator in operator_order:
                if quotas[operator] >= len(grouped[operator]):
                    continue
                quotas[operator] += 1
                remaining -= 1
                progressed = True
                if remaining == 0:
                    break
            if not progressed:
                break

        compacted: list[MutationCandidate] = []
        for operator in operator_order:
            compacted.extend(evenly_sample(grouped[operator], quotas[operator]))
    else:
        compacted = [
            candidate
            for operator in operator_order
            for candidate in grouped[operator]
        ]

    compacted.sort(key=lambda item: (item.line, item.column, item.operator, item.start_offset))

    return [
        MutationCandidate(
            mutant_id=candidate.mutant_id,
            ordinal=ordinal,
            file_path=candidate.file_path,
            operator=candidate.operator,
            line=candidate.line,
            column=candidate.column,
            start_offset=candidate.start_offset,
            end_offset=candidate.end_offset,
            original=candidate.original,
            replacement=candidate.replacement,
            selected_specs=candidate.selected_specs,
            source_excerpt=candidate.source_excerpt,
        )
        for ordinal, candidate in enumerate(compacted, start=1)
    ]


def generate_mutations_for_source(
    file_path: str,
    source: str,
    selected_specs: list[str],
    allowed_operators: set[str],
) -> list[MutationCandidate]:
    masked_source, tokens = tokenize_lua(source)
    offsets = line_offsets(source)
    candidates: list[MutationCandidate] = []

    def add_candidate(
        operator: str,
        start_offset: int,
        end_offset: int,
        line: int,
        column: int,
        original: str,
        replacement: str,
    ) -> None:
        source_line = offsets[line - 1][2] if 0 < line <= len(offsets) else ""
        candidates.append(
            MutationCandidate(
                mutant_id=_candidate_id(file_path, operator, line, column, original, replacement),
                ordinal=0,
                file_path=file_path,
                operator=operator,
                line=line,
                column=column,
                start_offset=start_offset,
                end_offset=end_offset,
                original=original,
                replacement=replacement,
                selected_specs=selected_specs,
                source_excerpt=source_line.strip(),
            )
        )

    for index, token in enumerate(tokens):
        prev_token = tokens[index - 1] if index > 0 else None
        next_token = tokens[index + 1] if index + 1 < len(tokens) else None

        if token.value in {"==", "~="}:
            operator = (
                "nil_guard_invert"
                if (prev_token and prev_token.value == "nil") or (next_token and next_token.value == "nil")
                else "comparison_equality"
            )
            if operator in allowed_operators:
                replacement = "~=" if token.value == "==" else "=="
                add_candidate(
                    operator,
                    token.start,
                    token.end,
                    token.line,
                    token.column,
                    token.value,
                    replacement,
                )
            continue

        if token.value in {"<", "<=", ">", ">="} and "comparison_bounds" in allowed_operators:
            replacement_map = {"<": "<=", "<=": "<", ">": ">=", ">=": ">"}
            add_candidate(
                "comparison_bounds",
                token.start,
                token.end,
                token.line,
                token.column,
                token.value,
                replacement_map[token.value],
            )
            continue

        if token.value in {"and", "or"} and "logical_connector" in allowed_operators:
            replacement = "or" if token.value == "and" else "and"
            add_candidate(
                "logical_connector",
                token.start,
                token.end,
                token.line,
                token.column,
                token.value,
                replacement,
            )
            continue

        if token.value in {"true", "false"} and "boolean_literal" in allowed_operators:
            replacement = "false" if token.value == "true" else "true"
            add_candidate(
                "boolean_literal",
                token.start,
                token.end,
                token.line,
                token.column,
                token.value,
                replacement,
            )
            continue

        if token.value in {"+", "-", "*", "/"} and "arithmetic_simple" in allowed_operators:
            if _token_is_operand(prev_token) and _token_is_operand_start(next_token):
                replacement_map = {"+": "-", "-": "+", "*": "/", "/": "*"}
                add_candidate(
                    "arithmetic_simple",
                    token.start,
                    token.end,
                    token.line,
                    token.column,
                    token.value,
                    replacement_map[token.value],
                )

    keyword_blockers = re.compile(r"\b(if|then|elseif|else|for|while|repeat|until|do|function|end)\b")
    assignment_pattern = re.compile(r"^[A-Za-z_][A-Za-z0-9_\.\:\[\] ]*=\s*.+$")
    local_pattern = re.compile(r"^local\s+[A-Za-z_][A-Za-z0-9_,\s]*(\s*=.+)?$")
    call_pattern = re.compile(r"^[A-Za-z_][A-Za-z0-9_\.\:]*\s*\(.*\)$")
    trailing_operator = re.compile(r"(,|\.\.|[+\-*/=])\s*$")
    multiline_structure_open = re.compile(r"[{\[(]\s*$")

    for line_number, (start_offset, end_offset, line_text, _) in enumerate(offsets, start=1):
        masked_line = masked_source[start_offset:end_offset]
        stripped = masked_line.strip()
        indent = re.match(r"^\s*", line_text).group(0)
        if not stripped:
            continue
        if len(indent) < 2:
            continue
        if keyword_blockers.search(stripped):
            continue
        if trailing_operator.search(stripped):
            continue
        if multiline_structure_open.search(stripped):
            continue
        if stripped.count("(") != stripped.count(")") or stripped.count("[") != stripped.count("]"):
            continue

        operator = None
        if stripped.startswith("return ") and "delete_return" in allowed_operators:
            operator = "delete_return"
        elif local_pattern.match(stripped) and not stripped.startswith("local function") and "delete_local" in allowed_operators:
            operator = "delete_local"
        elif (
            assignment_pattern.match(stripped)
            and not stripped.startswith("local ")
            and "==" not in stripped
            and "~=" not in stripped
            and "delete_assignment" in allowed_operators
        ):
            operator = "delete_assignment"
        elif call_pattern.match(stripped) and "delete_call" in allowed_operators:
            operator = "delete_call"

        if not operator:
            continue

        replacement = indent + "-- mutation: deleted statement"
        add_candidate(
            operator,
            start_offset,
            end_offset,
            line_number,
            len(indent) + 1,
            line_text,
            replacement,
        )

    candidates.sort(key=lambda item: (item.line, item.column, item.operator, item.start_offset))
    return candidates


def mutate_source(source: str, candidate: MutationCandidate) -> str:
    return (
        source[: candidate.start_offset]
        + candidate.replacement
        + source[candidate.end_offset :]
    )


def build_plan(
    policy_path: Path = DEFAULT_POLICY_PATH,
    manifest_path: Path = DEFAULT_MANIFEST_PATH,
    operator_override: set[str] | None = None,
) -> dict[str, Any]:
    banner("Mutation Plan")
    policy = load_policy(policy_path)
    manifest = resolve_manifest(manifest_path)
    included_files = discover_included_files(policy)
    validate_manifest_against_policy(included_files, manifest)
    filtered_manifest = {file_path: manifest[file_path] for file_path in included_files}

    operators = set(policy["operators"])
    if operator_override:
        unknown = operator_override - operators
        if unknown:
            raise MutationError(f"Operator override contains unsupported values: {sorted(unknown)}")
        operators = operator_override

    mutants: list[dict[str, Any]] = []
    max_mutants_per_file = int(policy.get("max_mutants_per_file", 0))
    for file_path in included_files:
        selected_specs = manifest[file_path]
        source = (REPO_ROOT / file_path).read_text(encoding="utf-8")
        raw_mutants = generate_mutations_for_source(file_path, source, selected_specs, operators)
        file_mutants = compact_candidates(raw_mutants, max_mutants_per_file)
        log(
            f"discovered {len(raw_mutants)} raw mutants and kept {len(file_mutants)} "
            f"deterministic sample mutants in {file_path} "
            f"using specs: {', '.join(selected_specs)}"
        )
        mutants.extend(asdict(candidate) for candidate in file_mutants)

    for ordinal, mutant in enumerate(mutants, start=1):
        mutant["ordinal"] = ordinal

    log(f"generated {len(mutants)} deterministic mutants across {len(included_files)} files")
    return {
        "generated_at": int(time.time()),
        "policy": policy,
        "included_files": included_files,
        "module_specs": filtered_manifest,
        "mutants": mutants,
    }


def build_bundle_source(specs: list[str]) -> str:
    lines = [f"dofile(vim.fn.getcwd() .. '/{spec_path}')" for spec_path in specs]
    return "\n".join(lines) + "\n"


def _nvim_test_command(bundle_path: Path) -> list[str]:
    escaped_path = bundle_path.as_posix().replace("\\", "\\\\").replace("'", "\\'")
    return [
        "nvim",
        "--headless",
        "--noplugin",
        "-u",
        "tests/minimal_init.lua",
        "-c",
        f"set rtp+=. | lua require('plenary.busted').run('{escaped_path}')",
    ]


def _nvim_syntax_check_command(lua_path: Path) -> list[str]:
    escaped_path = lua_path.as_posix().replace("\\", "\\\\").replace("'", "\\'")
    return [
        "nvim",
        "--headless",
        "--noplugin",
        "-u",
        "NONE",
        "-c",
        "set nomore",
        "-c",
        f"lua local chunk, err = loadfile('{escaped_path}'); if not chunk then error(err) end",
        "-c",
        "qa!",
    ]


def run_bundle(bundle_path: Path, cwd: Path, timeout_seconds: int) -> tuple[int, str, str, float]:
    command = _nvim_test_command(bundle_path)
    started = time.time()
    result = subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
        check=False,
    )
    duration = time.time() - started
    return result.returncode, result.stdout, result.stderr, duration


def check_lua_syntax(lua_path: Path, cwd: Path) -> tuple[int, str, str, float]:
    command = _nvim_syntax_check_command(lua_path)
    started = time.time()
    result = subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    duration = time.time() - started
    return result.returncode, result.stdout, result.stderr, duration


def create_bundle_file(bundle_root: Path, module_path: str, specs: list[str]) -> Path:
    bundle_root.mkdir(parents=True, exist_ok=True)
    bundle_path = bundle_root / f"{safe_name(module_path)}_bundle_spec.lua"
    bundle_path.write_text(build_bundle_source(specs), encoding="utf-8")
    return bundle_path


def preflight(plan: dict[str, Any], retry_count: int = 1) -> list[dict[str, Any]]:
    banner("Mutation Preflight")
    bundle_root = REPO_ROOT / ".mutation-preflight"
    if bundle_root.exists():
        shutil.rmtree(bundle_root)
    bundle_root.mkdir(parents=True, exist_ok=True)

    unique_bundles: dict[tuple[str, ...], list[str]] = {}
    for module_path, specs in plan["module_specs"].items():
        unique_bundles.setdefault(tuple(specs), []).append(module_path)

    results: list[dict[str, Any]] = []
    try:
        for specs, modules in sorted(unique_bundles.items(), key=lambda item: item[1][0]):
            bundle_path = create_bundle_file(bundle_root, modules[0], list(specs))
            log(
                f"preflight bundle for modules: {', '.join(modules)} "
                f"with specs: {', '.join(specs)}"
            )
            attempts = retry_count + 1
            last_result: dict[str, Any] | None = None
            for attempt in range(1, attempts + 1):
                code, stdout, stderr, duration = run_bundle(
                    bundle_path,
                    cwd=REPO_ROOT,
                    timeout_seconds=plan["policy"]["timeout_seconds"],
                )
                last_result = {
                    "modules": modules,
                    "specs": list(specs),
                    "exit_code": code,
                    "stdout": stdout,
                    "stderr": stderr,
                    "duration_seconds": round(duration, 3),
                    "attempt": attempt,
                }
                if code == 0:
                    break
                if attempt < attempts:
                    log(
                        f"clean preflight failed for {modules[0]} on attempt {attempt}; retrying once"
                    )
            assert last_result is not None
            results.append(last_result)
            if last_result["exit_code"] != 0:
                raise MutationError(
                    f"Preflight failed for {modules[0]} with specs {', '.join(specs)}"
                )
    finally:
        if bundle_root.exists():
            shutil.rmtree(bundle_root)

    log("preflight completed cleanly")
    return results


def select_shard_mutants(mutants: list[dict[str, Any]], shard_index: int, shard_count: int) -> list[dict[str, Any]]:
    return [
        mutant
        for mutant in mutants
        if (mutant["ordinal"] - 1) % shard_count == shard_index
    ]


def is_invalid_output(output: str) -> bool:
    lowered = output.lower()
    return any(pattern.lower() in lowered for pattern in INVALID_OUTPUT_PATTERNS)


def save_failure_artifact(
    artifact_root: Path,
    status: str,
    mutant: dict[str, Any],
    mutated_source: str,
    output: str,
) -> None:
    target_dir = artifact_root / status / mutant["mutant_id"]
    target_dir.mkdir(parents=True, exist_ok=True)
    source_name = safe_name(mutant["file_path"]) + ".lua"
    (target_dir / source_name).write_text(mutated_source, encoding="utf-8")
    write_json(
        target_dir / "metadata.json",
        {
            "mutant": mutant,
            "status": status,
            "output": output,
        },
    )


def repo_relative_prefix(path: Path) -> str | None:
    absolute_path = path if path.is_absolute() else REPO_ROOT / path
    try:
        relative_path = absolute_path.relative_to(REPO_ROOT)
    except ValueError:
        return None
    relative = relative_path.as_posix()
    return relative or None


def build_overlay_excluded_prefixes(artifact_root: Path) -> list[str]:
    prefixes = list(DEFAULT_OVERLAY_EXCLUDED_PREFIXES)
    output_root = artifact_root.parent.parent if len(artifact_root.parents) >= 2 else artifact_root.parent
    relative_output_root = repo_relative_prefix(output_root)
    if relative_output_root and relative_output_root not in prefixes:
        prefixes.append(relative_output_root)
    return prefixes


def is_overlay_excluded_path(relative_path: str, excluded_prefixes: list[str]) -> bool:
    return any(
        relative_path == prefix or relative_path.startswith(f"{prefix}/")
        for prefix in excluded_prefixes
    )


def add_worktree() -> Path:
    worktree_dir = Path(tempfile.mkdtemp(prefix="raccoon-mutation-worktree-"))
    subprocess.run(
        ["git", "worktree", "add", "--force", "--detach", str(worktree_dir), "HEAD"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return worktree_dir


def overlay_workspace(worktree_dir: Path, excluded_prefixes: list[str]) -> None:
    tracked = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=False,
        check=True,
    )
    for raw_path in tracked.stdout.split(b"\0"):
        if not raw_path:
            continue
        relative = raw_path.decode("utf-8")
        if is_overlay_excluded_path(relative, excluded_prefixes):
            continue
        source = REPO_ROOT / relative
        target = worktree_dir / relative
        if not source.exists() or source.is_dir():
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    deleted = subprocess.run(
        ["git", "ls-files", "--deleted", "-z"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=False,
        check=True,
    )
    for raw_path in deleted.stdout.split(b"\0"):
        if not raw_path:
            continue
        relative = raw_path.decode("utf-8")
        if is_overlay_excluded_path(relative, excluded_prefixes):
            continue
        target = worktree_dir / relative
        if target.exists():
            target.unlink()


def remove_worktree(worktree_dir: Path) -> None:
    subprocess.run(
        ["git", "worktree", "remove", "--force", str(worktree_dir)],
        cwd=REPO_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if worktree_dir.exists():
        shutil.rmtree(worktree_dir, ignore_errors=True)


def execute_shard(
    plan: dict[str, Any],
    shard_index: int,
    shard_count: int,
    artifact_root: Path,
    keep_failed_worktree: bool,
    ci_mode: bool,
) -> dict[str, Any]:
    banner(f"Mutation Shard {shard_index + 1}/{shard_count}")
    policy = plan["policy"]
    mutants = select_shard_mutants(plan["mutants"], shard_index, shard_count)
    log(f"assigned {len(mutants)} mutants to shard {shard_index + 1}/{shard_count}")

    excluded_prefixes = build_overlay_excluded_prefixes(artifact_root)
    worktree_dir = add_worktree()
    overlay_workspace(worktree_dir, excluded_prefixes)
    bundle_root = worktree_dir / ".mutation-bundles"
    bundle_cache: dict[str, Path] = {}
    results: list[dict[str, Any]] = []
    kept_worktree = False

    try:
        for mutant in mutants:
            module_path = mutant["file_path"]
            module_specs = plan["module_specs"][module_path]
            bundle_key = "|".join(module_specs)
            bundle_path = bundle_cache.get(bundle_key)
            if bundle_path is None:
                bundle_path = create_bundle_file(bundle_root, module_path, module_specs)
                bundle_cache[bundle_key] = bundle_path

            target_path = worktree_dir / module_path
            original_source = target_path.read_text(encoding="utf-8")
            mutated_source = mutate_source(
                original_source,
                MutationCandidate(
                    mutant_id=mutant["mutant_id"],
                    ordinal=mutant["ordinal"],
                    file_path=mutant["file_path"],
                    operator=mutant["operator"],
                    line=mutant["line"],
                    column=mutant["column"],
                    start_offset=mutant["start_offset"],
                    end_offset=mutant["end_offset"],
                    original=mutant["original"],
                    replacement=mutant["replacement"],
                    selected_specs=mutant["selected_specs"],
                    source_excerpt=mutant["source_excerpt"],
                ),
            )
            log(
                f"mutant {mutant['mutant_id']} start "
                f"{mutant['file_path']}:{mutant['line']}:{mutant['column']} "
                f"{mutant['operator']} specs={','.join(module_specs)}"
            )
            target_path.write_text(mutated_source, encoding="utf-8")
            output = ""
            status = "runner_error"
            duration = 0.0
            exit_code = None
            try:
                exit_code, stdout, stderr, duration = check_lua_syntax(
                    target_path,
                    cwd=worktree_dir,
                )
                output = stdout + stderr
                if exit_code != 0:
                    status = "invalid"
                else:
                    exit_code, stdout, stderr, duration = run_bundle(
                        bundle_path,
                        cwd=worktree_dir,
                        timeout_seconds=policy["timeout_seconds"],
                    )
                    output = stdout + stderr
                    if exit_code == 0:
                        status = "survived"
                    elif is_invalid_output(output):
                        status = "invalid"
                    else:
                        status = "killed"
            except subprocess.TimeoutExpired as exc:
                status = "timeout"
                output = ensure_text(exc.stdout) + ensure_text(exc.stderr)
                duration = float(policy["timeout_seconds"])
            finally:
                target_path.write_text(original_source, encoding="utf-8")

            log(
                f"mutant {mutant['mutant_id']} result={status} "
                f"duration={duration:.3f}s exit_code={exit_code}"
            )
            if status in {"survived", "invalid", "timeout"}:
                save_failure_artifact(artifact_root, status, mutant, mutated_source, output)

            result = {
                "mutant_id": mutant["mutant_id"],
                "file_path": mutant["file_path"],
                "operator": mutant["operator"],
                "line": mutant["line"],
                "column": mutant["column"],
                "selected_specs": module_specs,
                "status": status,
                "duration_seconds": round(duration, 3),
                "exit_code": exit_code,
                "output": output,
            }
            results.append(result)

            if status == "runner_error":
                raise MutationError(f"Runner crash for mutant {mutant['mutant_id']}")

        has_failures = any(item["status"] != "killed" for item in results)
        if not ci_mode and keep_failed_worktree and has_failures:
            kept_worktree = True
            log(f"keeping failed shard worktree at {worktree_dir}")
        return {
            "shard_index": shard_index,
            "shard_count": shard_count,
            "results": results,
            "kept_worktree": str(worktree_dir) if kept_worktree else None,
        }
    finally:
        if ci_mode or not kept_worktree:
            remove_worktree(worktree_dir)


def summarize_category(items: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    return sorted(
        items,
        key=lambda item: (
            item["file_path"],
            item["line"],
            item["column"],
            item["operator"],
            item["mutant_id"],
        ),
    )[:limit]


def write_summary_markdown(report: dict[str, Any], summary_path: Path | None) -> None:
    if summary_path is None:
        return
    lines = [
        "# Mutation Check",
        "",
        f"- Score: {report['score_percent']:.2f}%",
        f"- Threshold: {report['threshold_percent']}%",
        f"- Eligible mutants: {report['eligible_mutants']}",
        f"- Killed: {report['killed']}",
        f"- Survived: {report['survived']}",
        f"- Equivalent: {report['equivalent']}",
        f"- Invalid: {report['invalid']}",
        f"- Timeout: {report['timeout']}",
        f"- Runner errors: {report['runner_error']}",
        "",
    ]
    for label in ("survivors", "timeouts", "invalids"):
        lines.append(f"## Top {label.title()}")
        lines.append("")
        items = report[f"top_{label}"]
        if not items:
            lines.append("- none")
            lines.append("")
            continue
        for item in items:
            lines.append(
                f"- `{item['mutant_id']}` {item['file_path']}:{item['line']}:{item['column']} "
                f"{item['operator']}"
            )
        lines.append("")
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text("\n".join(lines), encoding="utf-8")


def aggregate_reports(
    plan: dict[str, Any],
    shard_reports: list[dict[str, Any]],
    equivalents_path: Path = DEFAULT_EQUIVALENTS_PATH,
    summary_path: Path | None = None,
) -> dict[str, Any]:
    banner("Mutation Aggregate")
    equivalents = load_equivalents(equivalents_path)
    flattened = [item for report in shard_reports for item in report["results"]]
    by_mutant = {item["mutant_id"]: item for item in flattened}
    missing = sorted(
        mutant["mutant_id"]
        for mutant in plan["mutants"]
        if mutant["mutant_id"] not in by_mutant
    )
    if missing:
        raise MutationError("Missing shard results for mutants: " + ", ".join(missing[:10]))

    killed = 0
    survived = 0
    invalid = 0
    timeout = 0
    runner_error = 0
    equivalent = 0
    survivor_items: list[dict[str, Any]] = []
    timeout_items: list[dict[str, Any]] = []
    invalid_items: list[dict[str, Any]] = []

    for mutant in plan["mutants"]:
        result = by_mutant[mutant["mutant_id"]]
        equivalence_key = (
            mutant["mutant_id"],
            mutant["file_path"],
            mutant["line"],
            mutant["column"],
            mutant["operator"],
        )
        allowlisted = equivalence_key in equivalents
        if result["status"] == "killed":
            killed += 1
        elif result["status"] == "survived":
            if allowlisted:
                equivalent += 1
            else:
                survived += 1
                survivor_items.append(result)
        elif result["status"] == "invalid":
            invalid += 1
            invalid_items.append(result)
        elif result["status"] == "timeout":
            timeout += 1
            timeout_items.append(result)
        else:
            runner_error += 1

    total_generated = len(plan["mutants"])
    eligible_mutants = total_generated - invalid - equivalent
    score_percent = 0.0 if eligible_mutants == 0 else (killed / eligible_mutants) * 100.0
    invalid_percent = 0.0 if total_generated == 0 else (invalid / total_generated) * 100.0

    report = {
        "total_generated": total_generated,
        "eligible_mutants": eligible_mutants,
        "threshold_percent": plan["policy"]["threshold_percent"],
        "score_percent": round(score_percent, 2),
        "invalid_percent": round(invalid_percent, 2),
        "killed": killed,
        "survived": survived,
        "equivalent": equivalent,
        "invalid": invalid,
        "timeout": timeout,
        "runner_error": runner_error,
        "top_survivors": summarize_category(
            survivor_items, plan["policy"]["max_summary_entries"]
        ),
        "top_timeouts": summarize_category(
            timeout_items, plan["policy"]["max_summary_entries"]
        ),
        "top_invalids": summarize_category(
            invalid_items, plan["policy"]["max_summary_entries"]
        ),
    }

    log(
        f"aggregate score={report['score_percent']:.2f}% threshold={report['threshold_percent']}% "
        f"killed={killed} survived={survived} equivalent={equivalent} invalid={invalid} timeout={timeout}"
    )

    write_summary_markdown(report, summary_path)

    fail_reasons: list[str] = []
    if runner_error > 0:
        fail_reasons.append("runner_error")
    if timeout > 0:
        fail_reasons.append("timeout")
    if invalid_percent > plan["policy"]["invalid_percent_limit"]:
        fail_reasons.append("invalid_percent")
    if score_percent < plan["policy"]["threshold_percent"]:
        fail_reasons.append("score_below_threshold")
    report["passed"] = not fail_reasons
    report["fail_reasons"] = fail_reasons
    return report
