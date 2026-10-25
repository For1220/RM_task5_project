extends Node
signal snapshot_updated(snapshot:Dictionary)
var current:Dictionary={}
func publish(snapshot:Dictionary)->void:
	current=snapshot
	snapshot_updated.emit(snapshot)
