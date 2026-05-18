extends Area2D

func _process(_delta: float) -> void:
	rotation = -get_parent().rotation # keep top scan on the top of the ball
