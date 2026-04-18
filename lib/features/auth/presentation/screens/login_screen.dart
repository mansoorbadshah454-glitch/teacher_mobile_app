import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _schoolIdController = TextEditingController(); // New School ID controller
  final _formKey = GlobalKey<FormState>();
  bool _isPasswordObscured = true;
  
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final LocalAuthentication auth = LocalAuthentication();
  bool _hasSavedCredentials = false;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final savedEmail = await _storage.read(key: 'saved_email');
    final savedPassword = await _storage.read(key: 'saved_password');
    final savedSchoolId = await _storage.read(key: 'saved_school_id');

    if (savedEmail != null && savedPassword != null && savedSchoolId != null) {
      if (mounted) {
        setState(() {
          _emailController.text = savedEmail;
          _passwordController.text = savedPassword;
          _schoolIdController.text = savedSchoolId;
          _hasSavedCredentials = true;
        });
      }
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    bool authenticated = false;
    try {
      if (mounted) {
        setState(() {
          _isAuthenticating = true;
        });
      }
      authenticated = await auth.authenticate(
        localizedReason: 'Please confirm your identity to login',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allows pattern/pin if biometrics fail/missing
        ),
      );
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
    } on PlatformException catch (e) {
      print("Local Auth Error: $e");
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
      return;
    }
    
    if (!mounted) return;

    if (authenticated) {
      _submit();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _schoolIdController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      print('LoginScreen: Submit button pressed. Email: ${_emailController.text.trim()}, SchoolID: ${_schoolIdController.text.trim()}'); 
      
      FocusScope.of(context).unfocus();

      try {
        // Ensure clean state before signing in
        await ref.read(authControllerProvider.notifier).signOut();

        await ref.read(authControllerProvider.notifier).signIn(
              _emailController.text.trim(),
              _passwordController.text.trim(),
            );
        
        print('LoginScreen: SignIn call completed.'); 
        
        // Save credentials upon successful sign-in securely
        await _storage.write(key: 'saved_email', value: _emailController.text.trim());
        await _storage.write(key: 'saved_password', value: _passwordController.text.trim());
        await _storage.write(key: 'saved_school_id', value: _schoolIdController.text.trim());
        
        // Navigation ONLY on success
        if (mounted) {
           context.go('/dashboard');
        }

      } catch (e) {
        print('LoginScreen: SignIn threw error: $e'); 
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    ref.listen<AsyncValue>(authControllerProvider, (_, state) {
      if (state.hasError) {
        print('LoginScreen: Auth Error State Received: ${state.error}');
        final errorMessage = state.error.toString();

        if (errorMessage.contains('network-request-failed') || errorMessage.toLowerCase().contains('network')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.wifi_off, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "No internet connection detected. Please check your network and try again.",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFFE53935),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(20),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage.contains('invalid-credential') 
                ? "Invalid email or password. Please try again." 
                : errorMessage.replaceAll('Exception: ', '').replaceAll(RegExp(r'\[.*?\] '), '')), // strip messy firebase codes
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1e1e24), Color(0xFF2d2d35)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 8,
              color: const Color(0xFF2a2a32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.school_rounded, size: 64, color: Colors.blueAccent),
                      const SizedBox(height: 16),
                      Text(
                        'Teacher Login',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white
                            ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _schoolIdController,
                        enabled: !isLoading && !_isAuthenticating,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'School ID',
                          hintText: 'Enter your unique school code',
                          labelStyle: TextStyle(color: Colors.white70),
                          prefixIcon: Icon(Icons.location_city_outlined, color: Colors.white70),
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your School ID';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        enabled: !isLoading && !_isAuthenticating,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          labelStyle: TextStyle(color: Colors.white70),
                          prefixIcon: Icon(Icons.email_outlined, color: Colors.white70),
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        enabled: !isLoading && !_isAuthenticating,
                        obscureText: _isPasswordObscured,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: const TextStyle(color: Colors.white70),
                          prefixIcon: const Icon(Icons.lock_outlined, color: Colors.white70),
                          border: const OutlineInputBorder(),
                          enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordObscured ? Icons.visibility_off : Icons.visibility,
                              color: Colors.white70,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordObscured = !_isPasswordObscured;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: isLoading || _isAuthenticating ? null : _submit,
                          style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent),
                          child: isLoading || _isAuthenticating
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Login'),
                        ),
                      ),
                      if (_hasSavedCredentials) ...[
                        const SizedBox(height: 20),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: isLoading || _isAuthenticating ? null : _authenticateWithBiometrics,
                          icon: const Icon(Icons.fingerprint, color: Colors.white, size: 28),
                          label: const Text('Login with Device Lock', style: TextStyle(color: Colors.white)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
