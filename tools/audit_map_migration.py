"""只读盘点 data/maps/*.json，为人工审核提供原始字段和计数。

这是盘点报告，不是迁移建议；不推断墙体归属、不生成碰撞、不修改地图。
mapsize 来自现有 schema 的 size；actors[].fields 只包含实际存在的字段。

python -B tools/audit_map_migration.py [--maps-dir DIR] [--output REPORT.json]
默认只打印 JSON。退出码：0 无问题，1 报告含数据问题，2 参数或输出错误。
计数为 null 表示字段类型错误、无法计数；总计另列 unknown_counts，避免当成零。
"""

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import sys


DEFAULT_MAPS_DIR = Path(__file__).resolve().parents[1] / "data" / "maps"
NOTICE = "这是只读盘点报告，不是迁移建议；未推断碰撞归属，未迁移或修改地图。"
ACTOR_FIELDS = (
    "id", "label", "rect", "sprite", "solid", "cover", "over", "reach",
    "reach_local", "collision", "sort_collider", "cover_y", "sort_offset",
)
COLLECTIONS = {"walls": list, "portals": list, "actors": list,
               "spawns": dict, "editor_groups": list}
COUNT_KEYS = (
    *COLLECTIONS, "actor_records", "invalid_actor_entries", "actors_with_sprite",
    "solid_true", "cover_true", "over_true", "actors_with_both_reach",
    "actors_without_explicit_reach", "collision_shapes", "invalid_collision_shapes",
    "actors_with_empty_collision", "actors_missing_id", "actors_empty_id",
    "actors_invalid_id", "duplicate_actor_ids", "actors_with_duplicate_id",
)


def _problem(issues, filename, location, code, message):
    issues.append({"file": filename, "path": location, "code": code, "message": message})


def _finite_number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    return not isinstance(value, float) or math.isfinite(value)


def _valid_rect(value):
    return (isinstance(value, list) and len(value) == 4
            and all(_finite_number(part) for part in value)
            and value[2] > 0 and value[3] > 0)


def _finite_float(text):
    value = float(text)
    if not math.isfinite(value):
        raise ValueError("non-finite JSON number")
    return value


def _reject_constant(text):
    raise ValueError("non-standard JSON number: " + text)


def _actor_ids(actors, filename, issues, counts):
    indices_by_id = {}
    statuses = []
    for index, actor in enumerate(actors):
        if not isinstance(actor, dict):
            statuses.append("invalid_actor")
            continue
        actor_id = actor.get("id")
        if "id" not in actor:
            status = "missing"
        elif not isinstance(actor_id, str):
            status = "invalid"
        elif not actor_id.strip():
            status = "empty"
        else:
            indices_by_id.setdefault(actor_id, []).append(index)
            statuses.append("unique")
            continue
        statuses.append(status)
        counts["actors_" + status + "_id"] += 1
        _problem(issues, filename, f"actors[{index}].id", "actor_id_" + status,
                 "Actor ID must be a nonempty string.")
    duplicates = []
    for actor_id, indices in sorted(indices_by_id.items()):
        if len(indices) < 2:
            continue
        duplicates.append({"id": actor_id, "indices": indices})
        for index in indices:
            statuses[index] = "duplicate"
            _problem(issues, filename, f"actors[{index}].id", "actor_id_duplicate",
                     "Actor ID occurs more than once in this map.")
    counts["duplicate_actor_ids"] = len(duplicates)
    counts["actors_with_duplicate_id"] = sum(len(item["indices"]) for item in duplicates)
    return statuses, {
        "all_nonempty_unique": all(status == "unique" for status in statuses),
        "distinct_nonempty_ids": len(indices_by_id),
        "duplicates": duplicates,
    }


def _collision(actor, filename, location, issues, counts):
    if "collision" not in actor:
        return None
    shapes = actor["collision"]
    if not isinstance(shapes, list):
        _problem(issues, filename, location + ".collision", "invalid_collision",
                 "Local collision must be an array of [x, y, width, height] rectangles.")
        return None
    counts["collision_shapes"] += len(shapes)
    counts["actors_with_empty_collision"] += not shapes
    for shape_index, shape in enumerate(shapes):
        if not _valid_rect(shape):
            counts["invalid_collision_shapes"] += 1
            _problem(issues, filename, f"{location}.collision[{shape_index}]",
                     "invalid_collision_shape", "Expected a finite rectangle with positive size.")
    reference = actor.get("sort_collider", 0)
    if actor.get("cover") is True and actor.get("over", False) is False:
        if (not isinstance(reference, int) or isinstance(reference, bool)
                or not 0 <= reference < len(shapes)):
            _problem(issues, filename, location + ".sort_collider", "invalid_sort_collider",
                     "Sorting reference does not identify a local collision rectangle.")
    return len(shapes)


def _actor_record(actor, index, status, filename, issues, counts, field_counts):
    location = f"actors[{index}]"
    if not isinstance(actor, dict):
        counts["invalid_actor_entries"] += 1
        _problem(issues, filename, location, "invalid_actor", "Actor entry must be an object.")
        return {"index": index, "id_status": status, "raw": actor}
    counts["actor_records"] += 1
    fields = {key: actor[key] for key in ACTOR_FIELDS if key in actor}
    field_counts.update(fields.keys())
    counts["actors_with_sprite"] += isinstance(actor.get("sprite"), str) and bool(actor["sprite"])
    counts["actors_with_both_reach"] += "reach" in actor and "reach_local" in actor
    counts["actors_without_explicit_reach"] += "reach" not in actor and "reach_local" not in actor
    for flag in ("solid", "cover", "over"):
        counts[flag + "_true"] += actor.get(flag) is True
        if flag in actor and not isinstance(actor[flag], bool):
            _problem(issues, filename, location + "." + flag, "invalid_flag",
                     "Flag must be a JSON boolean; the raw value has been preserved.")
    if "sprite" in actor and not isinstance(actor["sprite"], str):
        _problem(issues, filename, location + ".sprite", "invalid_sprite", "Sprite must be a string.")
    for key in ("rect", "reach", "reach_local"):
        if key in actor and not _valid_rect(actor[key]):
            _problem(issues, filename, location + "." + key, "invalid_rectangle",
                     "Expected [x, y, width, height] with finite numbers and positive size.")
    for key in ("cover_y", "sort_offset"):
        if key in actor and not _finite_number(actor[key]):
            _problem(issues, filename, location + "." + key, "invalid_sort_number",
                     "Sorting field must be a finite number.")
    shape_count = _collision(actor, filename, location, issues, counts)
    return {"index": index, "id_status": status, "fields": fields,
            "collision_shape_count": shape_count}


def _audit_map(data, filename, issues):
    counts = dict.fromkeys(COUNT_KEYS, 0)
    field_counts = Counter(dict.fromkeys(ACTOR_FIELDS, 0))
    for key, expected in COLLECTIONS.items():
        value = data.get(key, expected())
        if not isinstance(value, expected):
            counts[key] = None
            _problem(issues, filename, key, "invalid_collection",
                     f"Expected a JSON {'array' if expected is list else 'object'}.")
        else:
            counts[key] = len(value)
    if "size" in data:
        size = data["size"]
        if not (isinstance(size, list) and len(size) == 2
                and all(_finite_number(part) and part > 0 for part in size)):
            _problem(issues, filename, "size", "invalid_mapsize", "Expected two positive finite numbers.")
    for key in ("background", "overlay"):
        if key in data and not isinstance(data[key], str):
            _problem(issues, filename, key, "invalid_asset_path", "Asset path must be a string.")
    actor_list = data.get("actors", []) if counts["actors"] is not None else []
    statuses, ids = _actor_ids(actor_list, filename, issues, counts)
    actors = [_actor_record(actor, index, statuses[index], filename, issues, counts, field_counts)
              for index, actor in enumerate(actor_list)]
    if counts["actors"] is None:
        ids["all_nonempty_unique"] = None
    return {
        "file": filename, "status": "parsed", "id": data.get("id"),
        "mapsize": data.get("size"), "background": data.get("background"),
        "overlay": data.get("overlay"),
        "present_fields": sorted(key for key in (*COLLECTIONS, "size", "background", "overlay") if key in data),
        "counts": counts, "actor_field_counts": dict(field_counts), "actor_ids": ids,
        "actors": actors,
        "editor_groups": {"present": "editor_groups" in data, "value": data.get("editor_groups", [])},
    }


def _read_map(path, issues):
    try:
        with path.open(encoding="utf-8") as source:
            data = json.load(source, parse_float=_finite_float, parse_constant=_reject_constant)
    except (OSError, UnicodeError) as error:
        _problem(issues, path.name, "", "unreadable_map", str(error.reason if isinstance(error, UnicodeError) else error.strerror))
        return {"file": path.name, "status": "unreadable"}
    except ValueError as error:
        _problem(issues, path.name, "", "invalid_json", str(error))
        return {"file": path.name, "status": "invalid_json"}
    if not isinstance(data, dict):
        _problem(issues, path.name, "", "invalid_map_root", "Map JSON root must be an object.")
        return {"file": path.name, "status": "invalid_root"}
    return _audit_map(data, path.name, issues)


def audit_maps(maps_dir=DEFAULT_MAPS_DIR):
    """Return a deterministic JSON-compatible inventory; read only the directory's *.json files."""
    maps_dir = Path(maps_dir)
    issues = []
    try:
        paths = sorted((path for path in maps_dir.iterdir()
                        if path.is_file() and path.suffix == ".json"), key=lambda path: path.name)
    except OSError as error:
        paths = []
        _problem(issues, "", "", "unreadable_maps_directory", error.strerror)
    if not paths and not issues:
        _problem(issues, "", "", "no_map_files", "No *.json map files found in the requested directory.")
    maps = [_read_map(path, issues) for path in paths]
    counts = dict.fromkeys(COUNT_KEYS, 0)
    unknown_counts = dict.fromkeys(COUNT_KEYS, 0)
    field_counts = dict.fromkeys(ACTOR_FIELDS, 0)
    for entry in maps:
        for key in COUNT_KEYS:
            value = entry.get("counts", {}).get(key)
            if value is None:
                unknown_counts[key] += 1
            else:
                counts[key] += value
        for key, value in entry.get("actor_field_counts", {}).items():
            field_counts[key] += value
    issues.sort(key=lambda item: (item["file"], item["path"], item["code"], item["message"]))
    return {
        "report_version": 1, "purpose": "inventory_only", "notice": NOTICE,
        "scope": {"file_pattern": "*.json", "recursive": False},
        "field_names": {"mapsize": "size", "legacy_reach": "reach", "local_reach": "reach_local"},
        "totals": {"files": len(maps), "parsed_maps": sum(entry["status"] == "parsed" for entry in maps),
                   "unreadable_or_invalid_maps": sum(entry["status"] != "parsed" for entry in maps),
                   "counts": counts, "unknown_counts": unknown_counts,
                   "actor_field_counts": field_counts, "issues": len(issues)},
        "maps": maps, "issues": issues,
    }


def report_json(report):
    """Serialize without timestamps or machine-specific absolute paths."""
    return json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n"


def _protect_maps(output, maps_dir):
    target = output.resolve()
    for directory in (Path(maps_dir).resolve(), DEFAULT_MAPS_DIR.resolve()):
        if target == directory or directory in target.parents:
            raise ValueError("--output cannot write inside a map directory.")
        if target.exists() and directory.is_dir():
            for source in directory.glob("*.json"):
                if source.is_file() and source.samefile(target):
                    raise ValueError("--output cannot overwrite a map through a linked path.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=NOTICE)
    parser.add_argument("--maps-dir", type=Path, default=DEFAULT_MAPS_DIR,
                        help="Directory to inventory (default: repository/data/maps).")
    parser.add_argument("--output", type=Path, help="Write UTF-8 JSON here; otherwise print JSON to stdout.")
    args = parser.parse_args(argv)
    try:
        if args.output is not None:
            _protect_maps(args.output, args.maps_dir)
        report = audit_maps(args.maps_dir)
        text = report_json(report)
        if args.output is None:
            sys.stdout.write(text)
        else:
            args.output.write_text(text, encoding="utf-8", newline="\n")
    except (OSError, ValueError) as error:
        print("audit_map_migration: " + str(error), file=sys.stderr)
        return 2
    return 1 if report["issues"] else 0


if __name__ == "__main__":
    sys.exit(main())
