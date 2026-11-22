import 'package:material_ui/material_ui.dart';

import '../../core/testing/test_keys.dart';

/// Shared horizontal divider between logical Settings sections.
class SettingsSectionDivider extends StatelessWidget {
  const SettingsSectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Divider(height: 1),
    );
  }
}

/// Shared uppercase primary-colored section header for Settings screens, with optional trailing widget.
class SettingsSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SettingsSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.1,
          ),
    );
    if (trailing == null) return text;
    return Row(
      children: [
        Expanded(child: text),
        trailing!,
      ],
    );
  }
}

/// Shared obscured TextField with built-in show/hide visibility toggle and testId semantics.
class SecretTextField extends StatefulWidget {
  final String testId;
  final ValueKey<String> fieldKey;
  final TextEditingController controller;
  final String labelText;
  final String? helperText;

  const SecretTextField({
    super.key,
    required this.testId,
    required this.fieldKey,
    required this.controller,
    required this.labelText,
    this.helperText,
  });

  @override
  State<SecretTextField> createState() => _SecretTextFieldState();
}

class _SecretTextFieldState extends State<SecretTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return withTestId(
      widget.testId,
      child: TextField(
        key: widget.fieldKey,
        controller: widget.controller,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: widget.labelText,
          helperText: widget.helperText,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
    );
  }
}
