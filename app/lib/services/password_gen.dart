import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zxcvbn/zxcvbn.dart';

import '../bridge/api.dart' as bridge;

class PasswordGenerationOptions {
  final int length;
  final bool uppercase;
  final bool lowercase;
  final bool numbers;
  final bool symbols;
  final bool excludeAmbiguous;

  const PasswordGenerationOptions({
    this.length = 20,
    this.uppercase = true,
    this.lowercase = true,
    this.numbers = true,
    this.symbols = true,
    this.excludeAmbiguous = false,
  });

  void validate() {
    if (length < 8 || length > 64) {
      throw ArgumentError.value(length, 'length', 'must be between 8 and 64');
    }
    if (!uppercase && !lowercase && !numbers && !symbols) {
      throw ArgumentError.value(
        this,
        'options',
        'enable at least one character set',
      );
    }
  }

  bridge.GenOptions toBridge() => bridge.GenOptions(
    length: length,
    uppercase: uppercase,
    lowercase: lowercase,
    numbers: numbers,
    symbols: symbols,
    excludeAmbiguous: excludeAmbiguous,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PasswordGenerationOptions &&
          runtimeType == other.runtimeType &&
          length == other.length &&
          uppercase == other.uppercase &&
          lowercase == other.lowercase &&
          numbers == other.numbers &&
          symbols == other.symbols &&
          excludeAmbiguous == other.excludeAmbiguous;

  @override
  int get hashCode =>
      length.hashCode ^
      uppercase.hashCode ^
      lowercase.hashCode ^
      numbers.hashCode ^
      symbols.hashCode ^
      excludeAmbiguous.hashCode;
}

class PasswordStrength {
  final int score;
  final String crackTimeDisplay;

  const PasswordStrength({required this.score, required this.crackTimeDisplay});
}

abstract interface class PasswordGeneratorBackend {
  Future<String> generatePassword(PasswordGenerationOptions options);

  Future<String> generatePassphrase({
    required int words,
    required String separator,
  });
}

class FrbPasswordGeneratorBackend implements PasswordGeneratorBackend {
  const FrbPasswordGeneratorBackend();

  @override
  Future<String> generatePassword(PasswordGenerationOptions options) =>
      bridge.generatePassword(opts: options.toBridge());

  @override
  Future<String> generatePassphrase({
    required int words,
    required String separator,
  }) => bridge.generatePassphrase(words: words, sep: separator);
}

final passwordGeneratorBackendProvider = Provider<PasswordGeneratorBackend>(
  (ref) => const FrbPasswordGeneratorBackend(),
);

final passwordGeneratorServiceProvider = Provider<PasswordGeneratorService>(
  (ref) => PasswordGeneratorService(
    backend: ref.watch(passwordGeneratorBackendProvider),
  ),
);

class PasswordGeneratorService {
  final PasswordGeneratorBackend backend;
  final Zxcvbn _zxcvbn;

  PasswordGeneratorService({required this.backend, Zxcvbn? zxcvbn})
    : _zxcvbn = zxcvbn ?? Zxcvbn();

  Future<String> generatePassword([
    PasswordGenerationOptions options = const PasswordGenerationOptions(),
  ]) {
    options.validate();
    return backend.generatePassword(options);
  }

  Future<String> generatePassphrase({int words = 4, String separator = ' '}) {
    if (words < 4 || words > 6) {
      throw ArgumentError.value(words, 'words', 'must be between 4 and 6');
    }
    return backend.generatePassphrase(words: words, separator: separator);
  }

  PasswordStrength evaluateStrength(String password) {
    final result = _zxcvbn.evaluate(password);
    final display = result.crack_times_display;
    return PasswordStrength(
      score: (result.score ?? 0).round(),
      crackTimeDisplay:
          display?['offline_slow_hashing_1e4_per_second'] ??
          (display == null || display.isEmpty ? '' : display.values.first),
    );
  }
}
