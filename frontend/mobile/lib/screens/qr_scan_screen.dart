import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/sports_app_theme.dart';

/// Full-screen QR / barcode scanner; pops with the first decoded string value.
///
/// On web, [MobileScanner] is not supported; a manual entry fallback is shown.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _handled = false;
  late final TextEditingController _manualCodeController;

  @override
  void initState() {
    super.initState();
    _manualCodeController = TextEditingController();
  }

  @override
  void dispose() {
    _manualCodeController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop<String>(v);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (kIsWeb) {
      return Scaffold(
        backgroundColor: SportsAppColors.background,
        appBar: AppBar(
          title: const Text('Check-in code'),
          backgroundColor: SportsAppColors.background,
        ),
        body: SportsBackground(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Camera scanning is not available on web. Enter a code manually.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: SportsAppColors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _manualCodeController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    prefixIcon: Icon(Icons.tag_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    final v = _manualCodeController.text.trim();
                    if (v.isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop<String>(v);
                  },
                  child: const Text('Submit'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan check-in'),
        backgroundColor: Colors.black.withValues(alpha: 0.6),
      ),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
