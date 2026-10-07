import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models.dart';

/// Thin wrapper over the Firestore collections the app uses.
class Db {
  Db._();

  static FirebaseFirestore get fs => FirebaseFirestore.instance;
  static String get uid => FirebaseAuth.instance.currentUser!.uid;

  static CollectionReference<Map<String, dynamic>> get users => fs.collection('users');
  static CollectionReference<Map<String, dynamic>> get activities => fs.collection('activities');
  static CollectionReference<Map<String, dynamic>> get poojaSignups => fs.collection('poojaSignups');
  static CollectionReference<Map<String, dynamic>> get expenses => fs.collection('expenses');
  static CollectionReference<Map<String, dynamic>> get contributions => fs.collection('contributions');
  static CollectionReference<Map<String, dynamic>> get proofs => fs.collection('proofs');
  static DocumentReference<Map<String, dynamic>> get festival =>
      fs.collection('settings').doc('festival');
  static CollectionReference<Map<String, dynamic>> get settings => fs.collection('settings');
  static DocumentReference<Map<String, dynamic>> eventDoc(String eventId) =>
      settings.doc(settingsDocId(eventId));

  /// Extra events added by admins: settings/eventList {custom: [{id, title}]}.
  static DocumentReference<Map<String, dynamic>> get eventList => settings.doc('eventList');

  /// Fields every created record carries (checked by the security rules).
  static Map<String, dynamic> stamp() => {
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// Stores a compressed JPEG screenshot and returns its id.
  /// Images live in Firestore (base64) so the app runs on the free Spark plan
  /// without Cloud Storage.
  static Future<String> saveProof(Uint8List jpeg) async {
    final ref = proofs.doc();
    await ref.set({
      'image': base64Encode(jpeg),
      'contentType': 'image/jpeg',
      'uploadedBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<Uint8List?> loadProof(String id) async {
    final snap = await proofs.doc(id).get();
    final b64 = snap.data()?['image'];
    if (b64 is! String) return null;
    return base64Decode(b64);
  }

  static Future<void> deleteProof(String? id) async {
    if (id == null || id.isEmpty) return;
    try {
      await proofs.doc(id).delete();
    } catch (_) {
      // Not fatal: the record is gone either way.
    }
  }
}
