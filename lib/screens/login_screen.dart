import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hidePass = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = FirebaseAuth.instance;
    try {
      if (_register) {
        final name = _name.text.trim();
        final phone = _phone.text.trim();
        final email = _email.text.trim();
        final cred = await auth.createUserWithEmailAndPassword(email: email, password: _pass.text);
        await Db.users.doc(cred.user!.uid).set({
          'name': name,
          'phone': phone,
          'email': email,
          'role': 'member',
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await auth.signInWithEmailAndPassword(email: _email.text.trim(), password: _pass.text);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _authMessage(e.code, e.message));
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Type your email above first, then tap "Forgot password".');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) toast(context, 'Password reset link sent to $email');
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _authMessage(e.code, e.message));
    }
  }

  String _authMessage(String code, [String? detail]) {
    switch (code) {
      case 'invalid-email':
        return 'That email address looks wrong.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'This email is already registered. Sign in instead.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes.';
      case 'operation-not-allowed':
        return 'Email/Password sign-in is not enabled in Firebase Authentication.';
      default:
        final d = detail ?? '';
        if (d.contains('CONFIGURATION_NOT_FOUND')) {
          return 'Firebase Authentication is not set up yet (open Authentication and click Get started).';
        }
        return 'Could not sign in ($code). $d';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: IconBadge(
                          icon: Icons.temple_hindu_outlined, bg: AppColors.maroon, fg: AppColors.gold, size: 72),
                    ),
                    const SizedBox(height: 16),
                    const Text('Ganapati Bappa Morya',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600)),
                    Text('Vinayaka Chaturthi Committee', textAlign: TextAlign.center, style: display(26)),
                    const SizedBox(height: 6),
                    Text(
                      _register
                          ? 'Register, then a committee admin will approve you.'
                          : 'Members only. Sign in to continue.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 24),
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Full name'),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Mobile number'),
                        validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10
                            ? 'Enter a 10-digit mobile number'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pass,
                      obscureText: _hidePass,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: _hidePass ? 'Show password' : 'Hide password',
                          icon: Icon(_hidePass ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hidePass = !_hidePass),
                        ),
                      ),
                      validator: (v) => (v ?? '').length < 6 ? 'At least 6 characters' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.red)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : Text(_register ? 'Register' : 'Sign in'),
                    ),
                    if (!_register)
                      TextButton(onPressed: _busy ? null : _forgot, child: const Text('Forgot password?')),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                      child: Text(_register ? 'Already registered? Sign in' : 'New member? Register here'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
