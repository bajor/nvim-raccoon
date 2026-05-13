from pathlib import Path
import tempfile
import unittest

from scripts.mutation.render_report import render_markdown


class MutationRenderReportTests(unittest.TestCase):
    def test_render_markdown_includes_preflight_scope_and_detailed_results(self) -> None:
        plan = {
            "included_files": ["lua/raccoon/example.lua"],
            "module_specs": {
                "lua/raccoon/example.lua": ["tests/example_spec.lua"],
            },
            "mutants": [
                {
                    "mutant_id": "mut-1",
                    "ordinal": 1,
                    "file_path": "lua/raccoon/example.lua",
                    "operator": "comparison_equality",
                    "line": 2,
                    "column": 12,
                    "start_offset": 12,
                    "end_offset": 14,
                    "original": "==",
                    "replacement": "~=",
                    "selected_specs": ["tests/example_spec.lua"],
                    "source_excerpt": "if value == nil then",
                }
            ],
            "policy": {
                "included_roots": ["lua"],
                "operators": ["comparison_equality"],
                "max_mutants_per_file": 16,
                "max_summary_entries": 20,
                "timeout_seconds": 60,
            },
        }
        aggregate = {
            "passed": False,
            "score_percent": 0.0,
            "threshold_percent": 80,
            "eligible_mutants": 1,
            "total_generated": 1,
            "killed": 0,
            "survived": 1,
            "equivalent": 0,
            "invalid": 0,
            "timeout": 0,
            "runner_error": 0,
            "fail_reasons": ["score_below_threshold"],
        }
        shard_reports = [
            {
                "results": [
                    {
                        "mutant_id": "mut-1",
                        "file_path": "lua/raccoon/example.lua",
                        "operator": "comparison_equality",
                        "line": 2,
                        "column": 12,
                        "selected_specs": ["tests/example_spec.lua"],
                        "status": "survived",
                        "duration_seconds": 0.015,
                        "exit_code": 0,
                        "output": "all tests passed",
                    }
                ]
            }
        ]
        preflight_bundles = [
            {
                "modules": ["lua/raccoon/example.lua"],
                "specs": ["tests/example_spec.lua"],
                "exit_code": 0,
                "stdout": "",
                "stderr": "",
                "duration_seconds": 0.042,
                "attempt": 1,
            }
        ]

        with tempfile.TemporaryDirectory() as repo_dir:
            repo_root = Path(repo_dir)
            example_path = repo_root / "lua" / "raccoon" / "example.lua"
            example_path.parent.mkdir(parents=True, exist_ok=True)
            example_path.write_text("local value = 1\nif value == nil then\n  return true\nend\n", encoding="utf-8")

            from scripts.mutation import render_report as render_module

            original_root = render_module.REPO_ROOT
            render_module.REPO_ROOT = repo_root
            try:
                markdown = render_markdown(plan, aggregate, shard_reports, preflight_bundles)
            finally:
                render_module.REPO_ROOT = original_root

        self.assertIn("# Full Mutation Report", markdown)
        self.assertIn("## Preflight Bundles", markdown)
        self.assertIn("## File Breakdown", markdown)
        self.assertIn("## Survivors To Inspect First", markdown)
        self.assertIn("## Detailed Results By File", markdown)
        self.assertIn("raw discovered mutants before sampling", markdown.lower())
        self.assertIn("mut-1", markdown)
        self.assertIn("if value == nil then", markdown)
        self.assertIn("tests/example_spec.lua", markdown)


if __name__ == "__main__":
    unittest.main()
