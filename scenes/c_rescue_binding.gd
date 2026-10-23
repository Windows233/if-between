extends Sprite2D

const STATE_TEXTURES: Array[Texture2D] = [
	preload("res://art/fx/rescue_c/rescue_bind_state_01.png"),
	preload("res://art/fx/rescue_c/rescue_bind_state_02.png"),
	preload("res://art/fx/rescue_c/rescue_bind_state_03.png"),
]


func set_state(line_index: int) -> void:
	var state_index := clampi(line_index, 0, STATE_TEXTURES.size())
	visible = state_index < STATE_TEXTURES.size()
	texture = STATE_TEXTURES[state_index] if visible else null
