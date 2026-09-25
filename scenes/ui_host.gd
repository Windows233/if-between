## 界面调度：现在谁开着、按键先给谁、谁开着的时候角色该停下。
##
## 从 `main.gd` 抽出来的理由，是**加一个界面要改两处**这件事本身：
## `_unhandled_input()` 里要加一段「键盘先给它」，
## `update_player_control()` 里又要加一段「它开着时别让角色动」。
## 加到第三、第四个界面时，这两处会各自长成一串 `or`，
## 漏改一处就是「界面关了但人还是动不了」这类最难查的状态卡死。
##
## 所以这里只收这三件事，界面之间**不互相认识**：
## 谁在谁上面由这个调度器说了算，界面自己不知道自己排第几。
##
## 跟 `SaveManager` 一样是应用服务：认识 ui/ 下那一堆界面，
## 但不认识 MapDef、Player、Camera。
class_name UiHost
extends RefCounted

var dialogue: DialogueBox = null
var choice_menu: ChoiceMenu = null
var gallery: EndingGalleryPanel = null
var save_menu: SaveMenu = null
var settings: SettingsPanel = null
var title: TitleScreen = null
var inventory: InventoryPanel = null
var pause_menu: PauseMenu = null


func setup(
	p_dialogue: DialogueBox,
	p_choice_menu: ChoiceMenu,
	p_gallery: EndingGalleryPanel,
	p_save_menu: SaveMenu,
	p_settings: SettingsPanel,
	p_title: TitleScreen,
	p_inventory: InventoryPanel = null,
	p_pause_menu: PauseMenu = null,
) -> void:
	dialogue = p_dialogue
	choice_menu = p_choice_menu
	gallery = p_gallery
	save_menu = p_save_menu
	settings = p_settings
	title = p_title
	inventory = p_inventory
	pause_menu = p_pause_menu


# ---------------------------------------------------------------- 状态

## 有界面占着屏幕吗。**角色能不能动、鼠标点不点得动地图，都只问这一处。**
func is_busy() -> bool:
	return _top() != null


## 当前最上面的界面。没有就是 null。
##
## 顺序就是「谁盖住谁」：**按各自的 `layer` 从大到小排**（`ui/*.gd` 的
## `setup()` 里写着）。界面自己不该知道自己排第几，所以这份顺序只写在这里。
##
## **两边必须一致。** 不一致的症状很难查：面板看得见，但按键给了别人 ——
## 屏幕上一个能选的东西按不动，另一个看不见的在偷偷接键。
##
## 2026-09-24 那次「主菜单点设置、按 ESC 黑屏」就是这里和层号一起错的：
## 标题原来排在最前，但它的层号（21）比设置（17）高 —— 逻辑顺序和绘制顺序
## 是反的。当时靠「标题开子面板时把自己收起来」腾位置，于是关掉设置之后
## 谁都不在，屏幕一片黑。现在两边都改对了：
##
## - **子面板一律排在标题前面**（设置 22、存档 23、图鉴 24 都高于标题 21），
##   标题开子面板时**自己不收**（`TitleScreen.STAY_OPEN`），
##   关掉子面板自然回到标题；
## - 暂停菜单仍然夹在中间（15）：从它开出来的存档/设置画在它上面，
##   关掉之后人回到它手里；它自己压在选项框（13）上面 ——
##   剧情等着选的时候按 ESC 会开它，两个同时在场上。
func _top() -> CanvasLayer:
	if gallery != null and gallery.is_open():
		return gallery
	if save_menu != null and save_menu.is_open():
		return save_menu
	if settings != null and settings.is_open():
		return settings
	if title != null and title.is_open():
		return title
	if inventory != null and inventory.is_open():
		return inventory
	if pause_menu != null and pause_menu.is_open():
		return pause_menu
	if choice_menu != null and choice_menu.is_open():
		return choice_menu
	if dialogue != null and dialogue.is_open():
		return dialogue
	return null


# ---------------------------------------------------------------- 输入

## 键盘先给最上面那个界面。返回 true 表示这次按键被它吃了，
## 外面不该再拿它去触发交互。
func handle_key(keycode: int) -> bool:
	var top := _top()
	if top == null:
		return false

	if top == title:
		return title.handle_key(keycode)
	if top == save_menu:
		return save_menu.handle_key(keycode)
	if top == settings:
		return settings.handle_key(keycode)
	if top == pause_menu:
		return pause_menu.handle_key(keycode)
	if top == gallery:
		return gallery.handle_key(keycode)
	if top == inventory:
		return inventory.handle_key(keycode)
	if top == choice_menu:
		return choice_menu.handle_key(keycode)
	if top == dialogue:
		return dialogue.handle_key(keycode)
	return false


## 把 ESC 交给最上面那个界面，它吃掉了就返回 true。
##
## **交给谁、它认不认，由那个界面自己说**，这里不替它们分。现在这样：
##
## - 图鉴、背包、存档菜单、设置、暂停菜单自己 —— 都是「ESC = 关掉我自己」。
## - 对话框 —— 平时不认（于是 ESC 落到外面的「开暂停菜单」），
##   但**记录面板开着时认**（那一下是「关掉记录」）。
## - 选项框 —— 剧情的 IF 选项不认（那一步必须选一个，见 `ChoiceMenu`），
##   角色的动作菜单认。
##
## 对话框和剧情的选项框认不认这件事，以前是靠「别把键交给它们」硬挡的 ——
## 挡出来的结果是这个键在大半个游戏里失效：一次对话从头到尾弹不出菜单，
## 而屏幕上那句提示还在劝玩家「此处建议存档」（2026-09-23 就是这么咬人的）。
func try_escape() -> bool:
	if _top() == null:
		return false
	return handle_key(KEY_ESCAPE)


# ---------------------------------------------------------------- 开合

## 关掉所有覆盖在上面的界面。**切场景、读档这类「凭空跳转」的场合用**：
## 界面上写着的是上一个场景的事，跳完了还在就对不上了。
##
## 暂停菜单也在内 —— 从暂停菜单里选「加载」，读回来的应该是**游戏画面**，
## 而不是还停在暂停菜单上（玩家会以为读档没生效）。
func close_overlays() -> void:
	if pause_menu != null:
		pause_menu.close()
	if gallery != null:
		gallery.close()
	if settings != null:
		settings.close()
	if save_menu != null:
		save_menu.close()
	if inventory != null:
		inventory.close()
	if choice_menu != null:
		choice_menu.close()
	if dialogue != null:
		dialogue.close()


## 打开存档菜单之前先收起别的：图鉴和存档菜单都是全屏面板，
## 叠着开的话关掉一个底下还压着一个，看着像卡住了。
##
## **但剧情的选择框不能收。** 它不是「一个面板」，是**剧情正停在那儿等玩家选**：
## 关掉它，对话框就卡在「等选择」那个空壳上，选项再也点不出来 ——
## 死锁（2026-09-24 策划报的「接委托那段按下保存，对话框和选项都没了」）。
##
## 层号上也不会挤：选择框 13、存档菜单 23，菜单盖在上面，本来就看不出底下有人。
func open_save_menu(p_entries: Array[SaveMenu.Entry], mode: int) -> void:
	if gallery != null:
		gallery.close()
	if save_menu != null:
		save_menu.open(p_entries, mode)
