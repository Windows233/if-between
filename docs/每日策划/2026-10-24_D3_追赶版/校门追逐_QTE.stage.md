# 校门双QTE追逐演出顺序

状态：可供程序实现的需求稿，不等于已经运行。详细玩法与当天分工见《程序执行策划案.md》。结构稿和本说明同源。

## 教学楼门外准备

地图：school_gate；控制方式：cutscene。

- 无倒计时说明，玩家确认后开跑；完成方式：confirm。
- 存追逐前快照，清两个临时QTE结果并创建黑雾；完成方式：immediate。新增追逐会话初始化与检查点恢复；保存时间、镜头、输入、音乐和背包前态；禁止其他门和普通调查，保留暂停。

出口：{"type": "next", "next": "run_q1"}

## 可控跑动与第1次QTE

地图：school_gate；控制方式：minigame。

- 玩家移动到进度线后，黑猫扑近、慢动作和圈式按键判定；完成方式：interaction_result。新增可控追逐会话和圈式QTE；真实时间计时不受慢动作影响，屏幕UI不震动；忽略旧按住与重复事件；触发依次且一次。

出口：{"type": "branch", "cases": [{"condition": {"var": "q1_ok", "op": "eq", "value": true}, "next": "run_q2"}], "default": "caught"}

## 可控跑动与第2次QTE

地图：school_gate；控制方式：minigame。

- 玩家移动到进度线后，黑猫扑近、慢动作和圈式按键判定；完成方式：interaction_result。新增可控追逐会话和圈式QTE；真实时间计时不受慢动作影响，屏幕UI不震动；忽略旧按住与重复事件；触发依次且一次。

出口：{"type": "branch", "cases": [{"condition": {"var": "q2_ok", "op": "eq", "value": true}, "next": "arrive"}], "default": "caught"}

## 玩家到图书馆门前才成功

地图：school_gate；控制方式：minigame。

- 两次成功后继续由玩家跑到门前接近区；完成方式：interaction_result。终点区域由追逐控制器判断；不改普通portal rect，不提前触发locked事件；到门才交接成功。
- 撤黑雾/圆圈/计时，恢复时间镜头输入与音频前态；完成方式：finished。所有出口共用清理函数；解除普通门与调查临时拦截，清定时器及输入事件。
- 成功抵达后才开放图书馆；完成方式：immediate。
- 沿用真实图书馆入口切图；完成方式：finished。

出口：{"type": "return_control", "handoff": "图书馆from_school_gate，时间与镜头恢复，控制交给馆内首段剧情；未接馆内时只算入口完成。"}

## 黑猫追上与失败CG

地图：school_gate；控制方式：cutscene。

- 判负一次，恢复时间镜头后短扑近压黑；完成方式：finished。先清计时和临时输入，恢复原倍率；0.4秒扑近/压黑不会再次触发QTE。
- 显示校园失败近景；正式CG未交时用校门加黑雾定格；完成方式：confirm。接最终校园CG；未交图时明确临时合成定格，不能调用梦境卧室猫图冒充正式校园CG。
- 显示End5字卡，不新增错位结局编号；完成方式：confirm。

出口：{"type": "choice", "prompt": null, "cancel": "disabled", "options": [{"id": "retry", "label": "重试追逐", "next": "prepare"}, {"id": "title", "label": "返回标题", "next": "ending"}]}

## 正式失败结局

地图：school_gate；控制方式：cutscene。


出口：{"type": "end", "ending_id": "end4_iron", "ending_number": 5, "handoff": "按现有结局流程登记与返回标题；进入前先清全部追逐状态，时间/相机不残留。"}

程序必须新增追逐/实时圈式QTE能力；本文不编造原生do:chase命令。路径只验证静态通行，操控、碰撞避让、UI与相机需要按执行策划案实测。
