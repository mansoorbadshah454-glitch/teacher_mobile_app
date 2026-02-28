import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teacher_mobile_app/features/notebook/services/notebook_storage_service.dart';

// Stream of user changes (auth state changes)
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

// Provides the current user (if logged in)
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  return authState.value;
});

class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController() : super(const AsyncValue.data(null));

  Future<void> signIn(String email, String password) async {
    print('AuthProvider: signIn called with email: $email'); // LOG
    state = const AsyncValue.loading();
    try {
      print('AuthProvider: Calling FirebaseAuth.signInWithEmailAndPassword...'); // LOG
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      print('AuthProvider: FirebaseAuth.signInWithEmailAndPassword success.'); // LOG
      state = const AsyncValue.data(null);
    } catch (e, st) {
      print('AuthProvider: FirebaseAuth.signInWithEmailAndPassword FAILED: $e'); // LOG
      print('AuthProvider: StackTrace: $st'); // LOG
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signOut() async {
    try {
      print('AuthProvider: Starting full data purge on sign-out...');
      
      // 1. Nuke SharedPreferences (Duty status, cached strings, etc)
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // 2. Nuke Local SQLite Notebook Database
      await NotebookStorageService().clearAll();

      print('AuthProvider: Local data purge complete.');
    } catch (e) {
      print('AuthProvider: Error during local purge: $e');
    } finally {
      // 3. Guarantee Firebase Auth signed out
      await FirebaseAuth.instance.signOut();
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController();
});
