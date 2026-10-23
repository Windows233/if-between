解救C小游戏素材调用说明

资源位置
界面：res://art/ui/rescue_c/（12张PNG）
束缚：res://art/fx/rescue_c/（4张PNG）
完整文件路径、原文件名、尺寸、用途及SHA-256：同目录asset_manifest.json。

界面部件
rescue_panel.png：横向背景面板，1216×248。
rescue_track.png：独立轨道，1072×48。
rescue_cursor.png：移动菱形，40×64。
rescue_safe_zone.png：安全窗口，288×48。
rescue_confirm_normal/hover/pressed.png：按钮三态，各416×64。
rescue_step_empty/current/done.png：进度三态，各48×48。
rescue_result_success/fail.png：成功/失误图形，各64×64。
文字、按键名称、进度数字由游戏绘制，PNG不包含文字。

缩放与调用
界面源图按约四倍逻辑尺寸准备，可从0.25缩放开始校准；当前游戏逻辑视口320×180。
轨道、菱形、安全窗口独立摆放；按按钮三态切图，不改变画布与位置。
安全窗口缩窄时保留端部边框、伸缩中间区域；避免直接拉伸造成端部变形。
束缚图保留256×256完整画布和透明留白，与C实际显示尺寸及脚底位置一起校准，不按可见像素包围盒单独居中。

束缚状态用法
四张是整组束缚逐渐减少的状态，不是四根独立线，也不是三根可叠加的线层。
初始/成功0次：res://art/fx/rescue_c/rescue_bind_state_01.png
成功1次：res://art/fx/rescue_c/rescue_bind_state_02.png
成功2次：res://art/fx/rescue_c/rescue_bind_state_03.png
成功3次：隐藏整个束缚层，不加载完成贴图。
rescue_bind_state_04.png仍有一条斜线，作为备用状态保留，不接作“完全解开”。
本说明记录后续接入约定，本次没有新增小游戏逻辑或更改事件。

来源与待补
全部16张PNG直接来自M01-M08.zip，像素与文件内容未修改；四张束缚图仅统一文件名，去除重复.png后缀并明确state编号。
原始压缩包未包含可编辑源文件。M09去C版操场不在本次包内，另行交付。
