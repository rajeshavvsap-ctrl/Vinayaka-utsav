import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Day-wise schedule: pooja timings, aarti, cultural programs, visarjan.
class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({super.key, required this.session});
  final Session session;

  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  late String _day = widget.session.festival.initialDay();

  @override
  Widget build(BuildContext context) {
    final f = widget.session.festival;
    return Scaffold(
      appBar: AppBar(title: const Text('Activities')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Add activity'),
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
              stream: Db.activities.where('date', isEqualTo: _day).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return ErrorHint(snap.error);
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs.toList()
                  ..sort((a, b) => '${a.data()['time']}'.compareTo('${b.data()['time']}'));
                if (docs.isEmpty) {
                  return const EmptyHint(
                      icon: Icons.event_busy_outlined, text: 'No activities planned for this day yet.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: docs.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _row(context, docs[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final a = doc.data();
    final canChange = widget.session.canChange(a);
    final meta = [
      '${a['place'] ?? ''}',
      if ('${a['coordinator'] ?? ''}'.isNotEmpty) 'By ${a['coordinator']}',
    ].where((e) => e.isNotEmpty).join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 74,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(prettyTime('${a['time']}'), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      if (meta.isNotEmpty)
                        Text(meta, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                      if ('${a['notes'] ?? ''}'.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${a['notes']}', style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
                if (canChange)
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (v) async {
                      if (v == 'edit') {
                        _edit(context, doc);
                      } else if (v == 'delete' &&
                          await confirmDialog(context, 'Delete activity?', '${a['title']} will be removed.',
                              ok: 'Delete')) {
                        await doc.reference.delete();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>>? doc) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ActivityForm(session: widget.session, day: _day, doc: doc),
    );
  }
}

class _ActivityForm extends StatefulWidget {
  const _ActivityForm({required this.session, required this.day, this.doc});
  final Session session;
  final String day;
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;

  @override
  State<_ActivityForm> createState() => _ActivityFormState();
}

class _ActivityFormState extends State<_ActivityForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> _a = widget.doc?.data() ?? {};
  late final _title = TextEditingController(text: '${_a['title'] ?? ''}');
  late final _place = TextEditingController(text: '${_a['place'] ?? ''}');
  late final _coord = TextEditingController(text: '${_a['coordinator'] ?? ''}');
  late final _notes = TextEditingController(text: '${_a['notes'] ?? ''}');
  late String _date = '${_a['date'] ?? widget.day}';
  late TimeOfDay _time = _parseTime('${_a['time'] ?? '18:00'}');
  bool _busy = false;

  static TimeOfDay _parseTime(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.tryParse(p.first) ?? 18, minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  String get _timeKey => '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _coord.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final data = {
      'date': _date,
      'time': _timeKey,
      'title': _title.text.trim(),
      'place': _place.text.trim(),
      'coordinator': _coord.text.trim(),
      'notes': _notes.text.trim(),
    };
    try {
      if (widget.doc == null) {
        await Db.activities.add({...data, ...Db.stamp()});
      } else {
        await widget.doc!.reference.update(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Could not save: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.session.festival;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.doc == null ? 'New activity' : 'Edit activity', style: display(22)),
              const SizedBox(height: 14),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'What (e.g. Evening Maha Aarti)'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a title' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: f.dayKeys.contains(_date) ? _date : f.dayKeys.first,
                      decoration: const InputDecoration(labelText: 'Day'),
                      items: [
                        for (final k in f.dayKeys)
                          DropdownMenuItem(value: k, child: Text('Day ${f.dayNumber(k)} · ${shortDay(k)}')),
                      ],
                      onChanged: (v) => setState(() => _date = v ?? _date),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        final t = await showTimePicker(context: context, initialTime: _time);
                        if (t != null) setState(() => _time = t);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Time', suffixIcon: Icon(Icons.schedule)),
                        child: Text(prettyTime(_timeKey)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _place,
                decoration: const InputDecoration(labelText: 'Place (e.g. Pandal stage)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _coord,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Coordinator / team'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}
