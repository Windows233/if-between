## 救援小游戏的三线计时与判定模型。
## 练习、正式判定和错误确认分开推进，空等不会产生错误。
## phase 表示完整往返的 0..1 周期；外部用 advance 推进、submit 判定或确认。
class_name RescueTiming
extends RefCounted

enum State { CLOSED, PRACTICE, PRACTICE_FEEDBACK, RUNNING, MISTAKE, SUCCEEDED, FAILED }
enum Verdict { NONE, EARLY, HIT, LATE }

const LINE_COUNT: int = 3
const ERROR_LIMIT: int = 3
const ROUND_TRIP_SECONDS: Array[float] = [3.0, 2.6, 2.4]
const WINDOW_RATIOS: Array[float] = [0.35, 0.30, 0.25]
const EDGE_TOLERANCE: float = 0.00000001

var state: State = State.CLOSED
var phase: float = 0.0
var line_index: int = 0
var mistakes: int = 0
var last_verdict: Verdict = Verdict.NONE


func reset() -> void:
	state = State.PRACTICE
	phase = 0.0
	line_index = 0
	mistakes = 0
	last_verdict = Verdict.NONE


func close() -> void:
	state = State.CLOSED


func round_trip_seconds() -> float:
	return ROUND_TRIP_SECONDS[clampi(line_index, 0, LINE_COUNT - 1)]


func window_ratio() -> float:
	return WINDOW_RATIOS[clampi(line_index, 0, LINE_COUNT - 1)]


func window_start() -> float:
	return (1.0 - window_ratio()) * 0.5


func window_end() -> float:
	return (1.0 + window_ratio()) * 0.5


func marker_position() -> float:
	return 1.0 - absf(2.0 * fposmod(phase, 1.0) - 1.0)


func advance(delta: float) -> void:
	if state != State.PRACTICE and state != State.RUNNING:
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	phase = fposmod(phase + delta / round_trip_seconds(), 1.0)


func submit() -> Verdict:
	if state == State.PRACTICE_FEEDBACK or state == State.MISTAKE:
		state = State.RUNNING
		phase = 0.0
		last_verdict = Verdict.NONE
		return Verdict.NONE
	if state != State.PRACTICE and state != State.RUNNING:
		return Verdict.NONE
	last_verdict = _judge()
	if state == State.PRACTICE:
		state = State.PRACTICE_FEEDBACK
	elif last_verdict == Verdict.HIT:
		line_index += 1
		phase = 0.0
		if line_index == LINE_COUNT:
			state = State.SUCCEEDED
	else:
		mistakes += 1
		state = State.FAILED if mistakes >= ERROR_LIMIT else State.MISTAKE
	return last_verdict


func _judge() -> Verdict:
	var position: float = marker_position()
	if position >= window_start() - EDGE_TOLERANCE \
			and position <= window_end() + EDGE_TOLERANCE:
		return Verdict.HIT
	var moving_right: bool = fposmod(phase, 1.0) < 0.5
	var before_window: bool = position < window_start()
	return Verdict.EARLY if before_window == moving_right else Verdict.LATE
