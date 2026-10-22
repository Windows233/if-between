"""地图盘点工具的标准库 unittest；所有地图均为临时 fixture。

覆盖字段计数、坏输入隔离、ID 唯一性、稳定 JSON 和输出保护，避免盘点静默丢数据。

python -B -m unittest discover -s tests -p test_map_migration_audit.py -v
"""

from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tools import audit_map_migration as audit


class MapMigrationAuditTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.maps = self.root / "maps"
        self.maps.mkdir()

    def write_map(self, name="room.json", **fields):
        data = {"id": Path(name).stem, "size": [320, 180]}
        data.update(fields)
        path = self.maps / name
        path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        return path

    def run_cli(self, *arguments):
        environment = os.environ.copy()
        environment["PYTHONUTF8"] = "1"
        return subprocess.run(
            [sys.executable, "-B", str(Path(audit.__file__)), "--maps-dir", str(self.maps), *arguments],
            capture_output=True, encoding="utf-8", env=environment, timeout=15,
        )

    def test_valid_fields_and_totals(self):
        self.write_map(
            background="res://地图/房间.png", overlay="res://地图/前景.png",
            walls=[[0, 0, 10, 8]], portals=[{"to": "yard"}], spawns={"start": [20, 20]},
            editor_groups=[{"id": "group_1", "name": "家具", "members": ["desk", "chair"]}],
            actors=[
                {"id": "desk", "label": "桌子", "rect": [10, 10, 30, 40],
                 "sprite": "res://art/desk.png", "solid": True, "cover": True, "over": False,
                 "reach": [0, 5, 40, 50], "reach_local": [-5, 0, 40, 50],
                 "collision": [[0, 10, 30, 20], [0, 30, 10, 10]],
                 "cover_y": 23, "sort_offset": -2, "sort_collider": 1},
                {"id": "chair", "rect": [60, 10, 10, 20], "sprite": "",
                 "solid": False, "cover": False, "over": True, "collision": []},
            ],
        )
        report = audit.audit_maps(self.maps)
        self.assertEqual([], report["issues"])
        self.assertEqual("inventory_only", report["purpose"])
        self.assertIn("不是迁移建议", report["notice"])
        entry = report["maps"][0]
        self.assertEqual([320, 180], entry["mapsize"])
        self.assertEqual("res://地图/房间.png", entry["background"])
        self.assertEqual("res://地图/前景.png", entry["overlay"])
        counts = report["totals"]["counts"]
        for key in ("walls", "portals", "spawns", "editor_groups", "solid_true", "cover_true",
                    "over_true", "actors_with_both_reach", "actors_with_empty_collision", "actors_with_sprite"):
            self.assertEqual(1, counts[key], key)
        self.assertEqual(2, counts["actors"])
        self.assertEqual(2, counts["collision_shapes"])
        self.assertEqual(0, counts["invalid_collision_shapes"])
        fields = report["totals"]["actor_field_counts"]
        self.assertEqual(1, fields["reach"])
        self.assertEqual(1, fields["reach_local"])
        self.assertEqual(2, fields["sprite"])
        self.assertEqual(1, fields["cover_y"])
        self.assertEqual(1, fields["sort_offset"])
        self.assertTrue(entry["editor_groups"]["present"])
        self.assertTrue(entry["actor_ids"]["all_nonempty_unique"])
        actor = entry["actors"][0]
        self.assertEqual(2, actor["collision_shape_count"])
        self.assertEqual([[0, 10, 30, 20], [0, 30, 10, 10]], actor["fields"]["collision"])
        self.assertEqual([0, 5, 40, 50], actor["fields"]["reach"])
        self.assertEqual([-5, 0, 40, 50], actor["fields"]["reach_local"])
        self.assertEqual(-2, actor["fields"]["sort_offset"])

    def test_optional_fields_are_absent_not_inferred(self):
        self.write_map(actors=[{"id": "baked_into_background", "solid": True, "cover": True}])
        report = audit.audit_maps(self.maps)
        self.assertEqual([], report["issues"])
        entry = report["maps"][0]
        fields = entry["actors"][0]["fields"]
        self.assertNotIn("collision", fields)
        self.assertNotIn("reach_local", fields)
        self.assertNotIn("cover_y", fields)
        self.assertNotIn("sprite", fields)
        self.assertIsNone(entry["actors"][0]["collision_shape_count"])
        self.assertEqual(0, entry["counts"]["walls"])
        self.assertEqual(1, entry["counts"]["actors_without_explicit_reach"])
        self.assertFalse(entry["editor_groups"]["present"])

    def test_bad_json_root_and_encoding_do_not_hide_valid_maps(self):
        self.write_map("valid.json", actors=[{"id": "desk"}])
        (self.maps / "bad.json").write_text('{"actors": [', encoding="utf-8")
        (self.maps / "root.json").write_text("[]", encoding="utf-8")
        (self.maps / "encoding.json").write_bytes(b"\xff")
        report = audit.audit_maps(self.maps)
        self.assertEqual(4, report["totals"]["files"])
        self.assertEqual(1, report["totals"]["parsed_maps"])
        self.assertEqual(3, report["totals"]["unreadable_or_invalid_maps"])
        self.assertEqual(1, report["totals"]["counts"]["actors"])
        self.assertEqual(3, report["totals"]["unknown_counts"]["actors"])
        self.assertEqual({"invalid_json", "invalid_map_root", "unreadable_map"},
                         {problem["code"] for problem in report["issues"]})
        self.assertEqual(["bad.json", "encoding.json", "root.json", "valid.json"],
                         [entry["file"] for entry in report["maps"]])

    def test_nonstandard_and_overflow_numbers_are_reported(self):
        for index, number in enumerate(("NaN", "Infinity", "-Infinity", "1e9999")):
            (self.maps / f"bad{index}.json").write_text('{"size": [320, ' + number + '] }', encoding="utf-8")
        report = audit.audit_maps(self.maps)
        self.assertEqual(4, report["totals"]["unreadable_or_invalid_maps"])
        self.assertTrue(all(problem["code"] == "invalid_json" for problem in report["issues"]))
        json.loads(audit.report_json(report))

    def test_duplicate_empty_missing_and_nonstring_ids(self):
        self.write_map(actors=[{"id": "desk"}, {"id": ""}, {"id": "desk"},
                               {"id": "  "}, {}, {"id": 7}, {"id": "Desk"}, None])
        report = audit.audit_maps(self.maps)
        entry = report["maps"][0]
        self.assertFalse(entry["actor_ids"]["all_nonempty_unique"])
        self.assertEqual([{"id": "desk", "indices": [0, 2]}], entry["actor_ids"]["duplicates"])
        self.assertEqual(["duplicate", "empty", "duplicate", "empty", "missing", "invalid", "unique", "invalid_actor"],
                         [actor["id_status"] for actor in entry["actors"]])
        counts = report["totals"]["counts"]
        self.assertEqual(8, counts["actors"])
        self.assertEqual(7, counts["actor_records"])
        self.assertEqual(2, counts["actors_empty_id"])
        self.assertEqual(1, counts["actors_missing_id"])
        self.assertEqual(1, counts["actors_invalid_id"])
        self.assertEqual(1, counts["duplicate_actor_ids"])
        self.assertEqual(2, counts["actors_with_duplicate_id"])
        self.assertEqual(1, counts["invalid_actor_entries"])

    def test_actor_ids_are_scoped_to_each_map(self):
        self.write_map("day.json", actors=[{"id": "desk"}])
        self.write_map("night.json", actors=[{"id": "desk"}])
        report = audit.audit_maps(self.maps)
        self.assertEqual([], report["issues"])
        self.assertEqual(0, report["totals"]["counts"]["duplicate_actor_ids"])

    def test_invalid_collections_are_unknown_not_string_lengths(self):
        self.write_map("invalid.json", walls="wall", portals={}, actors=None, spawns=[], editor_groups={})
        self.write_map("valid.json", walls=[[0, 0, 10, 10]], actors=[{"id": "desk"}])
        report = audit.audit_maps(self.maps)
        entry = report["maps"][0]
        for key in audit.COLLECTIONS:
            self.assertIsNone(entry["counts"][key])
            self.assertEqual(1, report["totals"]["unknown_counts"][key])
        self.assertIsNone(entry["actor_ids"]["all_nonempty_unique"])
        self.assertEqual(1, report["totals"]["counts"]["walls"])
        self.assertEqual(1, report["totals"]["counts"]["actors"])
        self.assertEqual(5, len(report["issues"]))

    def test_invalid_geometry_and_flags_preserve_raw_values(self):
        self.write_map(actors=[
            {"id": "desk", "solid": 1, "sprite": None, "reach": [0, 0, 0, 1],
             "reach_local": [0, True, 1, 1], "collision": [[0, 0, 1, 1], [0, 0, -1, 1], {"type": "polygon"}],
             "cover": True, "sort_collider": 8, "cover_y": "auto", "sort_offset": False},
            {"id": "chair", "collision": "rectangle"},
        ])
        report = audit.audit_maps(self.maps)
        counts = report["totals"]["counts"]
        self.assertEqual(3, counts["collision_shapes"])
        self.assertEqual(2, counts["invalid_collision_shapes"])
        self.assertEqual(0, counts["solid_true"])
        self.assertEqual(2, report["totals"]["actor_field_counts"]["collision"])
        fields = report["maps"][0]["actors"][0]["fields"]
        self.assertEqual({"type": "polygon"}, fields["collision"][2])
        self.assertEqual("auto", fields["cover_y"])
        codes = {problem["code"] for problem in report["issues"]}
        self.assertTrue({"invalid_flag", "invalid_sprite", "invalid_rectangle", "invalid_sort_number",
                         "invalid_sort_collider", "invalid_collision_shape", "invalid_collision"} <= codes)

    def test_stable_map_issue_and_object_key_ordering(self):
        self.write_map("z.json", actors=[{"id": "same"}, {"id": "same"}])
        self.write_map("a.json", actors=[{"id": "two"}, {"id": "one"}], spawns={"z": [1, 2], "a": [3, 4]})
        nested = self.maps / "nested"
        nested.mkdir()
        (nested / "ignored.json").write_text("bad", encoding="utf-8")
        (self.maps / "ignored.txt").write_text("bad", encoding="utf-8")
        first = audit.report_json(audit.audit_maps(self.maps))
        data = json.loads((self.maps / "a.json").read_text(encoding="utf-8"))
        data["spawns"] = dict(reversed(list(data["spawns"].items())))
        (self.maps / "a.json").write_text(json.dumps(dict(reversed(list(data.items())))), encoding="utf-8")
        second = audit.report_json(audit.audit_maps(self.maps))
        self.assertEqual(first, second)
        report = json.loads(first)
        self.assertEqual(["a.json", "z.json"], [entry["file"] for entry in report["maps"]])
        self.assertEqual(["two", "one"], [actor["fields"]["id"] for actor in report["maps"][0]["actors"]])
        self.assertNotIn(str(self.root), first)

    def test_scanning_preserves_map_bytes_names_and_mtimes(self):
        self.write_map(actors=[{"id": "desk", "reach": [1, 2, 3, 4]}])
        (self.maps / "bad.json").write_bytes(b"broken")
        before = {path.name: (path.read_bytes(), path.stat().st_mtime_ns) for path in self.maps.iterdir()}
        audit.audit_maps(self.maps)
        after = {path.name: (path.read_bytes(), path.stat().st_mtime_ns) for path in self.maps.iterdir()}
        self.assertEqual(before, after)

    def test_cli_stdout_and_output_match_without_logs(self):
        self.write_map(background="res://地图/房间.png", actors=[{"id": "desk"}])
        stdout = self.run_cli()
        self.assertEqual(0, stdout.returncode, stdout.stderr)
        self.assertEqual("", stdout.stderr)
        output = self.root / "report.json"
        saved = self.run_cli("--output", str(output))
        self.assertEqual(0, saved.returncode, saved.stderr)
        self.assertEqual("", saved.stdout)
        self.assertEqual("", saved.stderr)
        self.assertEqual(stdout.stdout, output.read_text(encoding="utf-8"))
        self.assertEqual(1, json.loads(stdout.stdout)["totals"]["files"])
        self.assertNotIn(b"\r\n", output.read_bytes())

    def test_cli_problem_exit_still_produces_json(self):
        (self.maps / "bad.json").write_text("{", encoding="utf-8")
        result = self.run_cli()
        self.assertEqual(1, result.returncode)
        self.assertEqual("", result.stderr)
        self.assertEqual("invalid_json", json.loads(result.stdout)["issues"][0]["code"])

    def test_output_cannot_overwrite_or_add_any_map_file(self):
        source = self.write_map()
        before = source.read_bytes()
        for output in (source, self.maps / "new.json", self.maps / "subdir" / "report.json"):
            with self.subTest(output=output):
                result = self.run_cli("--output", str(output))
                self.assertEqual(2, result.returncode)
                self.assertEqual("", result.stdout)
                self.assertIn("cannot write inside a map directory", result.stderr)
        self.assertEqual(before, source.read_bytes())
        self.assertEqual([source], list(self.maps.iterdir()))

    def test_hardlinked_map_cannot_be_used_as_output(self):
        source = self.write_map()
        output = self.root / "report.json"
        try:
            os.link(source, output)
        except OSError as error:
            self.skipTest("Hard links unavailable: " + str(error))
        before = source.read_bytes()
        result = self.run_cli("--output", str(output))
        self.assertEqual(2, result.returncode)
        self.assertIn("cannot overwrite a map", result.stderr)
        self.assertEqual(before, source.read_bytes())

    def test_missing_or_empty_directory_is_reported(self):
        empty = audit.audit_maps(self.maps)
        missing = audit.audit_maps(self.root / "missing")
        self.assertEqual("no_map_files", empty["issues"][0]["code"])
        self.assertEqual("unreadable_maps_directory", missing["issues"][0]["code"])
        self.assertEqual(0, missing["totals"]["files"])

    def test_output_failure_has_a_distinct_exit_code(self):
        self.write_map()
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = audit.main(["--maps-dir", str(self.maps), "--output", str(self.root / "missing" / "report.json")])
        self.assertEqual(2, result)
        self.assertEqual("", stdout.getvalue())
        self.assertIn("audit_map_migration:", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
