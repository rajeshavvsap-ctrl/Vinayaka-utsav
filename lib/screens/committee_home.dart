import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/account.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'members_screen.dart';

/// Main screen: "Horizon Committee Events" with one tile per event.
/// Each event opens its own dashboard (activities, seva, expenses,
/// contributions, reports, settings).
class CommitteeHomeScreen extends StatefulWidget {
  const CommitteeHomeScreen({super.key, required this.me});
  final Member me;

  @override
  State<CommitteeHomeScreen> createState() => _CommitteeHomeScreenState();
}

class _CommitteeHomeScreenState extends State<CommitteeHomeScreen> {
  final _subs = <StreamSubscription<dynamic>>[];
  Map<String, Map<String, dynamic>> _settings = {};
  Map<String, num> _collected = {};
  Map<String, num> _spent = {};
  Map<String, int> _toVerify = {};
  int _memberCount = 0;
  int _pendingMembers = 0;

  @override
  void initState() {
    super.initState();
    _subs.add(Db.settings.snapshots().listen((s) {
      if (mounted) setState(() => _settings = {for (final d in s.docs) d.id: d.data()});
    }, onError: (Object _) {}));

    _subs.add(Db.contributions.snapshots().listen((s) {
      final col = <String, num>{}, ver = <String, int>{};
      for (final d in s.docs) {
        final m = d.data();
        final ev = eventOf(m);
        if (m['status'] == 'verified') col[ev] = (col[ev] ?? 0) + toNum(m['amount']);
        if (m['status'] == 'pending') {
          ver[ev] = (ver[ev] ?? 0) + 1;
          if (m['createdBy'] != widget.me.id) _enqueue('payment', d);
        }
      }
      if (mounted) {
        setState(() {
          _collected = col;
          _toVerify = ver;
        });
      }
    }, onError: (Object _) {}));

    _subs.add(Db.expenses.snapshots().listen((s) {
      final sp = <String, num>{};
      for (final d in s.docs) {
        final ev = eventOf(d.data());
        sp[ev] = (sp[ev] ?? 0) + toNum(d.data()['amount']);
      }
      if (mounted) setState(() => _spent = sp);
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

  List<Festival> get _events {
    final custom = (_settings['eventList']?['custom'] as List?) ?? const [];
    return [
      for (final d in defaultEvents) Festival.fromMap(_settings[settingsDocId(d.id)], id: d.id),
      for (final c in custom.whereType<Map>())
        Festival.fromMap(_settings[settingsDocId('${c['id']}')], id: '${c['id']}', title: '${c['title']}'),
    ];
  }

  String _eventTitle(String id) {
    for (final e in _events) {
      if (e.id == id) return e.title;
    }
    return eventDefFor(id).title;
  }

  Session get _committeeSession =>
      Session(widget.me, Festival.fromMap(null, id: 'committee', title: 'Horizon Committee'));

  void _openEvent(Festival f) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EventEntry(me: widget.me, eventId: f.id, title: f.title),
      ));

  Future<void> _addEvent() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add event'),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Event name (e.g. Ugadi, Sankranti)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(c, name.text.trim().length >= 3),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final title = name.text.trim();
    final id = 'ev${DateTime.now().millisecondsSinceEpoch}';
    try {
      await Db.eventList.set({
        'custom': FieldValue.arrayUnion([
          {'id': id, 'title': title}
        ]),
      }, SetOptions(merge: true));
      await Db.eventDoc(id).set({'title': title}, SetOptions(merge: true));
      if (mounted) toast(context, '$title added. Open it and set the dates in Settings.');
    } catch (e) {
      if (mounted) toast(context, 'Could not add event: $e');
    }
  }

  String _range(Festival f) {
    if (!f.configured) return 'Dates not set yet';
    final first = f.dayKeys.first, last = f.dayKeys.last;
    return f.days == 1 ? prettyDay(first) : '${shortDay(first)} – ${prettyDay(last)} · ${f.days} days';
  }

  (String, Color) _status(Festival f) {
    if (!f.configured) return ('Set up', AppColors.muted);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final n = f.dayNumber(dayKey(today));
    if (n != null) return (f.days == 1 ? 'Today' : 'Ongoing · Day $n', AppColors.green);
    if (today.isBefore(f.start)) {
      final d = f.start.difference(today).inDays;
      return ('In $d day${d == 1 ? '' : 's'}', AppColors.amber);
    }
    return ('Completed', AppColors.muted);
  }

  (IconData, Color, Color) _look(String icon) {
    switch (icon) {
      case 'durga':
        return (Icons.local_fire_department_outlined, AppColors.redBg, AppColors.maroon);
      case 'ganesha':
        return (Icons.temple_hindu_outlined, AppColors.amberBg, AppColors.amber);
      case 'party':
        return (Icons.celebration_outlined, AppColors.purpleBg, AppColors.purple);
      default:
        return (Icons.event_available_outlined, AppColors.blueBg, AppColors.blue);
    }
  }

  // ---------- approval pop-ups (admins only) ----------
  // While the app is open, every new member request and every new payment
  // waiting for verification pops up, one at a time, with action buttons.
  final _prompted = <String>{};
  final _queue = <DocumentReference<Map<String, dynamic>>>[];
  bool _showing = false;

  void _enqueue(String kind, QueryDocumentSnapshot<Map<String, dynamic>> d) {
    if (!widget.me.isAdmin) return;
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
                Text(_eventTitle(eventOf(c)), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                Text('${c['name']}', style: display(20)),
                Text(rupees(toNum(c['amount'])), style: display(26, color: AppColors.maroon)),
                if (flatLabel(c).isNotEmpty) Text('Flat: ${flatLabel(c)}'),
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
          'verifiedBy': widget.me.id,
          'verifiedByName': widget.me.name,
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


  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final events = _events;
    num totalIn = 0, totalOut = 0;
    for (final v in _collected.values) {
      totalIn += v;
    }
    for (final v in _spent.values) {
      totalOut += v;
    }

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
                            Text('Namaste, ${me.name.split(' ').first}',
                                style: const TextStyle(color: AppColors.gold, fontSize: 14)),
                            Text('Horizon Committee', style: display(26, color: Colors.white)),
                            const Text('Events', style: TextStyle(color: Color(0xFFF3DCCB), fontSize: 15)),
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
                          } else if (v == 'delete') {
                            await deleteMyAccount(context);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(enabled: false, child: Text('${me.name}${me.isAdmin ? ' (Admin)' : ''}')),
                          const PopupMenuItem(value: 'out', child: Text('Sign out')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete my account')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.maroonSoft, borderRadius: BorderRadius.circular(18)),
                    child: Row(
                      children: [
                        _HeadMoney('Collected', totalIn),
                        _HeadMoney('Spent', totalOut),
                        _HeadMoney('Balance', totalIn - totalOut),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text('Events', style: display(20)),
            ),
          ),
          SliverList.separated(
            itemCount: events.length,
            separatorBuilder: (context, i) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final f = events[i];
              final (icon, bg, fg) = _look(f.icon);
              final (status, statusColor) = _status(f);
              final verify = _toVerify[f.id] ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppCard(
                  onTap: () => _openEvent(f),
                  child: Row(
                    children: [
                      IconBadge(icon: icon, bg: bg, fg: fg, size: 52),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.title, style: display(18)),
                            Text(_range(f), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                StatusPill(status, bg: statusColor.withAlpha(30), fg: statusColor),
                                StatusPill('${rupees(_collected[f.id] ?? 0)} in',
                                    bg: AppColors.greenBg, fg: AppColors.green),
                                if ((_spent[f.id] ?? 0) > 0)
                                  StatusPill('${rupees(_spent[f.id] ?? 0)} spent',
                                      bg: AppColors.redBg, fg: AppColors.maroon),
                                if (me.isAdmin && verify > 0)
                                  StatusPill('$verify to verify', bg: AppColors.amberBg, fg: AppColors.amber),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.muted),
                    ],
                  ),
                ),
              );
            },
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => MembersScreen(session: _committeeSession))),
                    child: Row(
                      children: [
                        const IconBadge(icon: Icons.groups_outlined, bg: AppColors.blueBg, fg: AppColors.blue),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Members', style: display(18)),
                              Text(
                                me.isAdmin && _pendingMembers > 0
                                    ? '$_pendingMembers waiting for approval'
                                    : '$_memberCount committee members',
                                style: const TextStyle(color: AppColors.muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        if (me.isAdmin && _pendingMembers > 0)
                          StatusPill('$_pendingMembers', bg: AppColors.saffron, fg: AppColors.ink),
                        const Icon(Icons.chevron_right, color: AppColors.muted),
                      ],
                    ),
                  ),
                  if (me.isAdmin) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _addEvent,
                      icon: const Icon(Icons.add),
                      label: const Text('Add another event'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadMoney extends StatelessWidget {
  const _HeadMoney(this.label, this.value);
  final String label;
  final num value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppColors.gold, fontSize: 12)),
          FittedBox(child: Text(rupees(value), style: display(18, color: Colors.white))),
        ],
      ),
    );
  }
}

/// Opens one event's dashboard and keeps it in sync with its settings.
class EventEntry extends StatelessWidget {
  const EventEntry({super.key, required this.me, required this.eventId, required this.title});
  final Member me;
  final String eventId;
  final String title;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Db.eventDoc(eventId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(body: LoadErrorView(snap.error));
        if (!snap.hasData) return const Loading();
        final f = Festival.fromMap(snap.data!.data(), id: eventId, title: title);
        return HomeScreen(key: ValueKey(eventId), session: Session(me, f));
      },
    );
  }
}
