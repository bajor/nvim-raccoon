from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from .core import REPO_ROOT, generate_mutations_for_source, read_json


def _load_preflight(preflight_path: Path | None) -> list[dict[str, Any]]:
    if preflight_path is None or not preflight_path.exists():
        return []
    payload = read_json(preflight_path)
    return payload.get("bundles", [])


def _merge_results(
    plan: dict[str, Any],
    shard_reports: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    plan_by_mutant = {mutant["mutant_id"]: mutant for mutant in plan["mutants"]}
    merged: list[dict[str, Any]] = []
    for shard_report in shard_reports:
        for result in shard_report["results"]:
            enriched = dict(plan_by_mutant[result["mutant_id"]])
            enriched.update(result)
            merged.append(enriched)
    return sorted(
        merged,
        key=lambda item: (
            item["file_path"],
            item["line"],
            item["column"],
            item["operator"],
            item["mutant_id"],
        ),
    )


def _compute_raw_counts(plan: dict[str, Any]) -> dict[str, int]:
    operators = set(plan["policy"]["operators"])
    counts: dict[str, int] = {}
    for file_path in plan["included_files"]:
        source = (REPO_ROOT / file_path).read_text(encoding="utf-8")
        specs = plan["module_specs"][file_path]
        counts[file_path] = len(
            generate_mutations_for_source(
                file_path=file_path,
                source=source,
                selected_specs=specs,
                allowed_operators=operators,
            )
        )
    return counts


def _md_cell(value: Any) -> str:
    return str(value).replace("\n", " ").replace("|", "\\|")


def _append_table(lines: list[str], headers: list[str], rows: list[list[Any]]) -> None:
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("| " + " | ".join(["---"] * len(headers)) + " |")
    for row in rows:
        lines.append("| " + " | ".join(_md_cell(item) for item in row) + " |")
    lines.append("")


def render_markdown(
    plan: dict[str, Any],
    aggregate: dict[str, Any],
    shard_reports: list[dict[str, Any]],
    preflight_bundles: list[dict[str, Any]],
) -> str:
    merged_results = _merge_results(plan, shard_reports)
    raw_counts = _compute_raw_counts(plan)

    results_by_file: dict[str, list[dict[str, Any]]] = {
        file_path: [] for file_path in plan["included_files"]
    }
    for result in merged_results:
        results_by_file[result["file_path"]].append(result)

    lines: list[str] = [
        "# Full Mutation Report",
        "",
        "## Where To Look",
        "",
        "- This step prints the detailed mutation report directly in the job log.",
        "- The same markdown is appended to the GitHub job summary.",
        "- The uploaded aggregate artifact includes the raw JSON plus this rendered markdown.",
        "- The blob URL printed by `actions/upload-artifact` is internal storage and is not the review surface to use.",
        "",
        "## Outcome",
        "",
        f"- Passed: `{aggregate['passed']}`",
        f"- Score: `{aggregate['score_percent']:.2f}%`",
        f"- Threshold: `{aggregate['threshold_percent']}%`",
        f"- Eligible mutants: `{aggregate['eligible_mutants']}`",
        f"- Total sampled mutants: `{aggregate['total_generated']}`",
        f"- Killed: `{aggregate['killed']}`",
        f"- Survived: `{aggregate['survived']}`",
        f"- Equivalent: `{aggregate['equivalent']}`",
        f"- Invalid: `{aggregate['invalid']}`",
        f"- Timeout: `{aggregate['timeout']}`",
        f"- Runner errors: `{aggregate['runner_error']}`",
        f"- Fail reasons: `{', '.join(aggregate['fail_reasons']) if aggregate['fail_reasons'] else 'none'}`",
        "",
        "## Policy",
        "",
        f"- Included roots: `{', '.join(plan['policy']['included_roots'])}`",
        f"- Operators: `{', '.join(plan['policy']['operators'])}`",
        f"- Deterministic sample cap per file: `{plan['policy']['max_mutants_per_file']}`",
        f"- Summary entry cap in aggregate JSON: `{plan['policy']['max_summary_entries']}`",
        f"- Timeout per mutant: `{plan['policy']['timeout_seconds']}s`",
        "",
        "## Included Files",
        "",
    ]
    for file_path in plan["included_files"]:
        lines.append(f"- `{file_path}`")
    lines.append("")

    lines.extend([
        "## Preflight Bundles",
        "",
    ])
    if not preflight_bundles:
        lines.append("- none")
        lines.append("")
    else:
        preflight_rows: list[list[Any]] = []
        for bundle in preflight_bundles:
            note = bundle["stderr"].strip().splitlines()[0] if bundle["stderr"].strip() else ""
            preflight_rows.append(
                [
                    ", ".join(bundle["modules"]),
                    ", ".join(bundle["specs"]),
                    bundle["attempt"],
                    bundle["exit_code"],
                    f"{bundle['duration_seconds']:.3f}s",
                    note or "clean",
                ]
            )
        _append_table(
            lines,
            ["modules", "specs", "attempt", "exit", "duration", "note"],
            preflight_rows,
        )

    lines.extend([
        "## File Breakdown",
        "",
    ])
    breakdown_rows: list[list[Any]] = []
    for file_path in plan["included_files"]:
        file_results = results_by_file[file_path]
        breakdown_rows.append(
            [
                file_path,
                raw_counts[file_path],
                len(file_results),
                sum(1 for item in file_results if item["status"] == "killed"),
                sum(1 for item in file_results if item["status"] == "survived"),
                sum(1 for item in file_results if item["status"] == "invalid"),
                sum(1 for item in file_results if item["status"] == "timeout"),
            ]
        )
    _append_table(
        lines,
        ["file", "raw", "sampled", "killed", "survived", "invalid", "timeout"],
        breakdown_rows,
    )

    lines.extend([
        "## Survivors To Inspect First",
        "",
    ])
    survivor_files = [
        file_path
        for file_path in sorted(
            plan["included_files"],
            key=lambda candidate: (
                -sum(1 for item in results_by_file[candidate] if item["status"] == "survived"),
                candidate,
            ),
        )
        if any(item["status"] == "survived" for item in results_by_file[file_path])
    ]
    if not survivor_files:
        lines.append("- none")
        lines.append("")
    else:
        for file_path in survivor_files:
            file_results = [item for item in results_by_file[file_path] if item["status"] == "survived"]
            lines.append(f"### `{file_path}`")
            lines.append("")
            lines.append(
                f"- Survivors: `{len(file_results)}` of `{len(results_by_file[file_path])}` sampled mutants"
            )
            lines.append(
                f"- Specs to inspect: `{', '.join(plan['module_specs'][file_path])}`"
            )
            lines.append("")
            survivor_rows: list[list[Any]] = []
            for item in file_results:
                survivor_rows.append(
                    [
                        item["mutant_id"],
                        f"{item['line']}:{item['column']}",
                        item["operator"],
                        f"{item['original']} -> {item['replacement']}",
                        item["source_excerpt"],
                    ]
                )
            _append_table(
                lines,
                ["mutant", "line:col", "operator", "change", "source"],
                survivor_rows,
            )

    lines.extend([
        "## Detailed Results By File",
        "",
    ])
    for file_path in plan["included_files"]:
        file_results = results_by_file[file_path]
        lines.append(f"### `{file_path}`")
        lines.append("")
        lines.append(f"- Specs: `{', '.join(plan['module_specs'][file_path])}`")
        lines.append(f"- Raw discovered mutants before sampling: `{raw_counts[file_path]}`")
        lines.append(f"- Sampled mutants in this run: `{len(file_results)}`")
        lines.append("")
        rows: list[list[Any]] = []
        for item in file_results:
            rows.append(
                [
                    item["status"],
                    item["mutant_id"],
                    f"{item['line']}:{item['column']}",
                    item["operator"],
                    f"{item['original']} -> {item['replacement']}",
                    item["source_excerpt"],
                    ", ".join(item["selected_specs"]),
                    item["exit_code"],
                    f"{item['duration_seconds']:.3f}s",
                ]
            )
        _append_table(
            lines,
            [
                "status",
                "mutant",
                "line:col",
                "operator",
                "change",
                "source",
                "specs",
                "exit",
                "duration",
            ],
            rows,
        )

    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Render a full mutation report for GitHub Actions review.")
    parser.add_argument("--plan", required=True)
    parser.add_argument("--aggregate", required=True)
    parser.add_argument("--reports", nargs="+", required=True)
    parser.add_argument("--preflight", default=None)
    args = parser.parse_args(argv)

    plan = read_json(Path(args.plan))
    aggregate = read_json(Path(args.aggregate))
    shard_reports = [read_json(Path(path)) for path in args.reports]
    preflight_bundles = _load_preflight(Path(args.preflight)) if args.preflight else []
    print(render_markdown(plan, aggregate, shard_reports, preflight_bundles))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
