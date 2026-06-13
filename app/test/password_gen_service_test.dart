import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/services/password_gen.dart';

class _FakePasswordGeneratorBackend implements PasswordGeneratorBackend {
  PasswordGenerationOptions? passwordOptions;
  int? passphraseWords;
  String? passphraseSeparator;

  @override
  Future<String> generatePassword(PasswordGenerationOptions options) async {
    passwordOptions = options;
    return 'Abcd1234!Generated';
  }

  @override
  Future<String> generatePassphrase({
    required int words,
    required String separator,
  }) async {
    passphraseWords = words;
    passphraseSeparator = separator;
    return List.filled(words, 'amber').join(separator);
  }
}

void main() {
  group('PasswordGeneratorService', () {
    test('uses PDR defaults for generated passwords', () async {
      final backend = _FakePasswordGeneratorBackend();
      final service = PasswordGeneratorService(backend: backend);

      final password = await service.generatePassword();

      expect(password, 'Abcd1234!Generated');
      expect(backend.passwordOptions, const PasswordGenerationOptions());
      expect(backend.passwordOptions!.length, 20);
      expect(backend.passwordOptions!.uppercase, isTrue);
      expect(backend.passwordOptions!.lowercase, isTrue);
      expect(backend.passwordOptions!.numbers, isTrue);
      expect(backend.passwordOptions!.symbols, isTrue);
      expect(backend.passwordOptions!.excludeAmbiguous, isFalse);
    });

    test('rejects invalid password options before calling backend', () async {
      final backend = _FakePasswordGeneratorBackend();
      final service = PasswordGeneratorService(backend: backend);

      expect(
        () => service.generatePassword(
          const PasswordGenerationOptions(length: 7),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(backend.passwordOptions, isNull);

      expect(
        () => service.generatePassword(
          const PasswordGenerationOptions(
            uppercase: false,
            lowercase: false,
            numbers: false,
            symbols: false,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('generates passphrases with default and custom separators', () async {
      final backend = _FakePasswordGeneratorBackend();
      final service = PasswordGeneratorService(backend: backend);

      expect(await service.generatePassphrase(), 'amber amber amber amber');
      expect(backend.passphraseWords, 4);
      expect(backend.passphraseSeparator, ' ');

      expect(
        await service.generatePassphrase(words: 6, separator: '-'),
        'amber-amber-amber-amber-amber-amber',
      );
      expect(backend.passphraseWords, 6);
      expect(backend.passphraseSeparator, '-');
    });

    test(
      'rejects invalid passphrase word counts before calling backend',
      () async {
        final backend = _FakePasswordGeneratorBackend();
        final service = PasswordGeneratorService(backend: backend);

        expect(
          () => service.generatePassphrase(words: 3),
          throwsA(isA<ArgumentError>()),
        );
        expect(backend.passphraseWords, isNull);
      },
    );

    test('evaluates password strength with zxcvbn score', () {
      final service = PasswordGeneratorService(
        backend: _FakePasswordGeneratorBackend(),
      );

      final weak = service.evaluateStrength('password');
      final strong = service.evaluateStrength(
        'correct horse battery staple 42!',
      );

      expect(weak.score, lessThan(strong.score));
      expect(strong.crackTimeDisplay, isNotEmpty);
    });
  });
}
