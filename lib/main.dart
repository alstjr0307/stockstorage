import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'providers/auth_provider.dart';
import 'screens/home_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text('Firebase 초기화 오류: $e')))));
    return;
  }
  timeago.setLocaleMessages('ko', timeago.KoMessages());
  runApp(const StockStorageApp());
}

class StockStorageApp extends StatelessWidget {
  const StockStorageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        title: 'StockStorage',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A0E1A),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF4ADE80),
            surface: Color(0xFF1A2035),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
