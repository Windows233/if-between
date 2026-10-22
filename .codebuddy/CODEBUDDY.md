# IF：如果之间 —— 项目约定

> 这个文件由 AI 会话自动读取。改它要慎重，两个会话都会照着做。

## 一、这个项目有几个人同时在改

**第 0 步：新会话（尤其换了模型）先读 `docs/交接须知.md`** —— 一屏半，
含状态快照、阅读顺序、验证命令、红线。那份是给「刚接手的 AI」的入口，这份是并行协作的约定。

**动手之前必须做三件事：**

1. **同步远端。** `git pull`（或先 `git fetch` 看看远端有什么）。不 pull 就动手，
   等于闭着眼睛改，别人动过什么你完全不知道。
2. **读 `docs/进行中.md`。** 如果你要改的文件出现在别人的行里，**先停下来问用户**，
   不要自作主张往下改。
3. **读 `docs/开发纪要.md` 第零节**（做到哪、下一步干什么）和
   **`docs/工程约定.md` 第五节**（想做 X 该动哪个文件）。不要通读代码。

### 开工第一条：跑一次状态脚本

```bash
bash <项目根>/.codebuddy/hooks/session_status.sh
```

脚本自己定位项目根，在哪个目录执行都一样。报告里有当前分支、远端新提交、
对方改了哪些文件、本地未提交改动、以及 `docs/进行中.md` 的当前内容。

`SessionStart` hook 只在**会话的工作目录就是项目目录**时才会自动触发。
工作目录不落在项目里（桌面客户端的会话常是这样），就只能手动跑这一条 ——
所以它写进硬规矩，不要指望自动注入。

## 二、硬规矩

- **不要在 `main` 上长线开发。** 先开分支：
  `git switch -c feat/你的活`。前缀用 `feat/`、`fix/`、`content/`。
- **小步提交。** 每完成一个能跑通的小步骤就 commit + push。
  攒着不提交，冲突窗口就大，别人也没法知道你做到哪了。
- **收工前必跑**（两条都要退出码 0）：

  ```bash
  python tools/check_data.py
  "$GODOT" --headless --path . --script res://tests/run_tests.gd
  ```

  `$GODOT` 是本机的 Godot 可执行文件，路径各人不同：
  `C:/Games/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe`

- **测试不过不许 push。** 推上去的是别人接着要改的地基。
- **提交完就 push，不要留在本地过夜。**
- **维护 `docs/进行中.md`。** 开工加一行，收工删掉自己那行。

## 三、四处串行区，同一时间只能一个人动

- `core/` 里的公共类 —— 改字段、改接口会让别人编译不过
- `project.godot`、`export_presets.cfg` —— 标了 `-merge`，合并错了静默坏掉
- `docs/开发纪要.md` —— **只追加，不改别人的小节**
- `docs/进行中.md` —— 只动自己那行

## 四、几个容易踩的坑

- **新增带 `class_name` 的脚本后**，必须先跑一次
  `"$GODOT" --headless --path . --import`，否则引用它的代码报
  `Identifier not declared`。`--import` 不能和 Godot 编辑器同时跑，会抢 `.godot/`。
- **换行符不要手改。** `.gitattributes` 定了 `eol=lf`，仓库内一律 LF。
  工作区是 CRLF 也没关系，git 会归一化。
- **测试刻意不依赖 gdUnit4**，clone 下来直接能跑，别引入新测试框架。
- `.godot/` 不进版本控制。新机器上第一次必须跑 `--import`。

## 五、常用命令

```bash
# 开工
git pull
git switch -c feat/你的活

# 收工
python tools/check_data.py
"$GODOT" --headless --path . --script res://tests/run_tests.gd
git add -A && git commit -m "..."
git push -u origin HEAD

# 合回主线
git switch main && git pull && git merge feat/你的活 && git push
```

详细的协作流程见 `docs/协作约定.md`。
