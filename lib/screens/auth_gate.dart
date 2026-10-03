import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'pending_screen.dart';

/// Decides what to show: login -> profile setup -> waiting for approval -> app.
/// Only members a committee admin has approved get past this gate, and the
/// Firestore security rules enforce the same check on the server.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) return const Loading();
        final user = authSnap.data;
        if (user == null) return const LoginScreen();
        return _ProfileGate(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

class _ProfileGate extends StatelessWidget {
  const _ProfileGate({super.key, required this.user});
  final User user;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Db.users.doc(user.uid).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(body: LoadErrorView(snap.error));
        if (!snap.hasData) return const Loading();
        if (!snap.data!.exists) return ProfileSetupScreen(user: user);
        final me = Member.fromDoc(snap.data!);
        if (!me.isApproved) return PendingScreen(member: me);
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: Db.festival.snapshots(),
          builder: (context, fSnap) {
            if (fSnap.hasError) return Scaffold(body: LoadErrorView(fSnap.error));
            if (!fSnap.hasData) return const Loading();
            final festival = Festival.fromMap(fSnap.data!.data());
            return HomeScreen(session: Session(me, festival));
          },
        );
      },
    );
  }
}
