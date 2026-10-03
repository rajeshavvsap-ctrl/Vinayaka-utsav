import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Committee members. Everyone sees the approved list; admins approve new
/// registrations, reject them, and grant or remove admin rights.
class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.users.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return LoadErrorView(snap.error);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!.docs.map(Member.fromDoc).toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          final pending = all.where((m) => m.status == 'pending').toList();
          final approved = all.where((m) => m.status == 'approved').toList()
            ..sort((a, b) => (a.isAdmin == b.isAdmin) ? 0 : (a.isAdmin ? -1 : 1));
          final rejected = all.where((m) => m.status == 'rejected').toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              if (session.isAdmin && pending.isNotEmpty) ...[
                _header('Waiting for approval (${pending.length})'),
                for (final m in pending) _pendingCard(context, m),
              ],
              _header('Committee members (${approved.length})'),
              for (final m in approved) _memberRow(context, m),
              if (session.isAdmin && rejected.isNotEmpty) ...[
                _header('Not approved (${rejected.length})'),
                for (final m in rejected) _memberRow(context, m),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(text, style: display(18)),
      );

  Widget _pendingCard(BuildContext context, Member m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            Text('${m.phone} · ${m.email}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _set(context, m, {'status': 'rejected'}),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _set(context, m, {'status': 'approved'}),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.green, minimumSize: const Size(0, 44)),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberRow(BuildContext context, Member m) {
    final isMe = m.id == session.me.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.blueBg,
              child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${m.name}${isMe ? ' (you)' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(m.phone, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
            if (m.isAdmin) const StatusPill('Admin', bg: AppColors.amberBg, fg: AppColors.amber),
            if (m.status == 'rejected') StatusPill.forStatus('rejected'),
            if (session.isAdmin && !isMe)
              PopupMenuButton<String>(
                tooltip: 'Manage',
                onSelected: (v) {
                  switch (v) {
                    case 'admin':
                      _set(context, m, {'role': 'admin'});
                    case 'member':
                      _set(context, m, {'role': 'member'});
                    case 'approve':
                      _set(context, m, {'status': 'approved'});
                    case 'remove':
                      _confirmRemove(context, m);
                  }
                },
                itemBuilder: (_) => [
                  if (m.status == 'approved' && m.role != 'admin')
                    const PopupMenuItem(value: 'admin', child: Text('Make admin')),
                  if (m.role == 'admin') const PopupMenuItem(value: 'member', child: Text('Remove admin rights')),
                  if (m.status != 'approved') const PopupMenuItem(value: 'approve', child: Text('Approve')),
                  if (m.status == 'approved') const PopupMenuItem(value: 'remove', child: Text('Remove access')),
                ],
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, Member m) async {
    if (await confirmDialog(context, 'Remove access?', '${m.name} will no longer be able to open the app.',
        ok: 'Remove')) {
      if (context.mounted) await _set(context, m, {'status': 'rejected', 'role': 'member'});
    }
  }

  Future<void> _set(BuildContext context, Member m, Map<String, dynamic> data) async {
    try {
      await Db.users.doc(m.id).update(data);
    } catch (e) {
      if (context.mounted) toast(context, 'Could not update: $e');
    }
  }
}
