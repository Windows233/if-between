# 救援小游戏素材入库记录（2026-10-23）

本批入库操场背景、御守、C 立绘和三条救援音效；剧情接线在代码集成中更新。

## 图片

| 项目资源 | 来源与处理 |
| --- | --- |
| `art/map/school_yard.png` | `C:/Users/q3382/Documents/GameProject/待用资源/地图/更改图/操场.PNG`（1535×1024，RGB）；Lanczos 等比居中规整至旧画布 1264×843，比例差仅约 0.026%，无额外画面元素。 |
| `art/item/charm.png` | `C:/Users/q3382/Documents/GameProject/待用资源/地图/更改图/御守.PNG`（1920×2208，RGBA）；逐字节复制，保留原透明通道。 |
| `art/portrait/c_base.png` | `C:/Users/q3382/Documents/GameProject/待用资源/透明底立绘/c.png`（RGBA）；复用现有 C 半身立绘，保留源尺寸、透明通道与像素，不调用图像生成 API。 |

## 音效

来源目录：`C:/Users/q3382/Documents/GameProject/待用资源/音频/小游戏音效及连续音效试听/`。三条事件音效原格式均为未压缩 PCM、44.1 kHz、16 位、双声道。保留起音附近内容、使用 4 ms 平滑起音，末尾采用余弦淡出，避免直接硬切。

| 输出 | 源时长 | 输出时长 | 淡出 |
| --- | ---: | ---: | ---: |
| `audio/sfx/rescue_success.wav` | 0.743 s | 0.340 s | 45 ms |
| `audio/sfx/rescue_mistake.wav` | 0.813 s | 0.320 s | 55 ms |
| `audio/sfx/rescue_complete.wav` | 1.881 s | 1.000 s | 120 ms |

`连续音效.wav`（4.272 s）只作试听，不复制、不接事件。本批结束时对六个外部源文件重新计算 SHA-256，全部与读取前一致。

Godot 4.7.2 的 `--headless --path <项目> --import` 返回退出码 0；操场和御守沿用资源导入记录，三条新 WAV 的 `.import` 文件已生成。宿主同时报告系统根证书读取和安装目录 `editor_settings-4.7.tres` 写入错误，以及退出资源清理警告；不影响本批资源导入，未修改该引擎安装目录。

## SHA-256

下表记录原始外部文件和本批输出的 SHA-256。连续试听仅记录输入散列。

| 文件 | SHA-256 |
| --- | --- |
| 源 `操场.PNG` | `267c71118e1a66eb3277fbd485ed94b2b0183b790af8ce120992b1c6cea6f11b` |
| 输出 `art/map/school_yard.png` | `459d34657f913e053a2ca5fb5c3bf49d357cb39a1738304094d520e565adbc9f` |
| 源 `御守.PNG` | `6b46249ee413f58c152e75c8b9ad0d0d596ed69948a42199c1d0ec8bcdea1c61` |
| 输出 `art/item/charm.png` | `6b46249ee413f58c152e75c8b9ad0d0d596ed69948a42199c1d0ec8bcdea1c61` |
| 源 `c.png` | `022811372959d4bcd617b5450f5030f4f470b99ebfa9cf9c6f46d5f50104e87` |
| 输出 `art/portrait/c_base.png` | `022811372959d4bcd617b5450f5030f4f470b99ebfa9cf9c6f46d5f50104e87` |
| 源 `rescue_success.wav` | `b2685bf6da40c8070bd7de3795559a984bf625c7fb10040b2437a10dd209a026` |
| 输出 `audio/sfx/rescue_success.wav` | `7fd30ea7434f78450ad86e4ac56c9d1722d475ba471dffd3644e22b1e23a0c19` |
| 源 `rescue_mistake.wav` | `119d39392dc540acf2c5bf859a2706286716e6201c6244fb7ee1cca95b4e927d` |
| 输出 `audio/sfx/rescue_mistake.wav` | `1d5372efe8c8e0a1019d3e2e7fc3a4d1fc24dce6c11817643694a075ebcf3e4c` |
| 源 `rescue_complete.wav` | `3b5d9a2a2accf75a17ad20b83c885d1514045375c55dbe5bcb76f0f56b886e87` |
| 输出 `audio/sfx/rescue_complete.wav` | `d757adf8ef5cd22371bccbd2329bfd367ec2f800856b5bff2c6a8c54c0f3e183` |
| 源 `连续音效.wav`（仅试听） | `4712953ac06dbbc285a4b461ca56e62efb80af62304ff2776b03f1c619b6f480` |
