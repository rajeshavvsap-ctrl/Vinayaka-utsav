import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/common.dart';
import 'db.dart';

/// Permanently deletes the signed-in user's login and profile
/// (required by Google Play for apps that let people create accounts).
/// Committee records the user entered (expenses, contributions) are kept.
Future<void> deleteMyAccount(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.email == null) return;

  final pass = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Your login and profile will be permanently deleted. Expenses and contributions '
            'you entered stay in the committee accounts.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Enter your password to confirm'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8E1C1C), minimumSize: const Size(96, 44)),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  try {
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: pass.text),
    );
    await Db.users.doc(user.uid).delete();
    await user.delete();
    if (context.mounted) toast(context, 'Your account has been deleted.');
  } on FirebaseAuthException catch (e) {
    if (context.mounted) {
      toast(context, e.code == 'wrong-password' || e.code == 'invalid-credential'
          ? 'Password is incorrect.'
          : 'Could not delete account (${e.code}).');
    }
  } catch (e) {
    if (context.mounted) toast(context, 'Could not delete account: $e');
  }
}
