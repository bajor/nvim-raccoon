from pathlib import Path
import unittest

from scripts.mutation.core import generate_mutations_for_source, is_invalid_output, mutate_source


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


if __name__ == "__main__":
    unittest.main()
