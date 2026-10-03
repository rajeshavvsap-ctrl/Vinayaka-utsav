import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/db.dart';
import '../services/proof_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Member contributions (chanda). A member pays by UPI/cash/bank, uploads
/// the payment screenshot, and an admin verifies it before it counts in the
/// "Collected" total.
class ContributionsScreen extends StatefulWidget {
  const ContributionsScreen({super.key, required this.session});
  final Session session;

  @override
  State<ContributionsScreen> createState() => _ContributionsScreenState();
}

class _ContributionsScreenState extends State<ContributionsScreen> {
  String _filter = 'All';
  static const _filters = ['All', 'Pending', 'Verified', 'Mine'];

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Contributions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddContributionScreen(session: s))),
        icon: const Icon(Icons.add),
        label: const Text('I have paid'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.contributions.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return ErrorHint(snap.error);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!.docs.toList()
            ..sort((a, b) {
              // Pending first, then newest date.
              final pa = a.data()['status'] == 'pending' ? 0 : 1;
              final pb = b.data()['status'] == 'pending' ? 0 : 1;
              if (pa != pb) return pa - pb;
              return '${b.data()['date']}'.compareTo('${a.data()['date']}');
            });
          num verified = 0, pending = 0;
          for (final d in all) {
            final m = d.data();
            if (m['status'] == 'verified') verified += toNum(m['amount']);
            if (m['status'] == 'pending') pending += toNum(m['amount']);
          }
          final shown = all.where((d) {
            final m = d.data();
            switch (_filter) {
              case 'Pending':
                return m['status'] == 'pending';
              case 'Verified':
                return m['status'] == 'verified';
              case 'Mine':
                return m['createdBy'] == s.me.id;
              default:
                return true;
            }
          }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              AppCard(
                color: AppColors.maroon,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Collected (verified)', style: TextStyle(color: AppColors.gold, fontSize: 13)),
                    Text(rupees(verified), style: display(28, color: Colors.white)),
                    if (pending > 0)
                      Text('${rupees(pending)} waiting for verification',
                          style: const TextStyle(color: Color(0xFFF3DCCB), fontSize: 13)),
                  ],
                ),
              ),
              if (s.festival.upiId.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    children: [
                      const IconBadge(
                          icon: Icons.qr_code_2, bg: AppColors.purpleBg, fg: AppColors.purple, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pay committee UPI', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                            Text(s.festival.upiId,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy UPI ID',
                        icon: const Icon(Icons.copy_outlined),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: s.festival.upiId));
                          toast(context, 'UPI ID copied. Pay in GPay / PhonePe / Paytm.');
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in _filters)
                    ChoiceChip(
                      label: Text(f),
                      selected: _filter == f,
                      showCheckmark: false,
                      labelStyle: TextStyle(color: _filter == f ? Colors.white : AppColors.ink),
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                const EmptyHint(
                    icon: Icons.volunteer_activism_outlined,
                    text: 'No contributions here yet.\nAfter paying, tap "I have paid" and share the screenshot.'),
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
    final c = doc.data();
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => _detail(context, doc),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: AppColors.purpleBg,
            child: Text(
              '${c['name']}'.isNotEmpty ? '${c['name']}'[0].toUpperCase() : '?',
              style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text('${shortDay('${c['date']}')} · ${c['mode']}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(rupees(toNum(c['amount'])), style: display(17)),
              StatusPill.forStatus('${c['status']}'),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _detail(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final c = doc.data();
    final s = widget.session;
    final proofId = '${c['proofId'] ?? ''}';
    final pending = c['status'] == 'pending';
    final canDelete = s.isAdmin || (c['createdBy'] == s.me.id && pending);

    Future<void> setStatus(BuildContext sheet, String status) async {
      try {
        await doc.reference.update({
          'status': status,
          'verifiedBy': s.me.id,
          'verifiedByName': s.me.name,
          'verifiedAt': FieldValue.serverTimestamp(),
        });
        if (sheet.mounted) Navigator.pop(sheet);
      } catch (e) {
        if (sheet.mounted) toast(sheet, 'Could not update: $e');
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: proofId.isEmpty ? 0.55 : 0.85,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Expanded(child: Text('${c['name']}', style: display(22))),
                StatusPill.forStatus('${c['status']}'),
              ],
            ),
            Text(rupees(toNum(c['amount'])), style: display(28, color: AppColors.maroon)),
            const SizedBox(height: 10),
            DetailRow('Date', prettyDay('${c['date']}')),
            DetailRow('Mode', '${c['mode']}'),
            DetailRow('UPI / Txn ref', '${c['txnRef'] ?? ''}'),
            DetailRow('Note', '${c['note'] ?? ''}'),
            if (!pending) DetailRow(c['status'] == 'verified' ? 'Verified by' : 'Checked by', '${c['verifiedByName'] ?? ''}'),
            const SizedBox(height: 12),
            if (proofId.isNotEmpty)
              ProofImage(proofId: proofId, height: 340)
            else
              const Text('No screenshot attached.', style: TextStyle(color: AppColors.muted)),
            if (s.isAdmin && pending) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setStatus(sheet, 'rejected'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, minimumSize: const Size(0, 52)),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => setStatus(sheet, 'verified'),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Verify payment'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                    ),
                  ),
                ],
              ),
            ],
            if (s.isAdmin && !pending) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => doc.reference.update({'status': 'pending'}).then((_) {
                  if (sheet.mounted) Navigator.pop(sheet);
                }),
                child: const Text('Move back to pending'),
              ),
            ],
            if (canDelete) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await confirmDialog(sheet, 'Delete entry?', 'This contribution entry will be removed.',
                      ok: 'Delete')) {
                    await doc.reference.delete();
                    await Db.deleteProof(proofId);
                    if (sheet.mounted) Navigator.pop(sheet);
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete entry'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AddContributionScreen extends StatefulWidget {
  const AddContributionScreen({super.key, required this.session});
  final Session session;

  @override
  State<AddContributionScreen> createState() => _AddContributionScreenState();
}

class _AddContributionScreenState extends State<AddContributionScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.session.me.name);
  final _amount = TextEditingController();
  final _txn = TextEditingController();
  final _note = TextEditingController();
  String _mode = paymentModes.first;
  DateTime _date = DateTime.now();
  Uint8List? _proof;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _txn.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _needsProof => _mode != 'Cash';

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_needsProof && _proof == null) {
      toast(context, 'Please attach the payment screenshot.');
      return;
    }
    setState(() => _busy = true);
    try {
      String? proofId;
      if (_proof != null) proofId = await Db.saveProof(_proof!);
      await Db.contributions.add({
        'name': _name.text.trim(),
        'amount': num.parse(_amount.text.trim()),
        'mode': _mode,
        'txnRef': _txn.text.trim(),
        'note': _note.text.trim(),
        'date': dayKey(_date),
        'proofId': proofId,
        'status': 'pending',
        ...Db.stamp(),
      });
      if (mounted) {
        toast(context, 'Thank you! An admin will verify your payment.');
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
    final upi = widget.session.festival.upiId;
    return Scaffold(
      appBar: AppBar(title: const Text('Share payment')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (upi.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text('1. Pay to UPI ID $upi\n2. Fill the amount and attach the screenshot below.',
                    style: const TextStyle(color: AppColors.muted)),
              ),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Contributor name (person or family)'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount paid', prefixText: '₹ '),
              validator: amountValidator,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _mode,
              decoration: const InputDecoration(labelText: 'Paid by'),
              items: [for (final m in paymentModes) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => _mode = v ?? _mode),
            ),
            const SizedBox(height: 12),
            DateField(label: 'Payment date', value: _date, onChanged: (d) => setState(() => _date = d)),
            const SizedBox(height: 12),
            if (_mode != 'Cash') ...[
              TextFormField(
                controller: _txn,
                decoration: const InputDecoration(labelText: 'UPI ref / transaction ID (optional)'),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 16),
            ProofField(
              label: _needsProof ? 'Attach payment screenshot (required)' : 'Attach receipt photo (optional)',
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
                  : const Text('Submit for verification'),
            ),
          ],
        ),
      ),
    );
  }
}
