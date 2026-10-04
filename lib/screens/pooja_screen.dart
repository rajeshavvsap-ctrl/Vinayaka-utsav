import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../services/report.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Pooja Seva sign-up: members add their (or their family's) name
/// to a pooja slot on a particular festival day.
class PoojaScreen extends StatefulWidget {
  const PoojaScreen({super.key, required this.session});
  final Session session;

  @override
  State<PoojaScreen> createState() => _PoojaScreenState();
}

class _PoojaScreenState extends State<PoojaScreen> {
  late String _day = widget.session.festival.initialDay();

  @override
  Widget build(BuildContext context) {
    final f = widget.session.festival;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pooja Seva'),
        actions: [PdfAction(make: () => sharePoojaReport(widget.session.festival))],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DayStrip(festival: f, selected: _day, onPick: (d) => setState(() => _day = d)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text('Day ${f.dayNumber(_day)} · ${prettyDay(_day)}', style: display(18)),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: Db.poojaSignups.where('date', isEqualTo: _day).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return LoadErrorView(snap.error);
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs.toList()
                  ..sort((a, b) => '${a.data()['name']}'.toLowerCase().compareTo('${b.data()['name']}'.toLowerCase()));

                final slots = [...f.slots];
                // Keep entries whose slot was later renamed/removed visible.
                for (final d in docs) {
                  final s = '${d.data()['slot']}';
                  if (!slots.contains(s)) slots.add(s);
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    for (final slot in slots) ...[
                      _slotCard(context, slot, docs.where((d) => d.data()['slot'] == slot).toList()),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotCard(BuildContext context, String slot, List<QueryDocumentSnapshot<Map<String, dynamic>>> entries) {
    final mine = entries.any((e) => e.data()['createdBy'] == widget.session.me.id);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.local_florist_outlined, bg: AppColors.greenBg, fg: AppColors.green, size: 40),
              const SizedBox(width: 12),
              Expanded(child: Text(slot, style: display(18))),
              Text('${entries.length} ${entries.length == 1 ? 'name' : 'names'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('No one has signed up yet.', style: TextStyle(color: AppColors.muted)),
            ),
          for (final e in entries) _entryRow(context, e),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _add(context, slot, mine),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: Text(mine ? 'Add another name' : 'Add my name'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
        ],
      ),
    );
  }

  Widget _entryRow(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> e) {
    final d = e.data();
    final canChange = widget.session.canChange(d);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                if ('${d['note'] ?? ''}'.isNotEmpty)
                  Text('${d['note']}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
          if (canChange)
            IconButton(
              tooltip: 'Remove name',
              icon: const Icon(Icons.close, color: AppColors.muted),
              onPressed: () async {
                if (await confirmDialog(context, 'Remove name?', '${d['name']} will be removed from this slot.',
                    ok: 'Remove')) {
                  await e.reference.delete();
                }
              },
            ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, String slot, bool alreadyMine) async {
    final name = TextEditingController(text: alreadyMine ? '' : widget.session.me.name);
    final note = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(slot),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(prettyDay(_day), style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              TextFormField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note (e.g. with family, 4 people)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Db.poojaSignups.add({
          'date': _day,
          'slot': slot,
          'name': name.text.trim(),
          'note': note.text.trim(),
          ...Db.stamp(),
        });
        if (context.mounted) toast(context, 'Added to $slot');
      } catch (e) {
        if (context.mounted) toast(context, 'Could not add: $e');
      }
    }
  }
}
