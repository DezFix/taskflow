/// Запись голосовых сообщений: Android и браузер.
///
/// Запись всегда идёт через поток байтов, а не через файл: так код
/// одинаково работает на Android и в браузере, где файловой системы нет.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Состояние записи голосового.
enum VoiceRecordingState { idle, recording, paused }

/// Результат записи: аудио и его длительность.
typedef VoiceCapture = ({Uint8List bytes, Duration duration});

/// Конфигурация записи: AAC в контейнере m4a.
const RecordConfig kVoiceConfig = RecordConfig(
  encoder: AudioEncoder.aacLc,
  sampleRate: 44100,
  numChannels: 1,
  bitRate: 64000,
);

/// Максимальная длительность голосового: дольше распознавать бессмысленно.
const Duration kMaxVoiceLength = Duration(minutes: 5);

/// Обёртка над пакетом record с понятными состояниями.
class VoiceRecorder {
  VoiceRecorder();

  final AudioRecorder _recorder = AudioRecorder();

  VoiceRecordingState _state = VoiceRecordingState.idle;
  StreamSubscription<Uint8List>? _subscription;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  DateTime? _startedAt;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _failed = false;

  VoiceRecordingState get state => _state;

  bool get isRecording => _state == VoiceRecordingState.recording;

  bool get isActive => _state != VoiceRecordingState.idle;

  Duration get elapsed => _elapsed;

  /// Запись достигла предела: пора отправлять.
  bool get reachedLimit => _elapsed >= kMaxVoiceLength;

  /// Проверяет разрешение на микрофон.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Запрашивает разрешение на запись звука.
  Future<bool> ensurePermission() => _recorder.hasPermission();

  /// Начинает запись. False означает, что разрешение не выдано.
  Future<bool> start() async {
    if (_state != VoiceRecordingState.idle) return true;
    if (!await ensurePermission()) return false;

    _builder.clear();
    _elapsed = Duration.zero;
    _failed = false;
    _startedAt = DateTime.now();

    try {
      final stream = await _recorder.startStream(kVoiceConfig);
      _subscription = stream.listen(_onData);
    } catch (_) {
      // Микрофон занят или платформа не дала доступ: сообщаем вызывающему.
      _failed = true;
      _state = VoiceRecordingState.idle;
      _startedAt = null;
      return false;
    }

    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final started = _startedAt;
      if (started == null) return;
      _elapsed = DateTime.now().difference(started);
    });

    _state = VoiceRecordingState.recording;
    return true;
  }

  void _onData(Uint8List data) {
    _builder.add(data);
  }

  /// Была ли запись прервана ошибкой платформы.
  bool get failed => _failed;

  Future<void> pause() async {
    if (_state != VoiceRecordingState.recording) return;
    await _recorder.pause();
    _state = VoiceRecordingState.paused;
  }

  Future<void> resume() async {
    if (_state != VoiceRecordingState.paused) return;
    await _recorder.resume();
    _state = VoiceRecordingState.recording;
  }

  /// Останавливает запись и отдаёт аудио.
  Future<VoiceCapture?> stop() async {
    if (_state == VoiceRecordingState.idle) return null;

    _ticker?.cancel();
    _ticker = null;

    try {
      await _recorder.stop();
    } catch (_) {
      // Данные уже накоплены в буфере: продолжаем.
    }

    // Последний кусок аудио приходит при закрытии потока, поэтому
    // сначала дожидаемся его завершения, потом забираем буфер.
    await _subscription?.cancel();
    _subscription = null;

    final duration = DateTime.now().difference(_startedAt ?? DateTime.now());
    _state = VoiceRecordingState.idle;
    _startedAt = null;
    _elapsed = Duration.zero;

    final bytes = _builder.takeBytes();
    if (bytes.isEmpty) return null;
    return (bytes: bytes, duration: duration);
  }

  /// Отменяет запись: ничего не отправляем.
  Future<void> cancel() async {
    if (_state == VoiceRecordingState.idle) return;
    _ticker?.cancel();
    _ticker = null;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _recorder.cancel();
    } catch (_) {
      // Состояние всё равно сброшено.
    }
    _state = VoiceRecordingState.idle;
    _startedAt = null;
    _elapsed = Duration.zero;
    _builder.clear();
  }

  Future<void> dispose() async {
    _ticker?.cancel();
    await _subscription?.cancel();
    await _recorder.dispose();
  }
}

/// Форматирует длительность записи для подписи.
String formatRecordingTime(Duration duration) {
  final total = duration.inSeconds;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
