import 'package:material_ui/material_ui.dart';

import 'core/backup/backup_controller.dart';
import 'core/backup/native_bridge.dart';
import 'core/config/app_config.dart';
import 'ui/home_screen.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UBackApp());
}

class UBackApp extends StatefulWidget {
  final BackupController? controller;

  const UBackApp({super.key, this.controller});

  @override
  State<UBackApp> createState() => _UBackAppState();
}

class _UBackAppState extends State<UBackApp> {
  late final BackupController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = BackupController(
        settingsRepo: AppSettingsRepository(),
        bridge: MethodChannelNativeBridge(),
      );
      _ownsController = true;
      _controller.init();
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UBack',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: HomeScreen(controller: _controller),
    );
  }
}
