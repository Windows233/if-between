学校美术更改图入库记录（2026-10-22）

13张有效PNG，14个调用路径；学生证同时更新剧情特写与背包图标。忽略__MACOSX与._元数据。
所有原图像素、透明通道、文件内容保持不变；规范化英文文件名。原压缩包未包含可编辑源文件。
完整来源、用途、尺寸、旧新哈希和审核结论见school_art_update_20261022.json。

已经替换
art/item/student_id_half.png：沙坑事件正在使用的半张学生证特写，六年二班与原对白一致。
art/item/student_id.png：背包动态调用的student_id占位图，采用同一交付图片。
art/item/charm.png、night_tear.png、cat_doll.png：三个正式物品图替换名称色块；相应物品尚未接入获取剧情。
五个物品路径使用Godot导入尺寸上限512，保留高分辨率PNG源稿；背包和演出按实际尺寸等比显示。
art/props/ch2_notice_board.png：更新已有未接入的校门公告栏素材。
art/props/ch2_sandbox_dug.png：更新已有未接入的沙坑特写素材。

新增可调用图
art/props/ch2_teaching_notice_board.png：教学楼公告栏。
art/props/ch2_blackboard.png：黑板特写。
art/props/ch2_mirror.png：镜子特写。
art/props/ch2_fairy_tale_book.png：童话书展开页。
art/props/ch2_sculpture_inscription.png：雕塑铭文牌，不能当完整雕塑或喷泉替换。
以上未新增事件或改地图；图中文字将来接入时仍需文案核对。原始学校素材目录不覆盖。
部分透明抠图边缘有浅色描边，独立贴进深色场景前需再次检查小尺寸显示；当前仅作素材库/特写用途。

需要修改后再启用
art/props/ch2_register.png：登记册尚未写入主角姓名，与门卫室现有对白不完全匹配。不可替换gatehouse_desk.png，它是完整桌子；本次保留桌子和现有剧情。
art/map/candidates/school_yard_no_c.png：C已去掉，但整幅画面重绘，分辨率改为1535×1024，部分物件与现有碰撞/交互框不对齐。该图只入候选库；正式art/map/school_yard.png和地图JSON保持原样。
操场返修优先回到现用1264×843底图，只清理秋千旁C并补原地砖阴影。若采用本次重绘版，则需地图编辑师重新核对物件位置、碰撞、交互与遮挡，另行验收。

回退
本次替换的已跟踪资源可通过本次Git提交的父版本恢复。原先尚未跟踪的公告栏/沙坑图额外备份在本次工作区核查目录before/art/props下；不要覆盖其他人的工作区改动。

验证结果
Godot导入与二次扫描退出码0；14/14贴图加载成功；学生证剧情路径保持有效；数据自查通过，全量4350/4350通过。编辑器退出仍有既有ObjectDB/资源释放诊断，无新增贴图加载失败。
本机替换前备份：C:\Users\admin\.codex\visualizations\2026\10\21\01a15ee2-f568-7772-b6c4-3de0233ee5d3\art_update_review\before
