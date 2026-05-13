from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

from scripts.mutation.core import (
    add_worktree,
    build_overlay_excluded_prefixes,
    generate_mutations_for_source,
    is_invalid_output,
    mutate_source,
    overlay_workspace,
)


class MutationCoreTests(unittest.TestCase):
    def test_generates_expected_operator_kinds(self) -> None:
        source = """local count = 0
if enabled and value == nil then
  local value = count + 1
  return false
  vim.notify("hello")
end
"""
        mutants = generate_mutations_for_source(
            file_path="lua/raccoon/example.lua",
            source=source,
            selected_specs=["tests/example_spec.lua"],
            allowed_operators={
                "arithmetic_simple",
                "logical_connector",
                "nil_guard_invert",
                "boolean_literal",
                "delete_return",
                "delete_local",
                "delete_call",
            },
        )
        operators = {mutant.operator for mutant in mutants}
        self.assertEqual(
            {
                "arithmetic_simple",
                "logical_connector",
                "nil_guard_invert",
                "boolean_literal",
                "delete_local",
                "delete_return",
                "delete_call",
            },
            operators,
        )

    def test_delete_assignment_replaces_only_target_line(self) -> None:
        source = "local value = 1\nif true then\n  value = value + 1\nend\nreturn value\n"
        mutants = generate_mutations_for_source(
            file_path="lua/raccoon/example.lua",
            source=source,
            selected_specs=["tests/example_spec.lua"],
            allowed_operators={"delete_assignment"},
        )
        self.assertEqual(1, len(mutants))
        mutated = mutate_source(source, mutants[0])
        self.assertIn("-- mutation: deleted statement", mutated)
        self.assertIn("return value", mutated)

    def test_skips_deletion_for_multiline_structure_openers(self) -> None:
        source = "if true then\n  local payload = {\n    value = 1,\n  }\nend\n"
        mutants = generate_mutations_for_source(
            file_path="lua/raccoon/example.lua",
            source=source,
            selected_specs=["tests/example_spec.lua"],
            allowed_operators={"delete_local"},
        )
        self.assertEqual([], mutants)

    def test_invalid_output_detection_flags_parse_failures(self) -> None:
        self.assertTrue(is_invalid_output("error loading module 'raccoon.api': syntax error near ')'"))
        self.assertTrue(is_invalid_output("FAILED TO LOAD FILE"))
        self.assertFalse(is_invalid_output("Tests Failed. Exit: 1"))

    def test_build_overlay_excluded_prefixes_adds_repo_local_output_root(self) -> None:
        prefixes = build_overlay_excluded_prefixes(Path("tmp/mutation-output/artifacts/shard-0"))
        self.assertIn("tmp/mutation-output", prefixes)
        self.assertIn("mutation-plan", prefixes)

    def test_overlay_workspace_skips_repo_local_mutation_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as repo_dir, tempfile.TemporaryDirectory() as worktree_dir:
            repo_root = Path(repo_dir)
            tracked_file = repo_root / "lua" / "raccoon" / "example.lua"
            tracked_file.parent.mkdir(parents=True, exist_ok=True)
            tracked_file.write_text("return true\n", encoding="utf-8")

            mutation_plan_file = repo_root / "mutation-plan" / "plan.json"
            mutation_plan_file.parent.mkdir(parents=True, exist_ok=True)
            mutation_plan_file.write_text("{}", encoding="utf-8")

            shard_report_file = repo_root / "mutation-shards" / "shard-0" / "report.json"
            shard_report_file.parent.mkdir(parents=True, exist_ok=True)
            shard_report_file.write_text("{}", encoding="utf-8")

            tracked_result = subprocess.CompletedProcess(
                args=[],
                returncode=0,
                stdout=(
                    b"lua/raccoon/example.lua\0"
                    b"mutation-plan/plan.json\0"
                    b"mutation-shards/shard-0/report.json\0"
                ),
            )
            deleted_result = subprocess.CompletedProcess(args=[], returncode=0, stdout=b"")

            with (
                mock.patch("scripts.mutation.core.REPO_ROOT", repo_root),
                mock.patch(
                    "scripts.mutation.core.subprocess.run",
                    side_effect=[tracked_result, deleted_result],
                ),
            ):
                overlay_workspace(
                    Path(worktree_dir),
                    build_overlay_excluded_prefixes(Path("mutation-shards/shard-0/artifacts")),
                )

            self.assertTrue((Path(worktree_dir) / "lua" / "raccoon" / "example.lua").exists())
            self.assertFalse((Path(worktree_dir) / "mutation-plan" / "plan.json").exists())
            self.assertFalse((Path(worktree_dir) / "mutation-shards" / "shard-0" / "report.json").exists())

    def test_add_worktree_uses_system_temp_root(self) -> None:
        worktree_path = "/tmp/raccoon-mutation-worktree-test"
        with (
            mock.patch("scripts.mutation.core.tempfile.mkdtemp", return_value=worktree_path) as mkdtemp,
            mock.patch("scripts.mutation.core.subprocess.run"),
        ):
            self.assertEqual(Path(worktree_path), add_worktree())
        mkdtemp.assert_called_once_with(prefix="raccoon-mutation-worktree-")


if __name__ == "__main__":
    unittest.main()
