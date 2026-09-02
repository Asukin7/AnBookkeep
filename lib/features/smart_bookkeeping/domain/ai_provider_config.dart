final class AiProviderConfig {
  const AiProviderConfig({
    this.enabled = false,
    this.baseUrl = 'https://open.bigmodel.cn/api/paas/v4',
    this.apiKey = '',
    this.visionModel = 'glm-4v-flash',
    this.textModel = 'glm-4-flash',
    this.allowImageUpload = false,
    this.imageUploadConsent = false,
  });

  final bool enabled;
  final String baseUrl;
  final String apiKey;
  final String visionModel;
  final String textModel;
  final bool allowImageUpload;
  final bool imageUploadConsent;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  AiProviderConfig copyWith({
    bool? enabled,
    String? baseUrl,
    String? apiKey,
    String? visionModel,
    String? textModel,
    bool? allowImageUpload,
    bool? imageUploadConsent,
  }) {
    return AiProviderConfig(
      enabled: enabled ?? this.enabled,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      visionModel: visionModel ?? this.visionModel,
      textModel: textModel ?? this.textModel,
      allowImageUpload: allowImageUpload ?? this.allowImageUpload,
      imageUploadConsent: imageUploadConsent ?? this.imageUploadConsent,
    );
  }
}
