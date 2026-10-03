import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'activities_screen.dart';
import 'contributions_screen.dart';
import 'expenses_screen.dart';
import 'members_screen.dart';
import 'pooja_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final Session session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _subs = <StreamSubscription<dynamic>>[];
  num _collected = 0;
  num _pendingContrib = 0;
  int _pendingContribCount = 0;
  num _spent = 0;
  int _expenseCount = 0;
  int _todayActivities = 0;
  int _todaySignups = 0;
  int _memberCount = 0;
  int _pendingMembers = 0;
  Map<String, dynamic>? _next; // next activity today

  @override
  void initState() {
    super.initState();
    final today = dayKey(DateTime.now());

    _subs.add(Db.contributions.snapshots().listen((s) {
      num v = 0, p = 0;
      var pc = 0;
      for (final d in s.docs) {
        final m = d.data();
        if (m['status'] == 'verified') v += toNum(m['amount']);
        if (m['status'] == 'pending') {
          p += toNum(m['amount']);
          pc++;
          if (m['createdBy'] != widget.session.me.id) _enqueue('payment', d);
        }
      }
      if (mounted) {
        setState(() {
          _collected = v;
          _pendingContrib = p;
          _pendingContribCount = pc;
        });
      }
    }, onError: (Object _) {}));

    _subs.add(Db.expenses.snapshots().listen((s) {
      num t = 0;
      for (final d in s.docs) {
        t += toNum(d.data()['amount']);
      }
      if (mounted) {
        setState(() {
          _spent = t;
          _expenseCount = s.size;
        });
      }
    }, onError: (Object _) {}));

    _subs.add(Db.activities.where('date', isEqualTo: today).snapshots().listen((s) {
      final now = TimeOfDay.now();
      final nowKey = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final list = s.docs.map((d) => d.data()).toList()
        ..sort((a, b) => '${a['time']}'.compareTo('${b['time']}'));
      Map<String, dynamic>? next;
      for (final a in list) {
        if ('${a['time']}'.compareTo(nowKey) >= 0) {
          next = a;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _todayActivities = s.size;
          _next = next;
        });
      }
    }, onError: (Object _) {}));

    _subs.add(Db.poojaSignups.where('date', isEqualTo: today).snapshots().listen((s) {
      if (mounted) setState(() => _todaySignups = s.size);
    }, onError: (Object _) {}));

    _subs.add(Db.users.snapshots().listen((s) {
      var approved = 0, pending = 0;
      for (final d in s.docs) {
        final st = d.data()['status'];
        if (st == 'approved') approved++;
        if (st == 'pending') {
          pending++;
          _enqueue('member', d);
        }
      }
      if (mounted) {
        setState(() {
          _memberCount = approved;
          _pendingMembers = pending;
        });
      }
    }, onError: (Object _) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  // ---------- approval pop-ups (admins only) ----------
  // While the app is open, every new member request and every new payment
  // waiting for verification pops up, one at a time, with action buttons.
  final _prompted = <String>{};
  final _queue = <DocumentReference<Map<String, dynamic>>>[];
  bool _showing = false;

  void _enqueue(String kind, QueryDocumentSnapshot<Map<String, dynamic>> d) {
    if (!widget.session.isAdmin) return;
    if (!_prompted.add('$kind/${d.id}')) return;
    _queue.add(d.reference);
    _showNext();
  }

  Future<void> _showNext() async {
    if (_showing || _queue.isEmpty || !mounted) return;
    _showing = true;
    final ref = _queue.removeAt(0);
    try {
      final fresh = await ref.get();
      if (mounted && fresh.data()?['status'] == 'pending') {
        if (ref.parent.id == 'users') {
          await _memberDialog(fresh);
        } else {
          await _paymentDialog(fresh);
        }
      }
    } catch (_) {
      // Ignore; the item is still visible in its screen.
    }
    _showing = false;
    if (mounted) _showNext();
  }

  Future<void> _memberDialog(DocumentSnapshot<Map<String, dynamic>> d) async {
    final m = d.data()!;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.person_add_alt_1_outlined, color: AppColors.blue, size: 36),
        title: const Text('New member request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${m['name']}', style: display(20)),
            const SizedBox(height: 6),
            Text('Mobile: ${m['phone']}'),
            Text('Email: ${m['email']}'),
            const SizedBox(height: 10),
            const Text('Approve only committee members.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        ),
        actions: _actions(c, 'Approve'),
      ),
    );
    if (action == 'ok' || action == 'reject') {
      try {
        await d.reference.update({'status': action == 'ok' ? 'approved' : 'rejected'});
        if (mounted) toast(context, '${m['name']} ${action == 'ok' ? 'approved' : 'rejected'}');
      } catch (e) {
        if (mounted) toast(context, 'Could not update: $e');
      }
    }
  }

  Future<void> _paymentDialog(DocumentSnapshot<Map<String, dynamic>> d) async {
    final c = d.data()!;
    final proofId = '${c['proofId'] ?? ''}';
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.volunteer_activism_outlined, color: AppColors.purple, size: 36),
        title: const Text('Payment to verify'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c['name']}', style: display(20)),
                Text(rupees(toNum(c['amount'])), style: display(26, color: AppColors.maroon)),
                Text('${c['mode']} · ${prettyDay('${c['date']}')}'),
                if ('${c['txnRef'] ?? ''}'.isNotEmpty) Text('Ref: ${c['txnRef']}'),
                const SizedBox(height: 10),
                if (proofId.isNotEmpty)
                  ProofImage(proofId: proofId, height: 240)
                else
                  const Text('No screenshot attached.', style: TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
        ),
        actions: _actions(ctx, 'Verify'),
      ),
    );
    if (action == 'ok' || action == 'reject') {
      try {
        await d.reference.update({
          'status': action == 'ok' ? 'verified' : 'rejected',
          'verifiedBy': widget.session.me.id,
          'verifiedByName': widget.session.me.name,
          'verifiedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) toast(context, 'Payment ${action == 'ok' ? 'verified' : 'rejected'}');
      } catch (e) {
        if (mounted) toast(context, 'Could not update: $e');
      }
    }
  }

  List<Widget> _actions(BuildContext c, String okLabel) => [
        TextButton(onPressed: () => Navigator.pop(c, 'later'), child: const Text('Later')),
        TextButton(
          onPressed: () => Navigator.pop(c, 'reject'),
          style: TextButton.styleFrom(foregroundColor: AppColors.red),
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, 'ok'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.green, minimumSize: const Size(96, 44)),
          child: Text(okLabel),
        ),
      ];

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  void _copySummary() {
    final f = widget.session.festival;
    final text = '${f.title} - Accounts summary\n'
        'Collected (verified): ${rupees(_collected)}\n'
        'Pending verification: ${rupees(_pendingContrib)}\n'
        'Spent ($_expenseCount bills): ${rupees(_spent)}\n'
        'Balance: ${rupees(_collected - _spent)}\n'
        'Ganapati Bappa Morya!';
    Clipboard.setData(ClipboardData(text: text));
    toast(context, 'Summary copied. Paste it in WhatsApp.');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final f = s.festival;
    final todayNo = f.dayNumber(dayKey(DateTime.now()));
    final balance = _collected - _spent;

    final tiles = <_Tile>[
      _Tile('Activities', '$_todayActivities today', Icons.event_note_outlined, AppColors.amberBg, AppColors.amber,
          () => _open(ActivitiesScreen(session: s))),
      _Tile('Pooja Seva', '$_todaySignups names today', Icons.local_florist_outlined, AppColors.greenBg,
          AppColors.green, () => _open(PoojaScreen(session: s))),
      _Tile('Expenses', rupees(_spent), Icons.receipt_long_outlined, AppColors.redBg, AppColors.maroon,
          () => _open(ExpensesScreen(session: s))),
      _Tile(
          'Contributions',
          _pendingContribCount > 0 && s.isAdmin ? '$_pendingContribCount to verify' : rupees(_collected),
          Icons.volunteer_activism_outlined,
          AppColors.purpleBg,
          AppColors.purple,
          () => _open(ContributionsScreen(session: s)),
          badge: s.isAdmin ? _pendingContribCount : 0),
      _Tile(
          'Members',
          s.isAdmin && _pendingMembers > 0 ? '$_pendingMembers to approve' : '$_memberCount members',
          Icons.groups_outlined,
          AppColors.blueBg,
          AppColors.blue,
          () => _open(MembersScreen(session: s)),
          badge: s.isAdmin ? _pendingMembers : 0),
      if (s.isAdmin)
        _Tile('Reports', 'Day-wise & final PDF', Icons.picture_as_pdf_outlined, AppColors.greenBg,
            AppColors.green, () => _open(ReportsScreen(session: s))),
      if (s.isAdmin)
        _Tile('Settings', 'Dates, slots, UPI', Icons.tune_outlined, AppColors.amberBg, AppColors.amber,
            () => _open(SettingsScreen(festival: f))),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.maroon,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 12, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Namaste, ${s.me.name.split(' ').first}',
                                style: const TextStyle(color: AppColors.gold, fontSize: 14)),
                            Text(f.title, style: display(26, color: Colors.white)),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Menu',
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onSelected: (v) async {
                          if (v == 'out' &&
                              await confirmDialog(context, 'Sign out?', 'You can sign in again any time.')) {
                            await FirebaseAuth.instance.signOut();
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(enabled: false, child: Text('${s.me.name}${s.isAdmin ? ' (Admin)' : ''}')),
                          const PopupMenuItem(value: 'out', child: Text('Sign out')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: AppColors.maroonSoft, borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          todayNo != null ? 'Today · Day $todayNo of ${f.days}' : _offSeasonLabel(f),
                          style: const TextStyle(color: AppColors.gold, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _next != null ? '${_next!['title']}' : 'No more events today',
                          style: display(19, color: Colors.white),
                        ),
                        if (_next != null)
                          Text(
                            '${prettyTime('${_next!['time']}')}'
                            '${'${_next!['place'] ?? ''}'.isNotEmpty ? ' · ${_next!['place']}' : ''}',
                            style: const TextStyle(color: Color(0xFFF3DCCB), fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (s.isAdmin && !f.configured)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: AppCard(
                  color: AppColors.amberBg,
                  onTap: () => _open(SettingsScreen(festival: f)),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.amber),
                      SizedBox(width: 10),
                      Expanded(
                          child: Text('Set the festival start date, pooja slots and UPI ID in Settings.',
                              style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600))),
                      Icon(Icons.chevron_right, color: AppColors.amber),
                    ],
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: AppCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        _Money('Collected', _collected, AppColors.green),
                        _Money('Spent', _spent, AppColors.maroon),
                        _Money('Balance', balance, balance < 0 ? AppColors.red : AppColors.ink),
                      ],
                    ),
                    if (_pendingContrib > 0) ...[
                      const SizedBox(height: 8),
                      Text('${rupees(_pendingContrib)} waiting for verification',
                          style: const TextStyle(color: AppColors.amber, fontSize: 13)),
                    ],
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _copySummary,
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('Copy summary for WhatsApp'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.15,
              children: tiles.map((t) => _TileCard(t)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _offSeasonLabel(Festival f) {
    final today = DateTime.now();
    final start = f.start;
    if (DateTime(today.year, today.month, today.day).isBefore(start)) {
      final days = start.difference(DateTime(today.year, today.month, today.day)).inDays;
      return 'Festival starts in $days day${days == 1 ? '' : 's'}';
    }
    return 'Festival completed';
  }
}

class _Money extends StatelessWidget {
  const _Money(this.label, this.value, this.color);
  final String label;
  final num value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          FittedBox(child: Text(rupees(value), style: display(20, color: color))),
        ],
      ),
    );
  }
}

class _Tile {
  _Tile(this.title, this.subtitle, this.icon, this.bg, this.fg, this.onTap, {this.badge = 0});
  final String title;
  final String subtitle;
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
  final int badge;
}

class _TileCard extends StatelessWidget {
  const _TileCard(this.t);
  final _Tile t;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: t.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: t.icon, bg: t.bg, fg: t.fg),
              const Spacer(),
              if (t.badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.saffron, borderRadius: BorderRadius.circular(10)),
                  child: Text('${t.badge}',
                      style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
            ],
          ),
          const Spacer(),
          Text(t.title, style: display(18)),
          Text(t.subtitle,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
      ),
    );
  }
}
