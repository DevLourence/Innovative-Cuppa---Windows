import 'package:flutter/material.dart';
import 'landing_page.dart' show LoginPage;
import 'dashboard.dart';
import 'data/app_data.dart';
import 'services/persistence_service.dart';
import 'services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🔇 SILENCE PATCH: Intercept and discard harmless cloud-sync/platform noise on Windows
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    // Skip harmless plugin-level or platform-specific noise on Windows desktop builds
    final msg = details.exception.toString();
    if (msg.contains('app_links') || 
        msg.contains('accessibility_plugin') || 
        msg.contains('RawKeyDownEvent') || 
        msg.contains('keysPressed.isNotEmpty')) {
      return;
    }
    originalOnError?.call(details);
  };

  await PersistenceService.loadState();
  
  await Supabase.initialize(
    url: 'https://lkeohgoekdvfyqilqfzq.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxrZW9oZ29la2R2ZnlxaWxxZnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzMjM4ODAsImV4cCI6MjA4ODg5OTg4MH0.AyPQTUIJamW4UDO3oxKd1-akia_WE3ARF2Pc38wA2Xg',
  );

  await SupabaseService.init();
  await SupabaseService.pullFromCloud(); // Await hydration for initial data
  
  runApp(const InnovativeCuppaApp());
}

class InnovativeCuppaApp extends StatelessWidget {
  const InnovativeCuppaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppData.darkModeNotifier,
      builder: (context, isDark, child) {
        return MaterialApp(
          title: 'Innovative Cuppa',
          debugShowCheckedModeBanner: false,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1C1008),
              primary: const Color(0xFF1C1008),
              secondary: const Color(0xFFC8822A),
              surface: const Color(0xFFFAF9F6),
              onSurface: const Color(0xFF1C1008),
              surfaceContainerHighest: const Color(0xFFF0EDE8),
            ),
            fontFamily: 'Segoe UI',
            scaffoldBackgroundColor: const Color(0xFFF9F8F6),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0xFFF0EDE8), width: 1),
              ),
              color: Colors.white,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(color: Color(0xFF1C1008), fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1C1008),
              brightness: Brightness.dark,
              primary: const Color(0xFFE5DED5),
              secondary: const Color(0xFFC8822A),
              surface: const Color(0xFF1C1C1C),
              onSurface: const Color(0xFFF5F3F0),
            ),
            fontFamily: 'Segoe UI',
            scaffoldBackgroundColor: const Color(0xFF121110),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1),
              ),
              color: const Color(0xFF1E1E1E),
            ),
          ),
          home: const AppNavigator(),
        );
      },
    );
  }
}

class AppNavigator extends StatefulWidget {
  const AppNavigator({super.key});

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator> {
  Map<String, dynamic>? _loggedInUser;

  @override
  Widget build(BuildContext context) {
    if (_loggedInUser != null) {
      return DashboardPage(
        user: _loggedInUser!,
        onLogout: () => setState(() => _loggedInUser = null),
      );
    }
    return LoginPage(
      onLogin: (user) => setState(() => _loggedInUser = user),
    );
  }
}
