import 'package:equatable/equatable.dart';

/// Tipo de voz para la síntesis de audio de salida.
class VoiceActor extends Equatable {
  final String name;
  final String displayName;
  final String languageCode;
  final VoiceGender gender;
  final String? ssmlGender;

  const VoiceActor({
    required this.name,
    required this.displayName,
    required this.languageCode,
    required this.gender,
    this.ssmlGender,
  });

  @override
  List<Object?> get props => [name, displayName, languageCode, gender];

  static List<VoiceActor> forLanguage(String languageCode) {
    return _allVoices.where((v) => v.languageCode == languageCode).toList();
  }

  static const List<VoiceActor> _allVoices = [
    // ── Español ──
    VoiceActor(name: 'es-ES-Standard-A', displayName: 'Estándar (Mujer)', languageCode: 'es', gender: VoiceGender.female, ssmlGender: 'FEMALE'),
    VoiceActor(name: 'es-ES-Wavenet-B', displayName: 'WaveNet (Hombre)', languageCode: 'es', gender: VoiceGender.male, ssmlGender: 'MALE'),

    // ── Inglés ──
    VoiceActor(name: 'en-US-Standard-C', displayName: 'Estándar (Mujer)', languageCode: 'en', gender: VoiceGender.female, ssmlGender: 'FEMALE'),
    VoiceActor(name: 'en-US-Wavenet-D', displayName: 'WaveNet (Hombre)', languageCode: 'en', gender: VoiceGender.male, ssmlGender: 'MALE'),

    // ── Portugués ──
    VoiceActor(name: 'pt-BR-Wavenet-A', displayName: 'WaveNet (Mujer)', languageCode: 'pt', gender: VoiceGender.female, ssmlGender: 'FEMALE'),
    VoiceActor(name: 'pt-BR-Wavenet-B', displayName: 'WaveNet (Hombre)', languageCode: 'pt', gender: VoiceGender.male, ssmlGender: 'MALE'),

    // ── Francés ──
    VoiceActor(name: 'fr-FR-Standard-A', displayName: 'Estándar (Mujer)', languageCode: 'fr', gender: VoiceGender.female, ssmlGender: 'FEMALE'),
    VoiceActor(name: 'fr-FR-Standard-B', displayName: 'Estándar (Hombre)', languageCode: 'fr', gender: VoiceGender.male, ssmlGender: 'MALE'),

    // ── Alemán ──
    VoiceActor(name: 'de-DE-Wavenet-A', displayName: 'WaveNet (Mujer)', languageCode: 'de', gender: VoiceGender.female, ssmlGender: 'FEMALE'),
    VoiceActor(name: 'de-DE-Wavenet-B', displayName: 'WaveNet (Hombre)', languageCode: 'de', gender: VoiceGender.male, ssmlGender: 'MALE'),

    // ── Italiano ──
    VoiceActor(name: 'it-IT-Standard-A', displayName: 'Estándar (Mujer)', languageCode: 'it', gender: VoiceGender.female, ssmlGender: 'FEMALE'),
    VoiceActor(name: 'it-IT-Standard-B', displayName: 'Estándar (Hombre)', languageCode: 'it', gender: VoiceGender.male, ssmlGender: 'MALE'),

    // ── Japonés ──
    VoiceActor(name: 'ja-JP-Standard-A', displayName: 'Estándar (Mujer)', languageCode: 'ja', gender: VoiceGender.female, ssmlGender: 'FEMALE'),
    VoiceActor(name: 'ja-JP-Standard-B', displayName: 'Estándar (Hombre)', languageCode: 'ja', gender: VoiceGender.male, ssmlGender: 'MALE'),

    // ── Chino ──
    VoiceActor(name: 'zh-CN-Wavenet-A', displayName: 'WaveNet (Mujer)', languageCode: 'zh', gender: VoiceGender.female, ssmlGender: 'FEMALE'),
    VoiceActor(name: 'zh-CN-Standard-B', displayName: 'Estándar (Hombre)', languageCode: 'zh', gender: VoiceGender.male, ssmlGender: 'MALE'),

    // ── Coreano ──
    VoiceActor(name: 'ko-KR-Wavenet-A', displayName: 'WaveNet (Mujer)', languageCode: 'ko', gender: VoiceGender.female, ssmlGender: 'FEMALE'),
    VoiceActor(name: 'ko-KR-Wavenet-B', displayName: 'WaveNet (Hombre)', languageCode: 'ko', gender: VoiceGender.male, ssmlGender: 'MALE'),

    // ── Ruso ──
    VoiceActor(name: 'ru-RU-Standard-A', displayName: 'Estándar (Mujer)', languageCode: 'ru', gender: VoiceGender.female, ssmlGender: 'FEMALE'),
    VoiceActor(name: 'ru-RU-Standard-B', displayName: 'Estándar (Hombre)', languageCode: 'ru', gender: VoiceGender.male, ssmlGender: 'MALE'),

    // ── Árabe ──
    VoiceActor(name: 'ar-XA-Standard-A', displayName: 'Estándar (Mujer)', languageCode: 'ar', gender: VoiceGender.female, ssmlGender: 'FEMALE'),
    VoiceActor(name: 'ar-XA-Standard-B', displayName: 'Estándar (Hombre)', languageCode: 'ar', gender: VoiceGender.male, ssmlGender: 'MALE'),

    // ── Neerlandés ──
    VoiceActor(name: 'nl-NL-Standard-A', displayName: 'Estándar (Mujer)', languageCode: 'nl', gender: VoiceGender.female, ssmlGender: 'FEMALE'),
    VoiceActor(name: 'nl-NL-Standard-B', displayName: 'Estándar (Hombre)', languageCode: 'nl', gender: VoiceGender.male, ssmlGender: 'MALE'),
  ];
}

enum VoiceGender { male, female, other }
