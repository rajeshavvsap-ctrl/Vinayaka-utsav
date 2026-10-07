import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Admin-only festival settings: title, start date, number of days,
/// pooja slots and the committee UPI ID.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.festival});
  final Festival festival;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.festival.title);
  late final _days = TextEditingController(text: '${widget.festival.days}');
  late final _slots = TextEditingController(text: widget.festival.slots.join('\n'));
  late final _upi = TextEditingController(text: widget.festival.upiId);
  late DateTime _start = widget.festival.start;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _days.dispose();
    _slots.dispose();
    _upi.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final slots = _slots.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    try {
      await Db.eventDoc(widget.festival.id).set({
        'title': _title.text.trim(),
        'startDate': Timestamp.fromDate(DateTime(_start.year, _start.month, _start.day)),
        'days': int.parse(_days.text.trim()),
        'poojaSlots': slots,
        'upiId': _upi.text.trim(),
        'updatedBy': Db.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        toast(context, 'Settings saved');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Could not save: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.festival.title} settings')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title (e.g. Vinayaka Chaturthi 2026)'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a title' : null,
            ),
            const SizedBox(height: 12),
            DateField(
              label: 'Festival start date (Day 1)',
              value: _start,
              onChanged: (d) => setState(() => _start = d),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Number of event days (1–31)',
                helperText: 'Members can only pick dates inside these days.'),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return n == null || n < 1 || n > 31 ? 'Enter 1 to 31' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _slots,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Pooja slots (one per line)',
                alignLabelWithHint: true,
                helperText: 'Members add their names under these slots each day.',
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Add at least one slot' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _upi,
              decoration: const InputDecoration(
                labelText: 'Committee UPI ID (e.g. committee@okaxis)',
                helperText: 'Shown to members on the Contributions screen.',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Save settings')),
            const SizedBox(height: 12),
            const Text(
              'Changing the start date does not move existing entries; they stay on the dates they were added.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
