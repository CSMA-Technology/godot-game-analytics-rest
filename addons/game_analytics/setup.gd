tool
extends EditorPlugin


func _enter_tree():
	add_autoload_singleton("GameAnalytics", "res://addons/game_analytics/GameAnalytics.gd")

func _exit_tree():
	remove_autoload_singleton('GameAnalytics')
