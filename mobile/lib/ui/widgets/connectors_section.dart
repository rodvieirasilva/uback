import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config/app_config.dart';
import '../../core/testing/test_keys.dart';
import 'settings_components.dart';

/// Modular Connectors section for WhatsApp and Telegram credentials, connection, and tests.
class ConnectorsSection extends StatelessWidget {
  final TextEditingController whatsappKeyCtrl;
  final VoidCallback onTestWhatsapp;
  final TextEditingController telegramApiIdCtrl;
  final TextEditingController telegramApiHashCtrl;
  final TextEditingController telegramPasswordCtrl;
  final String telegramAuthState;
  final VoidCallback onConnectTelegram;
  final VoidCallback onTestTelegram;
  final VoidCallback onDisconnectTelegram;

  const ConnectorsSection({
    super.key,
    required this.whatsappKeyCtrl,
    required this.onTestWhatsapp,
    required this.telegramApiIdCtrl,
    required this.telegramApiHashCtrl,
    required this.telegramPasswordCtrl,
    required this.telegramAuthState,
    required this.onConnectTelegram,
    required this.onTestTelegram,
    required this.onDisconnectTelegram,
  });

  @override
  Widget build(BuildContext context) {
    final isTelegramConnected = telegramAuthState == 'ready';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const SettingsSectionHeader(title: 'WHATSAPP'),
        const SizedBox(height: 10),
        SecretTextField(
          testId: AppTestKeys.settingsWhatsappKeyId,
          fieldKey: AppTestKeys.settingsWhatsappKey,
          controller: whatsappKeyCtrl,
          labelText: 'WhatsApp 64-Digit Backup Key (optional)',
          helperText: 'Used locally to export incremental SQLite chat deltas (.db) from .crypt15',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: withTestId(
            AppTestKeys.settingsTestWhatsappId,
            child: OutlinedButton.icon(
              key: AppTestKeys.settingsTestWhatsapp,
              onPressed: onTestWhatsapp,
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('Test WhatsApp'),
            ),
          ),
        ),
        if (CompileTimeDefaults.enableTelegram) ...[
          const SizedBox(height: 18),
          const SettingsSectionHeader(title: 'TELEGRAM'),
          const SizedBox(height: 10),
          withTestId(
            AppTestKeys.settingsTelegramApiIdId,
            child: TextField(
              key: AppTestKeys.settingsTelegramApiId,
              controller: telegramApiIdCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Telegram API ID (optional)',
                helperText: 'From https://my.telegram.org (Client API)',
              ),
            ),
          ),
          const SizedBox(height: 12),
          SecretTextField(
            testId: AppTestKeys.settingsTelegramApiHashId,
            fieldKey: AppTestKeys.settingsTelegramApiHash,
            controller: telegramApiHashCtrl,
            labelText: 'Telegram API Hash (optional)',
          ),
          const SizedBox(height: 12),
          SecretTextField(
            testId: AppTestKeys.settingsTelegramPasswordId,
            fieldKey: AppTestKeys.settingsTelegramPassword,
            controller: telegramPasswordCtrl,
            labelText: 'Telegram 2FA Password (optional)',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Telegram Account: $telegramAuthState',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (isTelegramConnected) ...[
                withTestId(
                  AppTestKeys.settingsTestTelegramId,
                  child: OutlinedButton(
                    key: AppTestKeys.settingsTestTelegram,
                    onPressed: onTestTelegram,
                    child: const Text('Test Telegram'),
                  ),
                ),
                TextButton(
                  onPressed: onDisconnectTelegram,
                  child: const Text('Disconnect'),
                ),
              ] else
                withTestId(
                  AppTestKeys.settingsConnectTelegramId,
                  child: FilledButton.tonal(
                    key: AppTestKeys.settingsConnectTelegram,
                    onPressed: onConnectTelegram,
                    child: const Text('Connect Telegram'),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
