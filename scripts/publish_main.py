from __future__ import annotations

import argparse
import shutil
from pathlib import Path, PurePosixPath


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ALLOWLIST_PATH = REPO_ROOT / ".github" / "publish-allowlist.txt"


class PublishError(RuntimeError):
    """Raised when the publish tree cannot be built or validated."""


def load_allowlist(path: Path) -> list[str]:
    entries: list[str] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        entry = raw_line.strip()
        if not entry or entry.startswith("#"):
            continue
        normalized = PurePosixPath(entry).as_posix()
        if normalized.startswith("../") or normalized == ".." or normalized.startswith("/"):
            raise PublishError(f"Invalid allowlist entry: {entry}")
        entries.append(normalized)
    if not entries:
        raise PublishError(f"Allowlist is empty: {path}")
    return entries


def is_allowed_path(relative_path: str, entries: list[str]) -> bool:
    return any(
        relative_path == entry or relative_path.startswith(f"{entry}/")
        for entry in entries
    )


def copy_entry(source_root: Path, output_root: Path, entry: str) -> None:
    source = source_root / entry
    target = output_root / entry
    if not source.exists():
        raise PublishError(f"Allowlist entry is missing from source tree: {entry}")
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, target, dirs_exist_ok=True)
    else:
        shutil.copy2(source, target)


def build_publish_tree(
    source_root: Path,
    output_root: Path,
    allowlist_path: Path = DEFAULT_ALLOWLIST_PATH,
) -> list[str]:
    entries = load_allowlist(allowlist_path)
    if output_root.exists():
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True, exist_ok=True)
    for entry in entries:
        copy_entry(source_root, output_root, entry)
    validate_publish_tree(output_root, entries)
    return entries


def validate_publish_tree(root: Path, entries: list[str]) -> None:
    unexpected = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if not is_allowed_path(relative, entries):
            unexpected.append(relative)
    if unexpected:
        joined = ", ".join(sorted(unexpected))
        raise PublishError(f"Unexpected files in publish tree: {joined}")


def command_build(args: argparse.Namespace) -> int:
    build_publish_tree(
        source_root=Path(args.source_root),
        output_root=Path(args.output),
        allowlist_path=Path(args.allowlist),
    )
    return 0


def command_validate(args: argparse.Namespace) -> int:
    entries = load_allowlist(Path(args.allowlist))
    validate_publish_tree(Path(args.root), entries)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build and validate the stripped main-branch tree.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build_parser = subparsers.add_parser("build", help="Build the stripped publish tree")
    build_parser.add_argument("--source-root", default=str(REPO_ROOT))
    build_parser.add_argument("--allowlist", default=str(DEFAULT_ALLOWLIST_PATH))
    build_parser.add_argument("--output", required=True)
    build_parser.set_defaults(func=command_build)

    validate_parser = subparsers.add_parser("validate", help="Validate an existing publish tree")
    validate_parser.add_argument("--allowlist", default=str(DEFAULT_ALLOWLIST_PATH))
    validate_parser.add_argument("--root", required=True)
    validate_parser.set_defaults(func=command_validate)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except PublishError as exc:
        parser.exit(status=2, message=f"[publish] error: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
