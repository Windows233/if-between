"""数据自查：跨文件的引用对不对得上。

手写 JSON 最容易出的毛病是「引用了一个不存在的东西」——地图挂的剧情没有、
剧情 next 跳到没有的节点、结局 id 不在结局表里、立绘/背景图文件不在。
这些错误跑起来才炸，而且往往炸在很后面。这个脚本提前把全部对一遍。

用法：
    python tools/check_data.py

退出码 0 表示没问题。
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPS = os.path.join(ROOT, "data", "maps")
EVENTS = os.path.join(ROOT, "data", "events")

problems = []


def note(where: str, msg: str) -> None:
    problems.append("%s: %s" % (where, msg))


def load_json(path: str):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def walk_line_talk(raw):
    """一个交互/节点里可能用 talk，也可能老写法用 line。统一取出来。"""
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict):
        return [raw]
    return []


def collect_attr(key: str):
    """把 data 下面所有 json 里某个 key 的值全捞出来。"""
    found = set()
    for base in (MAPS, EVENTS):
        for name in sorted(os.listdir(base)):
            if not name.endswith(".json"):
                continue
            text = open(os.path.join(base, name), encoding="utf-8").read()
            if '"%s"' % key not in text:
                continue
            data = load_json(os.path.join(base, name))
            _collect_attr_in(data, key, found)
    return found


def _collect_attr_in(node, key: str, found: set) -> None:
    if isinstance(node, dict):
        for k, v in node.items():
            if k == key and isinstance(v, str):
                found.add(v)
            else:
                _collect_attr_in(v, key, found)
    elif isinstance(node, list):
        for item in node:
            _collect_attr_in(item, key, found)



def stale_imports() -> list:
    """找出**改了但没重新导入**的图片。

    Godot 每次导入都在 `.godot/imported/<图名>-<标识>.md5` 里记一份
    `source_md5`。它跟源文件当前的 md5 对不上，就说明图改过、导入没跟上。

    这时 `godot --path . --script ...` 跑起来用的还是旧图 —— 画面上全不对，
    代码和数据却一点毛病都看不出来。**这个坑踩过一次**（角色改了尺寸、
    跑出来还是老尺寸），所以放进自查里。
    """
    import hashlib
    import re
    bad = []
    cache = os.path.join(ROOT, ".godot", "imported")
    for base, _dirs, files in os.walk(os.path.join(ROOT, "art")):
        for name in files:
            if not name.lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
                continue
            src = os.path.join(base, name)
            rel = os.path.relpath(src, ROOT).replace(os.sep, "/")
            manifest = src + ".import"
            if not os.path.exists(manifest):
                bad.append((rel, "还没导入过"))
                continue
            found = re.search(r"imported/([^/\"]+)\.ctex", open(manifest, encoding="utf-8").read())
            if not found:
                continue
            sidecar = os.path.join(cache, found.group(1) + ".md5")
            if not os.path.exists(sidecar):
                bad.append((rel, "导入记录不完整"))
                continue
            recorded = re.search(r'source_md5="([0-9a-f]+)"',
                                 open(sidecar, encoding="utf-8").read())
            if not recorded:
                continue
            now = hashlib.md5(open(src, "rb").read()).hexdigest()
            if recorded.group(1) != now:
                bad.append((rel, "图改过、但没重新导入"))
    return bad



def _exists(rel: str) -> bool:
    return os.path.exists(os.path.join(ROOT, rel.replace("res://", "").replace("/", os.sep)))


## 剧情节点上认得的字段。**写了别的就报出来。**
##
## 为什么要有这一条：节点上的状态字段在 JSON 里叫 `set`（不是 `effects`），
## 写错一个词不会报错、也不会崩 —— 它就是**静静地不生效**。
## 2026-09-24 就在这儿栽过一次：写了 `"effects"`，于是「睡过了」那个标记
## 一直没立起来，卧室门到第二次还开着第一个口，得靠测试才查出来。
NODE_KEYS = {"id", "next", "ending", "talk", "stage", "set", "choices"}


def check_node_keys(where: str, node: dict, problems: list) -> None:
    for key in node:
        if key not in NODE_KEYS:
            problems.append("%s 节点 %s 上有不认识的字段 `%s`（认得的是：%s）"
                            % (where, node.get("id", "?"), key,
                               "、".join(sorted(NODE_KEYS))))
    # **写了 `ending` 的节点就是终点**，`next` 会被忽略。
    # 两个都写多半是想「先记结局再往下演」—— 那件事做不了：
    # 结局一记，整段剧情就收了。要中途记结局，用 `set` 写 `ending/<id>`。
    if node.get("ending") and node.get("next"):
        problems.append("%s 节点 %s 既写了 ending 又写了 next —— "
                        "ending 一写这个节点就是终点，next 会被忽略。"
                        "要中途记结局请用 set: {\"ending/<id>\": true}"
                        % (where, node.get("id", "?")))


def check_stage(where: str, node: dict, maps: dict, problems: list) -> None:
    """查一个节点的演出指令。

    要查的是**只有数据知道、代码查不出**的那些：
    图在不在、要跳的场景和出生点存不存在、跟谁说话有没有写。指令名写错
    由 `StageStep.validate()` 在引擎里抓，这里只管外部引用。
    """
    for index, step in enumerate(node.get("stage", [])):
        kind = step.get("do", "")
        at = "%s 节点 %s 第 %d 条演出（%s）" % (where, node.get("id", "?"), index + 1, kind)

        if kind == "image":
            path = step.get("path", "")
            if path and not _exists(path):
                problems.append(at + "：大图不存在 " + path)
        if kind in ("npc",):
            sprite = step.get("sprite", "")
            if sprite and not _exists(sprite):
                problems.append(at + "：临时角色的图不存在 " + sprite)
        if kind == "goto":
            target = step.get("map", "")
            spawn = step.get("spawn", "default")
            if target not in maps:
                problems.append(at + "：要去的场景不存在 " + target)
            elif spawn not in maps[target].get("spawns", {}):
                problems.append("%s：场景 %s 里没有出生点 %s" % (at, target, spawn))
        if kind == "banner" and not step.get("text"):
            problems.append(at + "：章标题没写内容")
        if kind == "say" and not step.get("lines") and not step.get("text") \
                and step.get("slide") != "out":
            problems.append(at + "：没有说话内容")
        if kind == "caption":
            lines = step.get("lines")
            if not isinstance(lines, list) or not lines:
                problems.append(at + "：屏幕中央那几行字一条都没写")
            elif not any(str(item.get("text", "")).strip()
                         for item in lines if isinstance(item, dict)):
                problems.append(at + "：屏幕中央那几行字全是空的")
        if kind == "play_sound":
            # 音频还没到位（`audio/sfx` 是空的），`main.play_sound()` 找不到
            # 文件会**静默跳过** —— 所以路径写错在游戏里看不出来，只能在这儿查。
            #
            # 文件不存在**不算数据错误**：演出里那条指令本来就该先写着，
            # 素材一到位就响。列出来只是提醒「这一段现在还是哑的」。
            path = step.get("path", "")
            if not path:
                problems.append(at + "：没写音频路径")
            elif not _exists(path):
                print("提醒：%s 的音频还没到位 %s" % (at, path))
        if kind == "music":
            # 换背景音乐。**`path` 留空是合法的** —— 那是「就在这儿把音乐停掉」，
            # 开场压住前奏用的就是它（`ch1_opening` 的 `title` 节点）。
            # 所以这里跟 `play_sound` 不一样：空路径不算错，只有「写了但找不到」要提醒。
            path = step.get("path", "")
            if path and not _exists(path):
                print("提醒：%s 的音乐还没到位 %s" % (at, path))


def main() -> int:
    # ---------- 读全部数据 ----------
    maps = {}
    for name in sorted(os.listdir(MAPS)):
        if name.endswith(".json"):
            maps[name[:-5]] = load_json(os.path.join(MAPS, name))

    events = {}
    for name in sorted(os.listdir(EVENTS)):
        if name.endswith(".json"):
            events[name[:-5]] = load_json(os.path.join(EVENTS, name))

    endings = {e["id"] for e in load_json(os.path.join(ROOT, "data", "endings.json"))}
    given = set()
    items = set(load_json(os.path.join(ROOT, "data", "items.json")).keys())

    # ---------- 地图 ----------
    map_ids = {m.get("id") for m in maps.values()}
    for mid, m in maps.items():
        where = "maps/%s.json" % mid
        for p in m.get("portals", []):
            if "to" in p and p["to"] not in map_ids:
                note(where, "传送点「%s」指向不存在的地图 %s" % (p.get("label", "?"), p["to"]))
            sprite = p.get("sprite", "")
            if sprite and not os.path.exists(
                    os.path.join(ROOT, sprite.replace("res://", "").replace("/", os.sep))):
                note(where, "传送点「%s」的贴图不存在：%s" % (p.get("label", "?"), sprite))
            spawn = p.get("spawn")
            if "to" in p and spawn and spawn not in maps[p["to"]].get("spawns", {}):
                note(where, "传送点「%s」用的出生点 %s 在目标地图里没有"
                     % (p.get("label", "?"), spawn))
        for a in m.get("actors", []):
            # 物件贴图是从插画里切的，路径错了画面上就是一块色块 —— 提前抓出来
            sprite = a.get("sprite", "")
            if sprite and not os.path.exists(
                    os.path.join(ROOT, sprite.replace("res://", "").replace("/", os.sep))):
                note(where, "角色「%s」的贴图不存在：%s" % (a.get("id", "?"), sprite))
            for act in a.get("actions", []):
                if "event" in act and act["event"] not in events:
                    note(where, "角色「%s」的动作挂了不存在的剧情 %s"
                         % (a.get("id", "?"), act["event"]))
            if "event" in a and a["event"] not in events:
                note(where, "角色「%s」挂了不存在的剧情 %s" % (a.get("id", "?"), a["event"]))
        bg = m.get("background", "")
        if bg and not os.path.exists(os.path.join(ROOT, bg.replace("res://", "").replace("/", os.sep))):
            note(where, "背景图不存在：%s" % bg)
        # 背景音乐同理。**留空是合法的**（卧室就没音乐），只有「写了但找不到」
        # 才是问题 —— 那种情况游戏里会安静地没有声音，看画面看不出来。
    music = m.get("music", "")
    if music and not os.path.exists(
            os.path.join(ROOT, music.replace("res://", "").replace("/", os.sep))):
        note(where, "背景音乐不存在：%s" % music)

    # 脚步音效同理。留空是正常的（户外场景没有），但**写了就得存在** ——
    # 路径拼错的话游戏里只是「不响」，画面和日志都不吭声。
    footstep = m.get("footstep", "")
    if footstep and not os.path.exists(
            os.path.join(ROOT, footstep.replace("res://", "").replace("/", os.sep))):
        note(where, "脚步音效不存在：%s" % footstep)

    # ---------- 剧情 ----------
    for eid, ev in events.items():
        where = "events/%s.json" % eid
        nodes = ev.get("nodes", [])
        # 演出指令里的外部引用：图在不在、要跳的场景和出生点有没有
        for node in nodes:
            check_node_keys(where, node, problems)
            check_stage(where, node, maps, problems)
        ids = {n.get("id") for n in nodes}
        entry = ev.get("entry", "")
        if nodes and entry not in ids:
            note(where, "entry 指向不存在的节点 %s" % entry)
        for n in nodes:
            nid = n.get("id", "?")
            if "next" in n and n["next"] not in ids:
                note(where, "节点 %s 的 next 指向不存在的节点 %s" % (nid, n["next"]))
            if "ending" in n and n["ending"] not in endings:
                note(where, "节点 %s 的结局 %s 不在结局表里" % (nid, n["ending"]))
            for c in n.get("choices", []):
                if "next" in c and c["next"] not in ids:
                    note(where, "节点 %s 的选项 %s 指向不存在的节点 %s"
                         % (nid, c.get("id", "?"), c["next"]))
                for k in c.get("set", {}):
                    if k.startswith("item/") and k[len("item/"):] not in items:
                        note(where, "选项 %s 给了没登记的物品 %s" % (c.get("id", "?"), k))
            for line in walk_line_talk(n.get("talk", [])):
                port = line.get("portrait", "")
                if port and not os.path.exists(
                        os.path.join(ROOT, "art", "portrait", port + ".png")):
                    note(where, "节点 %s 引用了不存在的立绘 art/portrait/%s.png" % (nid, port))
            for key in n.get("set", {}):
                if key.startswith("item/"):
                    if key[len("item/"):] not in items:
                        note(where, "节点 %s 写了没登记的物品 %s" % (nid, key))
                    else:
                        given.add(key[len("item/"):])

    # ---------- 物品：声明 vs 使用 ----------
    used_items = set()
    for key in collect_attr("var"):
        if key.startswith("item/"):
            used_items.add(key[len("item/"):])
    used_items |= given
    for it in sorted(used_items):
        if it not in items:
            note("items.json", "用到没登记的物品 item/%s" % it)
    for it in sorted(items):
        if it not in used_items:
            print("提醒：物品 %s 登记了但没人用" % it)

    # ---------- 结局：有人走到吗 ----------
    reached = set()
    for eid, ev in events.items():
        for n in ev.get("nodes", []):
            if "ending" in n:
                reached.add(n["ending"])

    for e in sorted(endings):
        if e not in reached:
            print("提醒：结局 %s 还没有任何剧情走到它" % e)

    # 改了图没重新导入 —— 不算数据错误，但画面上会是旧图，同样致命
    stale = stale_imports()
    if stale:
        print("== 有 %d 张图改了没重新导入 ==" % len(stale))
        for path, why in stale[:20]:
            print(" - %s（%s）" % (path, why))
        if len(stale) > 20:
            print("   ……还有 %d 张" % (len(stale) - 20))
        print("   跑：godot --headless --path . --import")
        problems.extend(["%s（%s）" % (p, why) for p, why in stale])

    if problems:
        print("== 数据有问题 %d 条 ==" % len(problems))
        for p in problems:
            print(" -", p)
        return 1
    print("数据自查通过：%d 张地图，%d 份剧情，%d 个结局，%d 件物品"
          % (len(maps), len(events), len(endings), len(items)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
