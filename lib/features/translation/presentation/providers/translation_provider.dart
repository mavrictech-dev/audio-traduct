import 'dart:async';
import 'package:audio_traductor/core/di/injection_container.dart';
import 'package:audio_traductor/core/services/mic_passthrough_service.dart';
import 'package:audio_traductor/features/translation/data/datasources/tts_datasource.dart';
import 'package:audio_traductor/features/translation/domain/entities/translation_paragraph.dart';
import 'package:audio_traductor/features/translation/domain/entities/translation_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TranslationStatus {
  idle,
  listening,
  translating,
  playing,
  error,
  downloadingModels,
}

class TranslationState {
  final TranslationStatus status;
  final List<TranslationParagraph> paragraphs;
  final String? errorMessage;
  final bool isStreaming;
  final String? playingParagraphId;
  final String? currentSessionId;
  final String sessionName;
  final bool micMode;
  final double downloadProgress;
  final String? downloadLanguage;
  final String? downloadStepLabel;

  const TranslationState({
    this.status = TranslationStatus.idle,
    this.paragraphs = const [],
    this.errorMessage,
    this.isStreaming = false,
    this.playingParagraphId,
    this.currentSessionId,
    this.sessionName = '',
    this.micMode = false,
    this.downloadProgress = 0.0,
    this.downloadLanguage,
    this.downloadStepLabel,
  });

  TranslationState copyWith({
    TranslationStatus? status,
    List<TranslationParagraph>? paragraphs,
    String? errorMessage,
    bool? isStreaming,
    String? playingParagraphId,
    String? currentSessionId,
    String? sessionName,
    bool? micMode,
    double? downloadProgress,
    String? downloadLanguage,
    String? downloadStepLabel,
  }) {
    return TranslationState(
      status: status ?? this.status,
      paragraphs: paragraphs ?? this.paragraphs,
      errorMessage: errorMessage,
      isStreaming: isStreaming ?? this.isStreaming,
      playingParagraphId: playingParagraphId,
      currentSessionId: currentSessionId,
      sessionName: sessionName ?? this.sessionName,
      micMode: micMode ?? this.micMode,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadLanguage: downloadLanguage ?? this.downloadLanguage,
      // A diferencia de downloadLanguage (que conserva el valor previo si se
      // pasa null), este campo sí se limpia explícitamente: lo necesitamos
      // para distinguir el paso "modelo de Whisper" del paso "modelos ML Kit"
      // dentro del mismo estado downloadingModels.
      downloadStepLabel: downloadStepLabel,
    );
  }
}

class TranslationNotifier extends StateNotifier<TranslationState> {
  TranslationNotifier() : super(const TranslationState());

  StreamSubscription? _subscription;
  int _counter = 0;
  String _currentTargetLanguage = 'es';
  String _currentVoiceName = '';
  double _currentSpeed = 0.5;
  final MicPassthroughService _passthrough = MicPassthroughService();

  @override
  void dispose() {
    _subscription?.cancel();
    _passthrough.dispose();
    super.dispose();
  }

  void setMicMode(bool v) {
    state = state.copyWith(micMode: v);
  }

  Future<void> startTranslation({
    required String sourceLanguage,
    required String targetLanguage,
    required String voiceName,
    required double speed,
    String? existingSessionId,
    String? sessionName,
  }) async {
    if (state.isStreaming) return;

    // Asegurar que no quede ningún subscription colgado
    await _subscription?.cancel();
    _subscription = null;

    _counter = 0;
    _currentTargetLanguage = targetLanguage;
    _currentVoiceName = voiceName;
    _currentSpeed = speed;

    // Precalentar la voz objetivo mientras se preparan los modelos evita la
    // pausa perceptible antes de que se lea la primera traducción.
    unawaited(RealTtsDatasource.instance.warmup(targetLanguage, voiceName));

    // Modo micrófono: passthrough directo (sin traducción)
    if (state.micMode) {
      state = state.copyWith(
        status: TranslationStatus.listening,
        isStreaming: true,
        errorMessage: null,
      );
      await _passthrough.start();
      return;
    }

    try {
      // ── Verificar / descargar el modelo de Whisper (STT offline) ──
      // Va antes que ML Kit: es la descarga más pesada (decenas de MB) y solo
      // pasa una vez en la vida de la app.
      final sttModelReady = await InjectionContainer.isSttModelDownloaded();

      if (!sttModelReady) {
        state = state.copyWith(
          status: TranslationStatus.downloadingModels,
          isStreaming: false,
          downloadProgress: 0.0,
          downloadStepLabel: 'Modelo de voz (offline)',
          paragraphs: [],
          errorMessage: null,
        );

        await InjectionContainer.downloadSttModel(
          onProgress: (progress) {
            state = state.copyWith(downloadProgress: progress);
          },
        );
      }

      // ── Verificar / descargar modelos de ML Kit ──
      final modelsReady = await InjectionContainer.areModelsDownloaded(
        sourceLanguage,
        targetLanguage,
      );

      if (!modelsReady) {
        state = state.copyWith(
          status: TranslationStatus.downloadingModels,
          isStreaming: false,
          downloadProgress: 0.0,
          downloadLanguage: null,
          downloadStepLabel: null,
          paragraphs: [],
          errorMessage: null,
        );

        await InjectionContainer.downloadModels(
          source: sourceLanguage,
          target: targetLanguage,
          onProgress: (progress, lang) {
            state = state.copyWith(
              downloadProgress: progress,
              downloadLanguage: lang.isEmpty ? state.downloadLanguage : lang,
            );
          },
        );
      }

      state = state.copyWith(
        status: TranslationStatus.listening,
        isStreaming: true,
        downloadProgress: 0.0,
        downloadLanguage: null,
        downloadStepLabel: null,
        paragraphs: [],
        errorMessage: null,
      );

      final stream = InjectionContainer.startTranslation(
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        voiceName: voiceName,
        speed: speed,
        existingSessionId: existingSessionId,
        sessionName: sessionName,
      );

      _subscription = stream.listen(
        (chunk) {
          if (!chunk.isFinal) {
            state = state.copyWith(status: TranslationStatus.translating);
            return;
          }
          _counter++;
          state = state.copyWith(
            status: TranslationStatus.listening,
            paragraphs: [
              ...state.paragraphs,
              TranslationParagraph(
                id: 'p$_counter',
                originalText: chunk.originalText,
                translatedText: chunk.translatedText,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                timestamp: DateTime.now(),
              ),
            ],
          );
        },
        onError: (error) {
          state = state.copyWith(
            status: TranslationStatus.error,
            errorMessage: 'Error: $error',
            isStreaming: false,
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        status: TranslationStatus.error,
        errorMessage: 'Error al iniciar: $e',
        isStreaming: false,
      );
    }
  }

  void setSessionInfo(String id, String name) {
    state = state.copyWith(currentSessionId: id, sessionName: name);
  }

  void clearVisibleParagraphs() {
    if (state.paragraphs.isEmpty) return;
    state = state.copyWith(paragraphs: [], playingParagraphId: null);
  }

  Future<void> playParagraph(String paragraphId) async {
    final p = state.paragraphs.firstWhere((p) => p.id == paragraphId);
    state = state.copyWith(
      status: TranslationStatus.playing,
      playingParagraphId: paragraphId,
    );

    unawaited(
      RealTtsDatasource.instance
          .synthesize(
            text: p.translatedText,
            voiceName: _currentVoiceName,
            languageCode: _currentTargetLanguage,
            speed: _currentSpeed,
          )
          .then((_) => _afterPlay())
          .catchError((_) => _afterPlay()),
    );
  }

  void _afterPlay() {
    state = state.copyWith(
      status: state.isStreaming
          ? TranslationStatus.listening
          : TranslationStatus.idle,
      playingParagraphId: null,
    );
  }

  Future<void> stopTranslation() async {
    // Modo micrófono: solo detener passthrough
    if (state.micMode) {
      await _passthrough.stop();
      state = state.copyWith(
        status: TranslationStatus.idle,
        isStreaming: false,
      );
      return;
    }

    // Dejar el listener activo mientras el repositorio entrega, traduce y lee
    // la última frase. Mostrar estado de procesamiento, pero bloquear nueva
    // captura desde la interfaz.
    state = state.copyWith(
      status: TranslationStatus.translating,
      isStreaming: false,
      downloadProgress: 0.0,
      downloadLanguage: null,
    );

    final result = await InjectionContainer.stopTranslation();
    await _subscription?.cancel();
    _subscription = null;

    result.fold(
      (failure) => state = state.copyWith(errorMessage: failure.message),
      (session) => state = state.copyWith(
        currentSessionId: session.id,
        sessionName: session.name,
      ),
    );
    state = state.copyWith(status: TranslationStatus.idle);
  }
}

final translationProvider =
    StateNotifierProvider<TranslationNotifier, TranslationState>((ref) {
      return TranslationNotifier();
    });

final historyProvider = FutureProvider<List<TranslationSession>>((ref) async {
  final result = await InjectionContainer.getHistory();
  return result.fold((failure) => throw failure, (s) => s);
});

final deleteSessionProvider = FutureProvider.family<void, String>((
  ref,
  id,
) async {
  await InjectionContainer.deleteSession(id);
});

/// [args] es (id de la sesión, nombre nuevo).
final renameSessionProvider = FutureProvider.family<void, (String, String)>((
  ref,
  args,
) async {
  await InjectionContainer.renameSession(args.$1, args.$2);
});
