/// Result of running [TelegramConnectFlow.run].
class TelegramConnectResult {
  final String state;
  final String? message;

  const TelegramConnectResult({required this.state, this.message});
}

/// Pure, unit-testable state machine for connecting a Telegram account using Settings fields.
///
/// Never prompts in a modal dialog for Phone Number or 2FA Password — those live in Settings.
/// Only prompts the user for the dynamic Telegram OTP code.
class TelegramConnectFlow {
  static Future<TelegramConnectResult> run({
    required int apiId,
    required String apiHash,
    required String phone,
    required String password,
    required Future<Map<String, String?>> Function(int apiId, String apiHash) getAuthState,
    required Future<Map<String, String?>> Function(String phone) sendPhone,
    required Future<Map<String, String?>> Function(String code) sendCode,
    required Future<Map<String, String?>> Function(String password) sendPassword,
    required Future<String?> Function(String? errorMessage) promptOtpCode,
  }) async {
    final cleanHash = apiHash.trim();
    final cleanPhone = phone.trim();
    if (apiId <= 0 || cleanHash.isEmpty || cleanPhone.isEmpty) {
      return const TelegramConnectResult(
        state: 'unconfigured',
        message: 'Fill in Telegram API ID, API Hash, and Phone Number above first.',
      );
    }

    var res = await getAuthState(apiId, cleanHash);
    var state = res['state'] ?? 'uninitialized';
    if (state == 'ready') {
      return TelegramConnectResult(state: state);
    }
    if (res['error'] != null && res['error']!.isNotEmpty) {
      return TelegramConnectResult(state: state, message: res['error']);
    }

    if (state == 'waitPhoneNumber' || state == 'uninitialized') {
      res = await sendPhone(cleanPhone);
      state = res['state'] ?? state;
      if (res['error'] != null && res['error']!.isNotEmpty) {
        return TelegramConnectResult(state: state, message: res['error']);
      }
    }

    while (state == 'waitCode') {
      final code = await promptOtpCode(res['error']);
      if (code == null || code.trim().isEmpty) {
        return TelegramConnectResult(state: state);
      }
      res = await sendCode(code.trim());
      state = res['state'] ?? state;
      if (state == 'ready') {
        return TelegramConnectResult(state: state, message: 'Telegram connected.');
      }
      if (state != 'waitCode' && res['error'] != null && res['error']!.isNotEmpty) {
        return TelegramConnectResult(state: state, message: res['error']);
      }
    }

    if (state == 'waitPassword') {
      if (password.isEmpty) {
        return TelegramConnectResult(
          state: state,
          message:
              'Your Telegram account requires a 2FA password. Fill in Telegram 2FA Password above and tap Connect again.',
        );
      }
      res = await sendPassword(password);
      state = res['state'] ?? state;
      if (res['error'] != null && res['error']!.isNotEmpty) {
        return TelegramConnectResult(state: state, message: res['error']);
      }
    }

    return TelegramConnectResult(
      state: state,
      message: state == 'ready' ? 'Telegram connected.' : null,
    );
  }
}
