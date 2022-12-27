extends Node2D



func _on_DesignEvent1Btn_pressed():
	GameAnalytics.add_design_event(['testEvent:test1'])


func _on_DesignEvent2Btn_pressed():
	GameAnalytics.add_design_event(['testEvent:test2'])


func _on_PublishBtn_pressed():
	GameAnalytics.publish_events()


func _on_EndSessionBtn_pressed():
	GameAnalytics.end_session()


func _on_NewSceneBtn_pressed():
	get_tree().change_scene("res://scenes/Test2.tscn")


func _on_InitBtn_pressed():
	GameAnalytics.init($GridContainer/GameKeyInput.text, $GridContainer/SecretKeyInput.text)
