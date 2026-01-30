import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/theme.dart';
import 'providers/user_provider.dart';
import 'providers/meal_provider.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/dashboard_screen.dart';
import 'ui/screens/planner_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive for Web
  await Hive.initFlutter();
  
  // Initialize dotenv (optional, backend handles API keys now)
  try {
    await dotenv.load(fileName: "assets/env");
    print("DEBUG: Dotenv loaded. OpenAI Key present: ${dotenv.env['OPEN_AI_KEY']?.isNotEmpty}");
  } catch (e) {
    print("DEBUG: Dotenv failed to load: $e (this is OK, backend handles API keys)");
  }

  await Hive.openBox('user_prefs');
  await Hive.openBox('meals');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => MealProvider()),
      ],
      child: const NutritionApp(),
    ),
  );
}

// Router Setup
final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/planner',
      builder: (context, state) => const PlannerScreen(),
    ),
  ],
);

class NutritionApp extends StatelessWidget {
  const NutritionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Tweak My Meal',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme,
      routerConfig: _router,
    );
  }
}
