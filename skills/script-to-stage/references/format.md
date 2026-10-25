# 游戏场景演出剧本格式 v2

标准文件扩展名 `.stage.yaml`。中文用于描述和台词，英文用于字段与稳定 ID。不要用 YAML 标签、锚点、别名或重复键。看起来像日期、布尔值或带冒号的台词请加引号。空数组写 `[]`，未知值写 `null`，不要用“无”假装 ID。

## 顶层字段

| 字段 | 含义 |
| --- | --- |
| format | 固定 `stage-script/v2`；相较v1增加必需的工程画面证据与原生实现对应 |
| title | 章节或事件标题 |
| status | `draft` 或 `ready_for_implementation` |
| project | 名称、引擎及目标适配器；未知写 null |
| game_context | 本次实际工程、地图与画面查验记录；不是小说中的世界观，结构见下 |
| sources | 原文与已读取参考来源：id、path、locator、role（script/reference/implementation）、authority（selected/approved/proposal/observed）。path 可为相对项目路径、文档URL或 `user_message`；locator 用行号、页码、标题或原句定位 |
| entities | id、name、kind（character/prop）；人物称谓统一，但不擅自给未命名人物取正式名 |
| assets | id、kind、status（verified/planned/missing）、path、spec。只有确实存在且适用的文件写 verified；没有真实路径写 null，spec 写外观/内容/用途及必要尺寸；可补 fallback |
| variables | id、type（bool/int/string）、initial、persistence（chapter/save/memory）、description；initial 是新流程初始值，不表示每次调查重置 |
| decisions | id、question、blocking、affects（节点 ID 数组）、resolution。未解决 resolution 为 null；已采纳方案写选择及其来源 |
| entry | 一个节点 ID |
| nodes | 节点数组，结构见下 |
| coverage | 原文段落到节点/cue的对应，from、nodes、note；须覆盖关键台词、动作、分支、结局，注明省略原因和授权，不凭压缩摘要删除正文 |

`sources` 与 cue.sources 是溯源信息，游戏中不显示。分支条件只能引用 variables 中的 ID。原生 flag 名称可在 variables 的 `binding` 中记录。

## game_context：必需的实际场景绑定

包含 `viewport / coordinate_system / scenes`。viewport是实际逻辑视口，例如 `[320,180]`；coordinate_system说明原点、轴方向、位置锚点。scenes数组每项包含：

- `id`：真实地图ID，与node.scene一致。
- `map_file / background / map_size`：当前工程的地图JSON、底图路径、地图逻辑大小，不写虚构路径。
- `inspection`：`data / visual / runtime`；data为verified/unverified，visual为verified/not_viewed，runtime为verified/not_run；写notes说明查看的文件、静态/运行时证据与范围。ready要求data和visual均verified，runtime可not_run但不能声称画面已经游戏验收。
- `objects`：本次使用的实际地图物件，id与地图actor一致，记录其rect和reach（若有）、representation（baked/sprite/interaction_only）、notes。交互框、可站位置和贴图范围分开说明。地图无actor的人物可记录在scene_notes，不杜撰actor ID。
- `camera_notes / scene_notes`：核实的镜头裁切和遮挡、本幕底图已含人物、实际可用动作等。

scene还可写entry_points、route_checks、integration。`integration`说明地图action挂接哪个事件、复用/替换的文件和所需原生节点。路线需实际验证才能route_checks.status: verified；不移动可写not_needed。

完全新场景尚无地图时map_file/background/map_size可null，inspection未核实，必须draft并登记场景制作需求。不能用通用“学校”叙述绕过绑定。

## 节点

每个节点包含 `id / title / sources / scene / trigger / control / repeat / setup / cues / exit`。

- `scene`：已有地图 ID 或稳定场景 ID；同一地图多节点不代表重新载入。
- `trigger`：`type: interact / enter / flow / state`；写 target 和 condition（如适用）。interact 明确玩家操作对象，flow 仅由上一个节点跳转。
- `control`：`cutscene / exploration / minigame`。cutscene 默认禁止自由移动、普通调查；阅读确认、菜单和暂停仍按项目规则工作。特殊限制写 control_notes。
- `repeat`：`once / repeatable / guarded`。guarded 写 repeat_notes，解释回访分流和状态保护；不要把 once 理解为引擎自动防重入。
- `setup`：camera、characters、environment、audio 四项。可用中文明确说明或写 inherit；角色用 entity ID，含位置、朝向、可见性。入口有多种前态时，写出足够恢复一致画面的信息。
- `cues`：有序动作数组；允许空数组，例如仅负责条件分流的节点。
- `exit`：显式出口。没有出口不能默认当结局。

坐标示例：`position: {space: map, at: [207, 255], anchor: feet}`。未测坐标：`position: {space: anchor, name: can_front, binding: null}`，另登记需定位的问题。不要给一张未接入的地图冒写现有 scene ID。

## Cue

公共必填字段：`id / kind / origin / sources / description / completion / engine`。id 在整个文件唯一；origin 为 `source / staging / proposal`；sources 是顶层来源 ID 数组。description写这个地图里实际可见/可听/状态结果，而非空泛情绪。可选 `target / params / seconds / assets / decision_ids`。

engine包含 `status / steps / notes`。status取existing/requires_work/unresolved。steps是实际原生指令数组（例如`[{do: focus, at: [220,85]}]`）；不是给新发明的中间动作起个像原生的名字。状态cue用`node_set`标出要拆出的节点set；scene.integration说明choices/next_when出口映射。requires_work必须有plan，列具体素材/代码工作及验收。unresolved不能ready。对纯逻辑交接可steps为空，但notes必须解释实际处理位置。

原生节点命令须核对当前执行逻辑。比如focus初始camera_focus为null时，即使写time也会直接切焦点，不能写成已支持首段平滑推镜。对新增功能可编排需求并标requires_work，不能假装steps已经能执行。

`completion`：

- `immediate`：本条发起并完成状态设置，直接继续。循环音乐开始播放可以 immediate，需另写停止/交接；不是让尚未结束的移动偷偷在后台进行。
- `finished`：动作/淡变结束才继续；若固定时间表现需要 seconds，若移动按引擎速度完成可不写。
- `confirm`：玩家确认后继续，不用 seconds 模拟读完；如果目标引擎确认同时收起图片，下一条就不能要求图片继续存在。
- `interaction_result`：小游戏等返回明确结果后继续，params 写输出变量与结果定义。

kind 与核心 params：

| kind | 必须表达的内容 |
| --- | --- |
| transition | 淡黑/揭幕/切场等操作、目标、时长、结束时是否仍遮挡 |
| camera | 看向谁/哪个位置、移动方式、何时恢复跟随；不支持的缩放摇移记录能力缺口 |
| actor | target、操作（出现/移动/朝向/姿势/移除/显隐）、起终点、姿势；缺动作时给明确可行替代 |
| dialogue | params 的 speaker（entity ID）、mode、text、side（left/right/none）、portrait（asset ID 或 null）；无实体旁白 speaker 为 null。角色地图站位另写 actor |
| caption | 屏幕文字、位置、出现方式、消失方式；与剧情台词分开 |
| audio | operation（play/stop/handoff）、bus（bgm/sfx）、asset、loop；必要时淡变和结束位置。未知音频用 planned 资产，不能编文件名 |
| image | operation（show/hide）、asset、布局、是否持续；hide 后不要继续依赖它可见 |
| ui | 提示/界面开关/交互可用性，具体文案、显示位置与关闭时刻 |
| wait | 为什么暂停；固定停顿写 seconds，等点击用 confirm |
| state | params.changes 数组，每项 var、op（set/add）、value；获得物品、计错、消耗和检查点都落在准确时刻。add 仅用于 int |
| interaction | 玩家输入、目标、反馈、成功/失败/未操作/取消处理、结果变量、暂停及重试；用 params.requirement_status 标明 existing/planned/unresolved |
| parallel | params.children 为非 parallel cue 数组；全部完成才继续，父 completion 固定 finished。多个子项不能争用同一角色位置、镜头、音轨或UI属性；需要交错台词和动作且无并行能力时，给明确分步替代 |

示例：原文“C突然出现”可分成 actor.show、audio.play、dialogue 三条；不要在 dialogue.description 里藏必须发生的角色出现。

## 条件与出口

条件使用结构对象：`{var: has_key, op: eq, value: true}`。op 可用 eq/ne/gt/ge/lt/le。组合用 `{all: [条件...]}`、`{any: [...]}`、`{not: 条件}`；all/any 至少一项。无条件处省略 condition，不要写中文逻辑表达式替代机器字段。

exit 只有下列五种：

```yaml
# 顺序
type: next
next: inspect_can

# 分支，按书写顺序首个成立者生效；default 是必需兜底
type: branch
cases:
  - condition: {var: has_key, op: eq, value: true}
    next: empty_can
default: inspect_can

# 玩家选择；condition 不满足则按 unavailable 隐藏/禁用，至少一项可选
type: choice
prompt: null
cancel: disabled
options:
  - id: pick
    label: 捡起
    next: gain_key
    # 可选 condition 和 unavailable: hidden / disabled
  - id: leave
    label: 不捡起
    next: leave_can

# 归还地图控制权，不等于结局。handoff 明确镜头/UI/人物/音乐去留
type: return_control
handoff: 镜头继续跟随主角，对话和道具图关闭，保留地图音乐，允许走动和调查。

# 故事结局，稳定ID与显示编号分开
type: end
ending_id: end_example
ending_number: null
handoff: 进入结局界面；清理临时画面；可从指定检查点重试。
```

choice 的取消若返回节点，cancel 写那个节点 ID；禁用写 disabled。选项导致的状态变化放到目标节点的 state cue；未确认前不生效。跨文件跳转要登记目标文件并验证，无法读取目标时在 draft 中登记 blocking decision；检查器仅接受文件内目标，可用文件内交接节点和 return_control 描述跨事件交接，不伪造可执行跳转。

## 状态/生命周期与验收

同一幕混合自由探索和演出时分节点。道具首次获取后重复调查不得再次奖励；拒绝拾取不能把主线钥匙永久封掉。回溯另列恢复表，可用 decision.resolution 或节点 repeat_notes 写清记忆、背包、角色、错误计数、奖励和场景表现的恢复时机。

原文提出尚未定义的小游戏，不用捏造难度值将其标为完成。给已明确规则和建议参数来源，未决结果/惩罚登记 decision。若提供替代要保留用户实际玩法要求。

结构检查之外，交付前逐条追踪：首次/重复/拒绝/成功/失败/重试的出口，台词与图像出现顺序，图像关闭，演员消失，音乐归属，主角控制权恢复，以及 source/proposal 是否混淆。
