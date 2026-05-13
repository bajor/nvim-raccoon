from __future__ import annotations

import argparse
from pathlib import Path
import os
import sys

from .core import (
    DEFAULT_EQUIVALENTS_PATH,
    DEFAULT_MANIFEST_PATH,
    DEFAULT_POLICY_PATH,
    MutationError,
    aggregate_reports,
    build_plan,
    execute_shard,
    log,
    preflight,
    read_json,
    write_json,
)


def parse_operator_override(value: str | None) -> set[str] | None:
    if not value:
        return None
    return {item.strip() for item in value.split(",") if item.strip()}


def command_plan(args: argparse.Namespace) -> int:
    operator_override = parse_operator_override(args.operators)
    plan = build_plan(
        policy_path=Path(args.policy),
        manifest_path=Path(args.manifest),
        operator_override=operator_override,
    )
    preflight_results = preflight(plan, retry_count=1)
    write_json(Path(args.output), plan)
    if args.preflight_output:
        write_json(Path(args.preflight_output), {"bundles": preflight_results})
    log(f"wrote mutation plan to {args.output}")
    return 0


def command_shard(args: argparse.Namespace) -> int:
    plan = read_json(Path(args.plan))
    report = execute_shard(
        plan=plan,
        shard_index=args.shard_index,
        shard_count=args.shard_count,
        artifact_root=Path(args.artifact_dir),
        keep_failed_worktree=args.keep_failed_worktree,
        ci_mode=args.ci,
    )
    write_json(Path(args.output), report)
    log(f"wrote shard report to {args.output}")
    return 0


def command_aggregate(args: argparse.Namespace) -> int:
    plan = read_json(Path(args.plan))
    shard_reports = [read_json(Path(path)) for path in args.reports]
    summary_path = Path(os.environ["GITHUB_STEP_SUMMARY"]) if os.environ.get("GITHUB_STEP_SUMMARY") else None
    report = aggregate_reports(
        plan=plan,
        shard_reports=shard_reports,
        equivalents_path=Path(args.equivalents),
        summary_path=summary_path,
    )
    write_json(Path(args.output), report)
    log(f"wrote aggregate report to {args.output}")
    return 0 if report["passed"] else 1


def command_run(args: argparse.Namespace) -> int:
    output_root = Path(args.output_dir)
    output_root.mkdir(parents=True, exist_ok=True)
    plan_path = output_root / "plan.json"
    preflight_path = output_root / "preflight.json"
    aggregate_path = output_root / "aggregate.json"
    operator_override = parse_operator_override(args.operators)

    plan = build_plan(
        policy_path=Path(args.policy),
        manifest_path=Path(args.manifest),
        operator_override=operator_override,
    )
    preflight_results = preflight(plan, retry_count=1)
    write_json(plan_path, plan)
    write_json(preflight_path, {"bundles": preflight_results})

    reports = []
    for shard_index in range(args.shards):
        shard_artifact_dir = output_root / "artifacts" / f"shard-{shard_index}"
        shard_report_path = output_root / "reports" / f"shard-{shard_index}.json"
        report = execute_shard(
            plan=plan,
            shard_index=shard_index,
            shard_count=args.shards,
            artifact_root=shard_artifact_dir,
            keep_failed_worktree=True,
            ci_mode=False,
        )
        write_json(shard_report_path, report)
        reports.append(report)

    summary_path = output_root / "summary.md"
    aggregate = aggregate_reports(
        plan=plan,
        shard_reports=reports,
        equivalents_path=Path(args.equivalents),
        summary_path=summary_path,
    )
    write_json(aggregate_path, aggregate)
    log(f"local mutation output retained at {output_root}")
    return 0 if aggregate["passed"] else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run mutation testing for raccoon.nvim")
    subparsers = parser.add_subparsers(dest="command", required=True)

    plan_parser = subparsers.add_parser("plan", help="Generate and validate the mutation plan")
    plan_parser.add_argument("--policy", default=str(DEFAULT_POLICY_PATH))
    plan_parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST_PATH))
    plan_parser.add_argument("--operators", default=None)
    plan_parser.add_argument("--output", required=True)
    plan_parser.add_argument("--preflight-output", default=None)
    plan_parser.set_defaults(func=command_plan)

    shard_parser = subparsers.add_parser("shard", help="Execute one shard of the mutation plan")
    shard_parser.add_argument("--plan", required=True)
    shard_parser.add_argument("--shard-index", type=int, required=True)
    shard_parser.add_argument("--shard-count", type=int, required=True)
    shard_parser.add_argument("--artifact-dir", required=True)
    shard_parser.add_argument("--output", required=True)
    shard_parser.add_argument("--ci", action="store_true")
    shard_parser.add_argument("--keep-failed-worktree", action="store_true")
    shard_parser.set_defaults(func=command_shard)

    aggregate_parser = subparsers.add_parser("aggregate", help="Aggregate shard reports")
    aggregate_parser.add_argument("--plan", required=True)
    aggregate_parser.add_argument("--reports", nargs="+", required=True)
    aggregate_parser.add_argument("--equivalents", default=str(DEFAULT_EQUIVALENTS_PATH))
    aggregate_parser.add_argument("--output", required=True)
    aggregate_parser.set_defaults(func=command_aggregate)

    run_parser = subparsers.add_parser("run", help="Run mutation testing locally")
    run_parser.add_argument("--policy", default=str(DEFAULT_POLICY_PATH))
    run_parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST_PATH))
    run_parser.add_argument("--equivalents", default=str(DEFAULT_EQUIVALENTS_PATH))
    run_parser.add_argument("--operators", default=None)
    run_parser.add_argument("--shards", type=int, required=True)
    run_parser.add_argument("--output-dir", required=True)
    run_parser.set_defaults(func=command_run)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except MutationError as exc:
        print(f"[mutation] error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

