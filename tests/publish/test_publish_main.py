from pathlib import Path
import tempfile
import unittest

from scripts.publish_main import (
    DEFAULT_ALLOWLIST_PATH,
    PublishError,
    build_publish_tree,
    is_allowed_path,
    load_allowlist,
    validate_publish_tree,
)


class PublishMainTests(unittest.TestCase):
    def test_load_allowlist_ignores_comments_and_blank_lines(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            allowlist_path = Path(temp_dir) / "allowlist.txt"
            allowlist_path.write_text(
                "# comment\n\nplugin\nREADME.md\n.github/workflows/main-guard.yml\n",
                encoding="utf-8",
            )
            self.assertEqual(
                ["plugin", "README.md", ".github/workflows/main-guard.yml"],
                load_allowlist(allowlist_path),
            )

    def test_build_publish_tree_copies_only_allowlisted_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source_root = root / "source"
            output_root = root / "output"
            allowlist_path = root / "allowlist.txt"

            (source_root / "plugin").mkdir(parents=True, exist_ok=True)
            (source_root / "plugin" / "raccoon.lua").write_text("return true\n", encoding="utf-8")
            (source_root / "README.md").write_text("# docs\n", encoding="utf-8")
            (source_root / "tests").mkdir(parents=True, exist_ok=True)
            (source_root / "tests" / "ignored_spec.lua").write_text("return false\n", encoding="utf-8")

            allowlist_path.write_text("plugin\nREADME.md\n", encoding="utf-8")

            build_publish_tree(source_root, output_root, allowlist_path)

            self.assertTrue((output_root / "plugin" / "raccoon.lua").exists())
            self.assertTrue((output_root / "README.md").exists())
            self.assertFalse((output_root / "tests").exists())

    def test_validate_publish_tree_rejects_unexpected_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            publish_root = root / "publish"
            publish_root.mkdir(parents=True, exist_ok=True)
            (publish_root / "README.md").write_text("# docs\n", encoding="utf-8")
            (publish_root / "tests").mkdir(parents=True, exist_ok=True)
            (publish_root / "tests" / "leaked_spec.lua").write_text("return false\n", encoding="utf-8")

            with self.assertRaises(PublishError):
                validate_publish_tree(publish_root, ["README.md"])

    def test_validate_publish_tree_rejects_missing_allowlisted_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            publish_root = root / "publish"
            publish_root.mkdir(parents=True, exist_ok=True)
            (publish_root / "plugin").mkdir(parents=True, exist_ok=True)

            with self.assertRaisesRegex(PublishError, "Missing allowlisted paths"):
                validate_publish_tree(publish_root, ["README.md", "plugin"])

    def test_default_allowlist_keeps_lua_tests_and_excludes_python_publish_helpers(self) -> None:
        entries = load_allowlist(DEFAULT_ALLOWLIST_PATH)

        self.assertTrue(is_allowed_path("tests/api_spec.lua", entries))
        self.assertTrue(is_allowed_path("tests/e2e/workflow_spec.lua", entries))
        self.assertTrue(is_allowed_path("tests/helpers/mocks.lua", entries))
        self.assertFalse(is_allowed_path("tests/publish/test_publish_main.py", entries))
        self.assertFalse(is_allowed_path("tests/mutation/test_core.py", entries))


if __name__ == "__main__":
    unittest.main()
