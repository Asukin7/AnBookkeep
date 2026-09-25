/// Marks a domain exception whose message is safe to show directly to users.
abstract interface class UserFacingException implements Exception {
  String get message;
}

/// A validation failure intentionally safe to present in the interface.
final class AppValidationException implements UserFacingException {
  const AppValidationException(this.message);

  @override
  final String message;

  @override
  String toString() => message;
}

/// Converts known validation/domain errors to UI text without exposing paths,
/// SQL details, network internals or stack information.
String appErrorMessage(Object error, {required String fallback}) {
  final Object? value = switch (error) {
    UserFacingException exception => exception.message,
    _ => null,
  };
  final message = value?.toString().trim();
  return message == null || message.isEmpty ? fallback : message;
}
