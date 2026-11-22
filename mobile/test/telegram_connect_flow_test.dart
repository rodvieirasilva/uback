import 'package:flutter_test/flutter_test.dart';
import 'package:uback/core/backup/telegram_connect_flow.dart';

void main() {
  test('warns without prompting when API ID, API Hash, or Phone Number is missing', () async {
    var prompted = false;
    final res = await TelegramConnectFlow.run(
      apiId: 12345,
      apiHash: 'hash',
      phone: '',
      password: '',
      getAuthState: (_, _) async => {'state': 'waitPhoneNumber'},
      sendPhone: (_) async => {'state': 'waitCode'},
      sendCode: (_) async => {'state': 'ready'},
      sendPassword: (_) async => {'state': 'ready'},
      promptOtpCode: (_) async {
        prompted = true;
        return '12345';
      },
    );

    expect(prompted, isFalse);
    expect(res.state, 'unconfigured');
    expect(res.message, contains('Fill in Telegram API ID, API Hash, and Phone Number'));
  });

  test('auto-submits phone & 2FA password from Settings and prompts ONLY for OTP code', () async {
    String? sentPhone;
    String? sentCode;
    String? sentPassword;
    var otpPrompts = 0;

    final res = await TelegramConnectFlow.run(
      apiId: 12345,
      apiHash: 'hash',
      phone: '+5511999999999',
      password: 'my2faPassword',
      getAuthState: (_, _) async => {'state': 'waitPhoneNumber'},
      sendPhone: (p) async {
        sentPhone = p;
        return {'state': 'waitCode'};
      },
      sendCode: (c) async {
        sentCode = c;
        return {'state': 'waitPassword'};
      },
      sendPassword: (pw) async {
        sentPassword = pw;
        return {'state': 'ready'};
      },
      promptOtpCode: (_) async {
        otpPrompts++;
        return '98765';
      },
    );

    expect(sentPhone, '+5511999999999');
    expect(sentCode, '98765');
    expect(sentPassword, 'my2faPassword');
    expect(otpPrompts, 1);
    expect(res.state, 'ready');
    expect(res.message, 'Telegram connected.');
  });

  test('connects directly without 2FA when account has no 2FA enabled', () async {
    var passwordSent = false;
    final res = await TelegramConnectFlow.run(
      apiId: 12345,
      apiHash: 'hash',
      phone: '+5511999999999',
      password: '',
      getAuthState: (_, _) async => {'state': 'waitPhoneNumber'},
      sendPhone: (_) async => {'state': 'waitCode'},
      sendCode: (_) async => {'state': 'ready'},
      sendPassword: (_) async {
        passwordSent = true;
        return {'state': 'ready'};
      },
      promptOtpCode: (_) async => '54321',
    );

    expect(passwordSent, isFalse);
    expect(res.state, 'ready');
  });

  test('warns to fill Settings 2FA field instead of prompting when 2FA is required but empty',
      () async {
    var passwordSent = false;
    final res = await TelegramConnectFlow.run(
      apiId: 12345,
      apiHash: 'hash',
      phone: '+5511999999999',
      password: '',
      getAuthState: (_, _) async => {'state': 'waitPhoneNumber'},
      sendPhone: (_) async => {'state': 'waitCode'},
      sendCode: (_) async => {'state': 'waitPassword'},
      sendPassword: (_) async {
        passwordSent = true;
        return {'state': 'ready'};
      },
      promptOtpCode: (_) async => '11111',
    );

    expect(passwordSent, isFalse);
    expect(res.state, 'waitPassword');
    expect(res.message, contains('Fill in Telegram 2FA Password above'));
  });

  test('surfaces error message when configured 2FA password is wrong', () async {
    final res = await TelegramConnectFlow.run(
      apiId: 12345,
      apiHash: 'hash',
      phone: '+5511999999999',
      password: 'wrong',
      getAuthState: (_, _) async => {'state': 'waitPassword'},
      sendPhone: (_) async => {'state': 'waitCode'},
      sendCode: (_) async => {'state': 'waitPassword'},
      sendPassword: (_) async => {'state': 'waitPassword', 'error': 'PASSWORD_HASH_INVALID'},
      promptOtpCode: (_) async => null,
    );

    expect(res.state, 'waitPassword');
    expect(res.message, 'PASSWORD_HASH_INVALID');
  });

  test('returns immediately when session is already ready', () async {
    var otpPrompts = 0;
    final res = await TelegramConnectFlow.run(
      apiId: 12345,
      apiHash: 'hash',
      phone: '+5511999999999',
      password: '',
      getAuthState: (_, _) async => {'state': 'ready'},
      sendPhone: (_) async => {'state': 'ready'},
      sendCode: (_) async => {'state': 'ready'},
      sendPassword: (_) async => {'state': 'ready'},
      promptOtpCode: (_) async {
        otpPrompts++;
        return null;
      },
    );

    expect(otpPrompts, 0);
    expect(res.state, 'ready');
  });
}
