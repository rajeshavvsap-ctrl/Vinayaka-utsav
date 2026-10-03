import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Shown to registered users until a committee admin approves them.
class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key, required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final rejected = member.status == 'rejected';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconBadge(
                  icon: rejected ? Icons.block_outlined : Icons.hourglass_top_outlined,
                  bg: rejected ? AppColors.redBg : AppColors.amberBg,
                  fg: rejected ? AppColors.red : AppColors.amber,
                  size: 72,
                ),
                const SizedBox(height: 20),
                Text(
                  rejected ? 'Access not approved' : 'Waiting for approval',
                  style: display(26),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  rejected
                      ? 'Your request to join was not approved. Please contact a committee member if this is a mistake.'
                      : 'Namaste ${member.name}! A committee admin needs to approve your account. '
                          'This screen will open the app automatically once you are approved.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 15),
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fallback if an account exists but its profile document does not
/// (e.g. registration was interrupted).
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, required this.user});
  final User user;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Db.users.doc(widget.user.uid).set({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'email': widget.user.email ?? '',
        'role': 'member',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your details'),
        actions: [
          IconButton(
              tooltip: 'Sign out', onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Tell the committee who you are.', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
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
              validator: (v) =>
                  (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10 ? 'Enter a 10-digit mobile number' : null,
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Continue')),
          ],
        ),
      ),
    );
  }
}
