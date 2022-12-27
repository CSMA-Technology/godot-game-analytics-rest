extends Node
const uuid = preload("res://addons/game_analytics/uuid.gd")

var ctx = HMACContext.new()

var _game_key: String
var _secret_key: String

var http_request = HTTPRequest.new()

var initialized = false
var session_id: String
var session_start_time: int
var is_publishing_events = false
var time_offset = 0

const SANDBOX_URL = 'https://sandbox-api.gameanalytics.com'
const PRODUCTION_URL = 'https://api.gameanalytics.com'
var base_url

const CATEGORY_USER = 'user'
const CATEGORY_SESSION_END = 'session_end'
const CATEGORY_DESIGN = 'design'

var queued_events = []

signal session_started
signal publish_completed

func _ready():
	add_child(http_request)
	get_tree().set_auto_accept_quit(false)
	get_tree().set_quit_on_go_back(false)

func init(game_key := '', secret_key := ''):
	if initialized:
		print("Game analytics already initialized. Ignoring call to `init`.")
		return
	# Defaults into sandbox mode if keys are not provided
	if !game_key or !secret_key:
		print("Game key and/or secret key not provided. Starting Game Analytics session in sandbox mode.")
		# These are intentionally hard-coded sandbox values
		_game_key = '5c6bcb5402204249437fb5a7a80a4959'
		_secret_key = '16813a12f718bc5c620f56944e1abc3ea13ccbac'
		base_url = SANDBOX_URL
	else:
		print("Starting Game Analytics session in production mode.")
		_game_key = game_key
		_secret_key = secret_key
		base_url = PRODUCTION_URL
	initialized = true
	start_session()

func _notification(what):
	if what in [MainLoop.NOTIFICATION_WM_QUIT_REQUEST, MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST]:
		if initialized and session_id:
			end_session()
			yield(self, "publish_completed")
		get_tree().quit()
	if initialized and what == MainLoop.NOTIFICATION_WM_FOCUS_IN:
		start_session()
	if session_id and what == MainLoop.NOTIFICATION_WM_FOCUS_OUT:
		end_session()

func get_auth_header(body:String):
	var err = ctx.start(HashingContext.HASH_SHA256, _secret_key.to_utf8())
	assert(err == OK)
	err = ctx.update(body.to_utf8())
	assert(err == OK)
	var hmac = ctx.finish()
	return Marshalls.raw_to_base64(hmac)

func start_session():
	assert(!session_id, 'Cannot start new Game Analytics session while one is still active. Call end_session first.')
	var body = JSON.print({
		'platform': OS.get_name(),
		"sdk_version":"rest api v2"
	})
	var url = base_url + '/v2/' + _game_key + '/init'
	var headers = ['Content-Type: application/json', 'Authorization: ' + get_auth_header(body)]
	var err = http_request.request(url, headers, true, HTTPClient.METHOD_POST, body)
	assert(err == OK)
	http_request.connect("request_completed", self, '_on_init_request_completed', [], CONNECT_ONESHOT)

func _is_request_successful(result: int, response_code: int):
	return result == HTTPRequest.RESULT_SUCCESS and response_code == 200

func _on_init_request_completed(result: int, response_code: int, _headers: PoolStringArray, body: PoolByteArray):
	if !_is_request_successful(result, response_code):
		push_error('Game analytics init failed. Request Result: ' + str(result) + '. Response code: ' + str(response_code))
		return
	var response = JSON.parse(body.get_string_from_utf8()).result
	if !response.enabled:
		push_error("Game analytics init failed. Server is reporting analytics are not enabled.")
		return
	session_start_time = OS.get_unix_time()
	session_id = uuid.v4()
	time_offset = response.server_ts - session_start_time
	print("Game Analytics initalized")
	add_event(CATEGORY_USER)
	emit_signal("session_started")

func _on_event_request_completed(result: int, response_code: int, _headers: PoolStringArray, _body: PoolByteArray):
	if _is_request_successful(result, response_code):
		print("Published " + str(queued_events.size()) + " events.")
		queued_events.clear()
	else:
		push_error('Game analytics event publish failed. Request Result: ' + str(result) + '. Response code: ' + str(response_code))
	is_publishing_events = false
	emit_signal("publish_completed")

func end_session():
	assert(session_id, 'There is no active Game Analytics session to end')
	var session_length = OS.get_unix_time() - session_start_time
	print("Ending Game Analytics session " + session_id)
	add_event(CATEGORY_SESSION_END, { "length": session_length })
	publish_events()
	session_id = ''

func add_design_event(id_parts: PoolStringArray, value: float = 0):
	assert(id_parts.size() > 0 && id_parts.size() <= 5, 'Design event IDs must be between 1 and 5 parts long')
	var event_id = id_parts.join(':')
	add_event(CATEGORY_DESIGN, { 'event_id': event_id, 'value': value })

func add_event(category: String, fields: Dictionary = {}):
	var client_ts = OS.get_unix_time() + time_offset
	if !session_id:
		print('Cannot add events until session is started. Waiting.')
		yield(self, "session_started")
	while is_publishing_events:
		print("Publish in progress. Waiting to add event until publish is completed.")
		yield(self, "publish_completed")
	var user_id = OS.get_unique_id()
	if !user_id: #OS.get_unique_id does not work on web
		user_id = 'test'
	var default_fields = {
		"device": "unknown",
		"v": 2,
		"user_id": user_id,
		"client_ts": client_ts,
		"sdk_version": "rest api v2",
		"os_version": OS.get_name().to_lower() + " 10",
		"manufacturer": "",
		"platform": OS.get_name().to_lower(),
		"session_id": session_id,
		"session_num": 1
	}
	var event = fields.duplicate(true)
	event.merge(default_fields)
	event.category = category
	queued_events.append(event)
	print("Event added: " + JSON.print(event))

func publish_events():
	if !session_id:
		print("Cannot publish analytics until session is started. Waiting.")
		yield(self, "session_started")
	while is_publishing_events:
		print("Publish in progress. Waiting to start new publish until prior one is completed.")
		yield(self, "publish_completed")
	is_publishing_events = true
	if queued_events.empty():
		print("No events to publish")
		return
	print('Publishing ' + str(queued_events.size()) + " events")
	var body = JSON.print(queued_events)
	var url = base_url + '/v2/' + _game_key + '/events'
	var headers = ['Content-Type: application/json', 'Authorization: ' + get_auth_header(body)]
	var err = http_request.request(url, headers, true, HTTPClient.METHOD_POST, body)
	assert(err == OK)
	http_request.connect("request_completed", self, '_on_event_request_completed', [], CONNECT_ONESHOT)
	
