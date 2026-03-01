class AppConfig {
  // Change this to your laptop's IP for physical device testing
  // Use 10.0.2.2 for Android emulator
  static const String backendUrl = 'http://192.168.29.201:8000';

  // Colors
  static const int colorBlack = 0xFF000000;
  static const int colorWhite = 0xFFFFFFFF;
  static const int colorGray = 0xFF999999;
  static const int colorCardBg = 0xFF1A1A1A;
  static const int colorCardBorder = 0xFF2A2A2A;
  static const int colorEdgeGlow = 0xFF818CF8;
  static const int colorError = 0xFFF87171;

  // Ring animation
  static const double ringIdleBreathCycleSec = 3.0;
  static const double ringIdleRotationSec = 12.0;
  static const double ringListeningBreathCycleSec = 1.5;
  static const double ringProcessingRotationSec = 3.0;
  static const double ringMorphDurationMs = 800;
  static const double ringBreathAmplitude = 0.03; // 3%
  static const double ringRadiusVariation = 0.05; // 5%

  // Dot properties
  static const double dotMinSize = 2.0;
  static const double dotMaxSize = 5.0;
  static const double dotMinOpacity = 0.05;
  static const double dotMaxOpacity = 1.0;
  static const double ringBandWidth = 30.0;
}
