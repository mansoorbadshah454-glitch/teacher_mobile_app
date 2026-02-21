import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/go_router_refresh_stream.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/features/auth/login_screen.dart';
import 'package:teacher_mobile_app/features/dashboard/dashboard_screen.dart';
import 'package:teacher_mobile_app/features/notebook/screens/notebook_screen.dart';
import 'package:teacher_mobile_app/features/notebook/screens/note_editor_screen.dart';
import 'package:teacher_mobile_app/features/notebook/models/note_model.dart';

final goRouterProvider = Provider<GoRouter>((ref) {

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    // Use a RefreshStream to listen to auth state changes
    refreshListenable: GoRouterRefreshStream(ref.watch(authStateChangesProvider.stream)),
    
    redirect: (context, state) {
      final isLoggedIn = ref.read(currentUserProvider) != null;
      final isLoggingIn = state.matchedLocation == '/login';

      if (!isLoggedIn && !isLoggingIn) {
        return '/login';
      }

      if (isLoggedIn && isLoggingIn) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
        routes: [
          // Nested routes for features
        ],
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/notebook',
        name: 'notebook',
        builder: (context, state) => const NotebookScreen(),
        routes: [
          GoRoute(
            path: 'editor',
            name: 'notebook_editor',
            builder: (context, state) {
              final note = state.extra as Note?;
              return NoteEditorScreen(note: note);
            },
          ),
        ],
      ),
    ],
  );
});
