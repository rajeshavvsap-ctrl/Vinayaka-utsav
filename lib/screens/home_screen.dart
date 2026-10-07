import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'activities_screen.dart';
import 'contributions_screen.dart';
import 'expenses_screen.dart';
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
  String get _ev => widget.session.festival.id;
  num _collected = 0;
  num _pendingContrib = 0;
  int _pendingContribCount = 0;
  num _spent = 0;
  int _expenseCount = 0;
  int _todayActivities = 0;
  int _todaySignups = 0;
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
        if (!inEvent(m, _ev)) continue;
        if (m['status'] == 'verified') v += toNum(m['amount']);
        if (m['status'] == 'pending') {
          p += toNum(m['amount']);
          pc++;
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
      var n = 0;
      for (final d in s.docs) {
        if (!inEvent(d.data(), _ev)) continue;
        t += toNum(d.data()['amount']);
        n++;
      }
      if (mounted) {
        setState(() {
          _spent = t;
          _expenseCount = n;
        });
      }
    }, onError: (Object _) {}));

    _subs.add(Db.activities.where('date', isEqualTo: today).snapshots().listen((s) {
      final now = TimeOfDay.now();
      final nowKey = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final list = s.docs.map((d) => d.data()).where((m) => inEvent(m, _ev)).toList()
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
          _todayActivities = list.length;
          _next = next;
        });
      }
    }, onError: (Object _) {}));

    _subs.add(Db.poojaSignups.where('date', isEqualTo: today).snapshots().listen((s) {
      final n = s.docs.where((d) => inEvent(d.data(), _ev)).length;
      if (mounted) setState(() => _todaySignups = n);
    }, onError: (Object _) {}));

  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  void _copySummary() {
    final f = widget.session.festival;
    final text = '${f.title} - Accounts summary\n'
        'Collected (verified): ${rupees(_collected)}\n'
        'Pending verification: ${rupees(_pendingContrib)}\n'
        'Spent ($_expenseCount bills): ${rupees(_spent)}\n'
        'Balance: ${rupees(_collected - _spent)}\n'
        '${f.id == 'vinayaka' ? 'Ganapati Bappa Morya!' : 'Horizon Committee'}';
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
      _Tile(f.sevaLabel, '$_todaySignups names today', Icons.local_florist_outlined, AppColors.greenBg,
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
              padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 12, 16, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'All events',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Horizon Committee', style: TextStyle(color: AppColors.gold, fontSize: 14)),
                            Text(f.title, style: display(24, color: Colors.white)),
                          ],
                        ),
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
                          child: Text('Set this event\'s start date, number of days, slots and UPI ID in Settings.',
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
      return 'Starts in $days day${days == 1 ? '' : 's'}';
    }
    return 'Event completed';
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
