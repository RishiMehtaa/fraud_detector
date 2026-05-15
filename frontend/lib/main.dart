import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/dashboard_page.dart';
import 'pages/network_graph_page.dart';
import 'pages/alert_queue_page.dart';
import 'pages/investigation_page.dart';
import 'pages/fund_flow_trace_page.dart';
import 'pages/chatbot_page.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => _AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
        GoRoute(path: '/graph', builder: (_, __) => const NetworkGraphPage()),
        GoRoute(path: '/alerts', builder: (_, __) => const AlertQueuePage()),
        GoRoute(path: '/trace', builder: (_, __) => const FundFlowTracePage()),
        GoRoute(path: '/chat', builder: (_, __) => const ChatbotPage()),
      ],
    ),
    GoRoute(
      path: '/investigation/:id',
      builder: (_, state) =>
          InvestigationPage(accountId: state.pathParameters['id']!),
    ),
  ],
);

void main() {
  runApp(const ProviderScope(child: FraudApp()));
}

class FraudApp extends StatelessWidget {
  const FraudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Fraud Detection System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF111827),
        cardTheme: const CardThemeData(
          color: Color(0xFF1F2937),
          surfaceTintColor: Colors.transparent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111827),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xFF0F172A),
          indicatorColor: Color(0xFF1E3A5F),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF1F2937),
        ),
      ),
      routerConfig: _router,
    );
  }
}

class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  static const _routes = [
    ('/', Icons.dashboard_outlined, Icons.dashboard, 'Overview'),
    ('/graph', Icons.hub_outlined, Icons.hub, 'Network'),
    ('/alerts', Icons.notifications_outlined, Icons.notifications, 'Alerts'),
    ('/trace', Icons.route_outlined, Icons.route, 'Trace'),
    ('/chat', Icons.chat_bubble_outline, Icons.chat_bubble, 'Chatbot'),
  ];

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location == '/') return 0;
    for (int i = 1; i < _routes.length; i++) {
      if (location.startsWith(_routes[i].$1)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _selectedIndex(context);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: idx,
            extended: false,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.shield, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            destinations: _routes
                .map((r) => NavigationRailDestination(
                      icon: Icon(r.$2),
                      selectedIcon: Icon(r.$3),
                      label: Text(r.$4,
                          style: const TextStyle(fontSize: 11)),
                    ))
                .toList(),
            onDestinationSelected: (i) => context.go(_routes[i].$1),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}