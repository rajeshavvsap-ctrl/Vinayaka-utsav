import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 'github' for the APK shared by link, 'play' for the Play Store build.
/// Set at build time with --dart-define=CHANNEL=...
const _channel = String.fromEnvironment('CHANNEL', defaultValue: 'github');
const _repo = 'rajeshavvsap-ctrl/Vinayaka-utsav';
const apkDownloadUrl = 'https://github.com/$_repo/releases/latest/download/vinayaka-utsav.apk';

bool _checked = false;

/// Runs once per app start. If a newer version exists, asks the user to update.
Future<void> checkForUpdate(BuildContext context) async {
  if (_checked || !Platform.isAndroid) return;
  _checked = true;
  try {
    if (_channel == 'play') {
      // Google Play shows its own update screen.
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate();
      }
      return;
    }

    final pkg = await PackageInfo.fromPlatform();
    final current = int.tryParse(pkg.buildNumber) ?? 0;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'));
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('User-Agent', 'vinayaka-utsav-app');
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    client.close();
    if (res.statusCode != 200) return;

    final body = jsonDecode(text) as Map<String, dynamic>;
    final latest = int.tryParse('${body['tag_name'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (latest <= current || !context.mounted) return;

    final notes = '${body['body'] ?? ''}'
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('What\'s new:'))
        .map((l) => l.substring('What\'s new:'.length).trim())
        .join();

    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.system_update, size: 36, color: Color(0xFF7A1F1F)),
        title: const Text('Update available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A new version (build $latest) is ready. You have build $current.'),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('What\'s new: $notes', style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 10),
            const Text('Your data is safe; nothing is lost when you update.',
                style: TextStyle(fontSize: 13, color: Color(0xFF7A5A50))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Update now'),
          ),
        ],
      ),
    );
    if (go == true) {
      await launchUrl(Uri.parse(apkDownloadUrl), mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    // No internet or API limit: try again next time the app opens.
  }
}
