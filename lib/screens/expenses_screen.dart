import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../services/proof_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.session});
  final Session session;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String _cat = 'All';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => AddExpenseScreen(session: widget.session))),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.expenses.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return LoadErrorView(snap.error);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!.docs.toList()
            ..sort((a, b) {
              final byDate = '${b.data()['date']}'.compareTo('${a.data()['date']}');
              if (byDate != 0) return byDate;
              final ta = a.data()['createdAt'], tb = b.data()['createdAt'];
              if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
              return 0;
            });
          final shown = _cat == 'All' ? all : all.where((d) => d.data()['category'] == _cat).toList();
          final total = shown.fold<num>(0, (s, d) => s + toNum(d.data()['amount']));
          final usedCats = {for (final d in all) '${d.data()['category']}'};

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              AppCard(
                color: AppColors.maroon,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_cat == 'All' ? 'Total spent' : 'Spent on $_cat',
                              style: const TextStyle(color: AppColors.gold, fontSize: 13)),
                          Text(rupees(total), style: display(28, color: Colors.white)),
                        ],
                      ),
                    ),
                    Text('${shown.length} bills', style: const TextStyle(color: Color(0xFFF3DCCB))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in ['All', ...expenseCategories.where(usedCats.contains)])
                    ChoiceChip(
                      label: Text(c),
                      selected: _cat == c,
                      showCheckmark: false,
                      labelStyle: TextStyle(color: _cat == c ? Colors.white : AppColors.ink),
                      onSelected: (_) => setState(() => _cat = c),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                const EmptyHint(icon: Icons.receipt_long_outlined, text: 'No expenses yet. Tap "Add expense".'),
              for (final d in shown) ...[
                _row(context, d),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final e = doc.data();
    final hasProof = '${e['proofId'] ?? ''}'.isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => _detail(context, doc),
      child: Row(
        children: [
          IconBadge(icon: _catIcon('${e['category']}'), bg: AppColors.redBg, fg: AppColors.maroon, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${e['item']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text('${shortDay('${e['date']}')} · Paid by ${e['paidBy']}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
          if (hasProof)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.image_outlined, size: 18, color: AppColors.muted, semanticLabel: 'Has bill'),
            ),
          Text(rupees(toNum(e['amount'])), style: display(17)),
        ],
      ),
    );
  }

  Future<void> _detail(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final e = doc.data();
    final proofId = '${e['proofId'] ?? ''}';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: proofId.isEmpty ? 0.5 : 0.8,
        maxChildSize: 0.95,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('${e['item']}', style: display(22)),
            Text(rupees(toNum(e['amount'])), style: display(28, color: AppColors.maroon)),
            const SizedBox(height: 10),
            DetailRow('Category', '${e['category']}'),
            DetailRow('Date', prettyDay('${e['date']}')),
            DetailRow('Paid by', '${e['paidBy']}'),
            DetailRow('Mode', '${e['mode'] ?? ''}'),
            DetailRow('Note', '${e['note'] ?? ''}'),
            const SizedBox(height: 12),
            if (proofId.isNotEmpty) ProofImage(proofId: proofId, height: 320),
            if (widget.session.canChange(e)) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await confirmDialog(c, 'Delete expense?', '${e['item']} will be removed.', ok: 'Delete')) {
                    await doc.reference.delete();
                    await Db.deleteProof(proofId);
                    if (c.mounted) Navigator.pop(c);
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete expense'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _catIcon(String c) {
    switch (c) {
      case 'Idol':
        return Icons.temple_hindu_outlined;
      case 'Pandal':
        return Icons.storefront_outlined;
      case 'Flowers':
      case 'Pooja items':
        return Icons.local_florist_outlined;
      case 'Prasadam / Food':
        return Icons.restaurant_outlined;
      case 'Sound & Lights':
        return Icons.speaker_outlined;
      case 'Decoration':
        return Icons.celebration_outlined;
      case 'Visarjan':
        return Icons.waves;
      default:
        return Icons.receipt_outlined;
    }
  }
}

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key, required this.session});
  final Session session;

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _form = GlobalKey<FormState>();
  final _item = TextEditingController();
  final _amount = TextEditingController();
  late final _paidBy = TextEditingController(text: widget.session.me.name);
  final _note = TextEditingController();
  String _category = expenseCategories.first;
  String _mode = paymentModes.first;
  late String _day = widget.session.festival.initialDay();
  Uint8List? _proof;
  bool _busy = false;

  @override
  void dispose() {
    _item.dispose();
    _amount.dispose();
    _paidBy.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      String? proofId;
      if (_proof != null) proofId = await Db.saveProof(_proof!);
      await Db.expenses.add({
        'item': _item.text.trim(),
        'amount': num.parse(_amount.text.trim()),
        'category': _category,
        'mode': _mode,
        'paidBy': _paidBy.text.trim(),
        'note': _note.text.trim(),
        'date': _day,
        'proofId': proofId,
        ...Db.stamp(),
      });
      if (mounted) {
        toast(context, 'Expense added');
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
      appBar: AppBar(title: const Text('Add expense')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _item,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Item (e.g. Flowers & garlands)'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter what was bought' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
              validator: amountValidator,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final c in expenseCategories) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 12),
            FestivalDayField(
              label: 'Date',
              festival: widget.session.festival,
              value: _day,
              onChanged: (d) => setState(() => _day = d),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _paidBy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Paid by'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Who paid?' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _mode,
              decoration: const InputDecoration(labelText: 'Payment mode'),
              items: [for (final m in paymentModes) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => _mode = v ?? _mode),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 16),
            ProofField(
              label: 'Attach bill / payment screenshot',
              bytes: _proof,
              onPick: () async {
                final b = await pickProof(context);
                if (b != null) setState(() => _proof = b);
              },
              onClear: () => setState(() => _proof = null),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Save expense'),
            ),
          ],
        ),
      ),
    );
  }
}
