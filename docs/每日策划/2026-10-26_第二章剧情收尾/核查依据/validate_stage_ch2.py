"""Validate stage-script/v2 structure, game bindings, and references. Requires PyYAML.

Usage: python validate_stage.py FILE [--project-root DIR] [--require-ready]
This does not simulate a game, prove branch conditions, or validate choreography.
"""
import argparse
import json
from pathlib import Path
import re
import sys

try:
    import yaml
except ImportError:
    raise SystemExit("PyYAML is unavailable. Use an existing Python environment with PyYAML.")


class UniqueLoader(yaml.SafeLoader):
    def compose_node(self, parent, index):
        if self.check_event(yaml.AliasEvent):
            raise ValueError("YAML aliases are not supported")
        return super().compose_node(parent, index)


def unique_mapping(loader, node):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node)
        if not isinstance(key, str):
            raise ValueError("Mapping keys must be strings")
        if key in result:
            raise ValueError(f"Duplicate YAML key: {key}")
        result[key] = loader.construct_object(value_node)
    return result


UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)
KINDS = {"transition", "camera", "actor", "dialogue", "caption", "audio", "image",
         "ui", "wait", "state", "interaction", "parallel"}


def validate(data, project_root=None):
    errors = []

    def check(ok, message):
        if not ok:
            errors.append(message)

    def required(obj, keys, where):
        check(isinstance(obj, dict), f"{where}: expected mapping")
        if not isinstance(obj, dict):
            return {}
        for key in keys.split():
            check(key in obj, f"{where}: missing {key}")
        return obj

    def rows(obj, key, where):
        value = obj.get(key, [])
        check(isinstance(value, list), f"{where}.{key}: expected list")
        return value if isinstance(value, list) else []

    def text(value):
        return isinstance(value, str) and bool(value.strip())

    def index(key, fields):
        found = {}
        for row in rows(data, key, "root"):
            row = required(row, "id " + fields, key)
            ident = row.get("id")
            check(text(ident), f"{key}: id must be nonempty string")
            if not isinstance(ident, str):
                continue
            check(ident not in found, f"{key}: duplicate id {ident}")
            found[ident] = row
        return found

    data = required(data, "format title status project game_context sources entities assets variables decisions entry nodes coverage", "root")
    check(data.get("format") == "stage-script/v2", "root: unsupported format (expected scene-bound v2)")
    ready = data.get("status") == "ready_for_implementation"
    check(data.get("status") in ("draft", "ready_for_implementation"), "root: invalid status")
    check(text(data.get("title")), "root: missing title text")
    sources = index("sources", "path locator role authority")
    entities = index("entities", "name kind")
    assets = index("assets", "kind status path spec")
    variables = index("variables", "type initial persistence description")
    decisions = index("decisions", "question blocking affects resolution")
    nodes = index("nodes", "title sources scene trigger control repeat setup cues exit")
    check(bool(sources), "root: at least one source is required")

    context = required(data.get("game_context"), "viewport coordinate_system scenes", "game_context")
    viewport = context.get("viewport")
    check(isinstance(viewport, list) and len(viewport) == 2
          and all(type(v) is int and v > 0 for v in viewport), "game_context: invalid viewport")
    scenes = {}
    for scene in rows(context, "scenes", "game_context"):
        scene = required(scene, "id map_file background map_size inspection objects camera_notes scene_notes", "scene binding")
        scene_id = scene.get("id")
        check(isinstance(scene_id, str) and scene_id not in scenes, "scene binding: invalid or duplicate id")
        if not isinstance(scene_id, str):
            continue
        scenes[scene_id] = scene
        inspection = required(scene.get("inspection"), "data visual runtime notes", scene_id + ".inspection")
        check(inspection.get("data") in ("verified", "unverified"), f"{scene_id}: invalid data inspection")
        check(inspection.get("visual") in ("verified", "not_viewed"), f"{scene_id}: invalid visual inspection")
        check(inspection.get("runtime") in ("verified", "not_run"), f"{scene_id}: invalid runtime inspection")
        if ready:
            check(inspection.get("data") == "verified" and inspection.get("visual") == "verified",
                  f"{scene_id}: ready requires actual map data and visual inspection")
        objects = rows(scene, "objects", scene_id)
        if project_root and inspection.get("data") == "verified":
            map_path = scene.get("map_file")
            check(isinstance(map_path, str) and bool(map_path), f"{scene_id}: missing map_file")
            if isinstance(map_path, str) and map_path:
                actual_path = project_root / map_path.removeprefix("res://")
                if not actual_path.is_file():
                    check(False, f"{scene_id}: map_file does not exist")
                else:
                    actual = json.loads(actual_path.read_text(encoding="utf-8-sig"))
                    check(actual.get("id") == scene_id, f"{scene_id}: actual map id mismatch")
                    check(actual.get("size") == scene.get("map_size"), f"{scene_id}: actual map size mismatch")
                    background = str(actual.get("background", "")).removeprefix("res://")
                    check(background == str(scene.get("background", "")).removeprefix("res://"),
                          f"{scene_id}: actual background mismatch")
                    check(bool(background) and (project_root / background).is_file(), f"{scene_id}: background not found")
                    actual_actors = {obj.get("id"): obj for obj in actual.get("actors", []) if isinstance(obj, dict)}
                    object_ids = set()
                    for obj in objects:
                        obj = required(obj, "id rect representation notes", scene_id + ".objects")
                        object_id = obj.get("id")
                        check(isinstance(object_id, str) and object_id not in object_ids,
                              f"{scene_id}: invalid or duplicate object id")
                        if not isinstance(object_id, str):
                            continue
                        object_ids.add(object_id)
                        actual_obj = actual_actors.get(object_id)
                        check(actual_obj is not None, f"{scene_id}: unknown actual map object {object_id}")
                        if actual_obj:
                            check(actual_obj.get("rect") == obj.get("rect"), f"{scene_id}/{object_id}: rect mismatch")
                            if "reach" in obj:
                                check(actual_obj.get("reach") == obj["reach"], f"{scene_id}/{object_id}: reach mismatch")

    native_commands = None
    if project_root:
        settings = project_root / "project.godot"
        if settings.is_file():
            setting_text = settings.read_text(encoding="utf-8-sig")
            sizes = [re.search(r"^window/size/viewport_" + axis + r"=(\d+)$", setting_text, re.M)
                     for axis in ("width", "height")]
            if all(sizes):
                check(viewport == [int(match.group(1)) for match in sizes], "game_context: actual viewport mismatch")
        commands_path = project_root / "core/stage_step.gd"
        if commands_path.is_file():
            native_commands = {}
            for name, fields in re.findall(r'&"([a-z][a-z0-9_]*)"\s*:\s*\[([^\]]*)\]', commands_path.read_text(encoding="utf-8-sig")):
                native_commands[name] = re.findall(r'"([a-z][a-z0-9_]*)"', fields)

    def ref(value, table, where):
        check(isinstance(value, str) and value in table, f"{where}: unknown reference {value!r}")

    def refs(obj, key, table, where, nonempty=False):
        values = rows(obj, key, where)
        if nonempty:
            check(bool(values), f"{where}.{key}: cannot be empty")
        for value in values:
            ref(value, table, f"{where}.{key}")

    def matches(value, kind):
        return {"bool": type(value) is bool, "int": type(value) is int,
                "string": isinstance(value, str)}.get(kind, False)

    for ident, var in variables.items():
        check(matches(var.get("initial"), var.get("type")), f"{ident}: initial type mismatch")
        check(var.get("persistence") in ("chapter", "save", "memory"), f"{ident}: invalid persistence")
    for ident, asset in assets.items():
        check(asset.get("status") in ("verified", "planned", "missing"), f"{ident}: invalid asset status")
        check(asset.get("status") != "verified" or text(asset.get("path")), f"{ident}: verified asset needs path")
        check(not (ready and asset.get("status") == "missing" and not text(asset.get("fallback"))),
              f"{ident}: ready script needs a usable fallback for missing asset")
        if project_root and asset.get("status") == "verified" and text(asset.get("path")):
            path = asset["path"].removeprefix("res://")
            check((project_root / path).is_file(), f"{ident}: asset file does not exist: {path}")
    for ident, decision in decisions.items():
        check(type(decision.get("blocking")) is bool, f"{ident}: blocking must be bool")
        refs(decision, "affects", nodes, ident)
        check(not (ready and decision.get("blocking") and decision.get("resolution") is None),
              f"{ident}: unresolved blocking decision cannot be ready")

    def condition(value, where):
        value = required(value, "", where)
        keys = set(value)
        if keys == {"not"}:
            condition(value["not"], where)
        elif keys == {"all"} or keys == {"any"}:
            key = next(iter(keys))
            parts = rows(value, key, where)
            check(bool(parts), f"{where}: empty condition group")
            for part in parts:
                condition(part, where)
        else:
            check(keys == {"var", "op", "value"}, f"{where}: malformed condition")
            ref(value.get("var"), variables, where)
            check(value.get("op") in ("eq", "ne", "gt", "ge", "lt", "le"), f"{where}: invalid operator")
            var = variables.get(str(value.get("var")), {})
            check(matches(value.get("value"), var.get("type")), f"{where}: condition value type mismatch")
            if value.get("op") in ("gt", "ge", "lt", "le"):
                check(var.get("type") == "int", f"{where}: ordered comparison requires int")

    cue_ids = set()

    def cue(value, where, child=False):
        value = required(value, "id kind origin sources description completion engine", where)
        ident = value.get("id")
        check(text(ident), f"{where}: cue id must be nonempty string")
        ident = str(ident)
        check(ident not in cue_ids, f"{where}: duplicate cue id {ident}")
        cue_ids.add(ident)
        refs(value, "sources", sources, ident, nonempty=True)
        kind = value.get("kind")
        check(kind in KINDS, f"{ident}: invalid kind")
        check(value.get("origin") in ("source", "staging", "proposal"), f"{ident}: invalid origin")
        check(text(value.get("description")), f"{ident}: missing description")
        check(value.get("completion") in ("immediate", "finished", "confirm", "interaction_result"),
              f"{ident}: invalid completion")
        if "seconds" in value:
            seconds = value["seconds"]
            check(type(seconds) in (int, float) and seconds >= 0, f"{ident}: invalid seconds")
        if "assets" in value:
            refs(value, "assets", assets, ident)
        if "target" in value:
            ref(value["target"], entities, ident)
        if "decision_ids" in value:
            refs(value, "decision_ids", decisions, ident)
        if value.get("origin") == "proposal":
            refs(value, "decision_ids", decisions, ident, nonempty=True)
            if ready:
                for decision_id in value.get("decision_ids", []):
                    check(decisions.get(str(decision_id), {}).get("resolution") is not None,
                          f"{ident}: unaccepted proposal cannot be ready")
        engine = required(value.get("engine"), "status steps notes", ident + ".engine")
        check(engine.get("status") in ("existing", "requires_work", "unresolved"), f"{ident}: invalid engine status")
        check(text(engine.get("notes")), f"{ident}: engine mapping needs notes")
        check(not (ready and engine.get("status") == "unresolved"), f"{ident}: unresolved engine mapping cannot be ready")
        if engine.get("status") == "requires_work":
            check(text(engine.get("plan")), f"{ident}: requires_work needs concrete plan")
        for step in rows(engine, "steps", ident + ".engine"):
            step = required(step, "do", ident + ".engine.step")
            if native_commands is not None:
                command = step.get("do")
                check(isinstance(command, str) and command in native_commands,
                      f"{ident}: unknown native command {command!r}")
                for field in native_commands.get(str(command), []):
                    check(field in step, f"{ident}: native command {command} missing {field}")
        params = required(value.get("params", {}), "", ident + ".params")
        if kind == "actor":
            ref(value.get("target"), entities, ident)
            required(params, "operation", ident)
        if kind in ("transition", "camera", "caption", "ui", "interaction"):
            check(bool(params), f"{ident}: {kind} needs explicit params")
        if kind == "image":
            required(params, "operation asset", ident)
            check(params.get("operation") in ("show", "hide"), f"{ident}: invalid image operation")
            ref(params.get("asset"), assets, ident)
        if kind == "audio":
            required(params, "operation bus", ident)
            check(params.get("operation") in ("play", "stop", "handoff"), f"{ident}: invalid audio operation")
            check(params.get("bus") in ("bgm", "sfx"), f"{ident}: invalid audio bus")
            if params.get("operation") == "play":
                ref(params.get("asset"), assets, ident)
        if kind == "wait" and value.get("completion") == "finished":
            check("seconds" in value, f"{ident}: timed wait requires seconds")
        if kind == "dialogue":
            required(params, "speaker mode text side portrait", ident)
            check(text(params.get("text")), f"{ident}: empty dialogue")
            check(params.get("mode") in ("spoken", "thought", "narration"), f"{ident}: invalid dialogue mode")
            check(params.get("side") in ("left", "right", "none"), f"{ident}: invalid dialogue side")
            if params.get("speaker") is not None:
                ref(params["speaker"], entities, ident)
            if params.get("portrait") is not None:
                ref(params["portrait"], assets, ident)
        if kind == "state":
            changes = rows(params, "changes", ident)
            check(bool(changes), f"{ident}: empty state changes")
            for change in changes:
                change = required(change, "var op value", ident)
                ref(change.get("var"), variables, ident)
                var = variables.get(str(change.get("var")), {})
                check(change.get("op") in ("set", "add"), f"{ident}: invalid state operation")
                check(matches(change.get("value"), var.get("type")), f"{ident}: state value type mismatch")
                if change.get("op") == "add":
                    check(var.get("type") == "int", f"{ident}: add requires int")
        if kind in ("image", "audio") and params.get("asset") is not None:
            ref(params["asset"], assets, ident)
        if kind == "parallel":
            check(not child, f"{ident}: nested parallel is unsupported")
            check(value.get("completion") == "finished", f"{ident}: parallel must await all children")
            children = rows(params, "children", ident)
            check(bool(children), f"{ident}: empty parallel")
            for item in children:
                cue(item, ident, child=True)

    edges = {ident: [] for ident in nodes}
    for ident, node in nodes.items():
        refs(node, "sources", sources, ident, nonempty=True)
        ref(node.get("scene"), scenes, ident + ".scene")
        check(node.get("control") in ("cutscene", "exploration", "minigame"), f"{ident}: invalid control")
        check(node.get("repeat") in ("once", "repeatable", "guarded"), f"{ident}: invalid repeat")
        if node.get("repeat") == "guarded":
            check(text(node.get("repeat_notes")), f"{ident}: guarded node needs repeat_notes")
        trigger = required(node.get("trigger"), "type", ident + ".trigger")
        check(trigger.get("type") in ("interact", "enter", "flow", "state"), f"{ident}: invalid trigger")
        if trigger.get("type") == "interact":
            ref(trigger.get("target"), entities, ident)
        if "condition" in trigger:
            condition(trigger["condition"], ident)
        required(node.get("setup"), "camera characters environment audio", ident + ".setup")
        for item in rows(node, "cues", ident):
            cue(item, ident)
        out = required(node.get("exit"), "type", ident + ".exit")

        def edge(target):
            ref(target, nodes, ident + ".exit")
            if isinstance(target, str) and target in nodes:
                edges[ident].append(target)

        kind = out.get("type")
        if kind == "next":
            edge(out.get("next"))
        elif kind == "branch":
            cases = rows(out, "cases", ident)
            check(bool(cases), f"{ident}: branch needs cases")
            for case in cases:
                case = required(case, "condition next", ident)
                condition(case.get("condition"), ident)
                edge(case.get("next"))
            edge(out.get("default"))
        elif kind == "choice":
            required(out, "prompt cancel options", ident)
            options = rows(out, "options", ident)
            check(bool(options), f"{ident}: choice has no options")
            option_ids = set()
            for option in options:
                option = required(option, "id label next", ident)
                option_id = str(option.get("id"))
                check(option_id not in option_ids, f"{ident}: duplicate option id {option_id}")
                option_ids.add(option_id)
                check(text(option.get("label")), f"{ident}: empty option label")
                edge(option.get("next"))
                if "condition" in option:
                    condition(option["condition"], ident)
                    check(option.get("unavailable") in ("hidden", "disabled"), f"{ident}: missing unavailable policy")
            if out.get("cancel") != "disabled":
                edge(out.get("cancel"))
        elif kind in ("return_control", "end"):
            check(text(out.get("handoff")), f"{ident}: missing handoff")
            if kind == "end":
                check(text(out.get("ending_id")), f"{ident}: missing ending_id")
        else:
            check(False, f"{ident}: invalid exit type")

    ref(data.get("entry"), nodes, "entry")
    visited = set()
    pending = [data.get("entry")] if isinstance(data.get("entry"), str) else []
    while pending:
        ident = pending.pop()
        if ident in visited:
            continue
        visited.add(ident)
        pending.extend(edges.get(ident, []))
    for ident in nodes.keys() - visited:
        # Additional interact/enter/state nodes are independently triggered roots.
        trigger = nodes[ident].get("trigger", {})
        if isinstance(trigger, dict) and trigger.get("type") in ("interact", "enter", "state"):
            pending.append(ident)
    while pending:
        ident = pending.pop()
        if ident not in visited:
            visited.add(ident)
            pending.extend(edges.get(ident, []))
    for ident in sorted(nodes.keys() - visited):
        check(False, f"{ident}: unreachable flow node")
    coverage = rows(data, "coverage", "root")
    check(bool(coverage), "root: coverage cannot be empty")
    for row in coverage:
        row = required(row, "from nodes note", "coverage")
        refs(row, "nodes", nodes, "coverage", nonempty=True)
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", type=Path)
    parser.add_argument("--project-root", type=Path)
    parser.add_argument("--require-ready", action="store_true")
    args = parser.parse_args()
    try:
        data = yaml.load(args.file.read_text(encoding="utf-8-sig"), Loader=UniqueLoader)
        errors = validate(data, args.project_root)
    except (OSError, ValueError, yaml.YAMLError, TypeError, RecursionError) as exc:
        print(f"FAIL: {exc}")
        return 1
    if errors:
        print("FAIL:\n" + "\n".join("- " + item for item in errors))
        return 1
    print(f"PASS: {len(data['nodes'])} nodes; status={data['status']}. Structural validation only.")
    if args.require_ready and data["status"] != "ready_for_implementation":
        print("Not ready for implementation; inspect decisions and bindings.")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
