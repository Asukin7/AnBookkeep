import 'dart:io';

final class LanBackupSettings {
  const LanBackupSettings({
    this.enabled = false,
    this.key = '',
    this.fileName = '',
    this.directAddress = '',
  });

  static final _invalid = RegExp(r'[\x00-\x1f<>:"/\\|?*]');
  static final _reserved = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\..*)?$',
    caseSensitive: false,
  );
  static final _endpoint = RegExp(
    r'^(?:([0-9.]+)|\[([0-9A-Fa-f:.]+)\]):([0-9]{1,5})$',
  );
  static final _connectionKey = RegExp(
    r'^([A-Za-z0-9_-]{43})\.([A-Za-z0-9_-]{2,})$',
  );

  final bool enabled;
  final String key;
  final String fileName;
  final String directAddress;

  bool get canBackUp =>
      enabled &&
      connectionKey != null &&
      validName(fileName) &&
      (directAddress.trim().isEmpty || directEndpoint != null);

  ({String fingerprint, String encodedKey})? get connectionKey {
    final match = _connectionKey.firstMatch(key);
    if (match == null) return null;
    final encodedKey = match[2]!;
    if (encodedKey.length % 4 == 1) return null;
    return (fingerprint: match[1]!, encodedKey: encodedKey);
  }

  ({InternetAddress address, int port})? get directEndpoint {
    final match = _endpoint.firstMatch(directAddress.trim());
    if (match == null) return null;
    final ipv6 = match[2];
    final address = InternetAddress.tryParse(ipv6 ?? match[1]!);
    final port = int.parse(match[3]!);
    if (address == null ||
        (address.type == InternetAddressType.IPv6) != (ipv6 != null) ||
        port == 0 ||
        port > 65535) {
      return null;
    }
    return (address: address, port: port);
  }

  static bool validName(String name) =>
      name.trim().isNotEmpty &&
      !name.endsWith('.') &&
      !name.endsWith(' ') &&
      !name.toLowerCase().endsWith('.xlsx') &&
      !_invalid.hasMatch(name) &&
      !_reserved.hasMatch(name);

  @override
  bool operator ==(Object other) =>
      other is LanBackupSettings &&
      other.enabled == enabled &&
      other.key == key &&
      other.fileName == fileName &&
      other.directAddress == directAddress;

  @override
  int get hashCode => Object.hash(enabled, key, fileName, directAddress);
}
