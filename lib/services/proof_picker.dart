import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Max stored size per screenshot (Firestore documents are capped at 1 MiB,
/// and base64 adds ~33%).
const _maxBytes = 600 * 1024;

Uint8List? _compress(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = decoded.width > 900 ? img.copyResize(decoded, width: 900) : decoded;
  var quality = 70;
  var out = img.encodeJpg(resized, quality: quality);
  while (out.length > _maxBytes && quality > 25) {
    quality -= 15;
    out = img.encodeJpg(resized, quality: quality);
  }
  return out.length > _maxBytes ? null : out;
}

/// Lets the user pick a payment screenshot or photograph a bill.
/// Returns compressed JPEG bytes, or null if cancelled / unreadable.
Future<Uint8List?> pickProof(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose screenshot from gallery'),
            onTap: () => Navigator.pop(c, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo of bill / receipt'),
            onTap: () => Navigator.pop(c, ImageSource.camera),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null) return null;

  final file = await ImagePicker().pickImage(source: source);
  if (file == null) return null;
  final raw = await file.readAsBytes();
  final out = await compute(_compress, raw);
  if (out == null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not read that image. Try cropping it or pick another.')),
    );
  }
  return out;
}
