import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    await FirebaseAuth.instance.signOut();
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController();
});
