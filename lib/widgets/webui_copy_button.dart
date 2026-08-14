import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trayforge/widgets/copy_snackbar.dart';
import 'package:url_launcher/url_launcher.dart';

/// WebUI URL button with dual actions: left-click copies the URL to the
/// clipboard, right-click opens it in the default browser.
///
/// Right-click never reaches [IconButton.onPressed], so the open-in-browser
/// behaviour is wired through a wrapping [GestureDetector]'s secondary tap.
class WebUiCopyButton extends StatelessWidget {
  /// The WebUI URL to copy / open.
  final Uri url;

  /// Compact presentation (smaller icon, dense hit target) for card headers.
  final bool compact;

  const WebUiCopyButton({super.key, required this.url, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTap: () {
        // Fire-and-forget: opening the browser needs no completion handling.
        unawaited(launchUrl(url, mode: LaunchMode.externalApplication));
      },
      child: IconButton(
        icon: Icon(Icons.content_copy, size: compact ? 20 : null),
        tooltip: 'Copy WebUI URL (right-click: open in browser)',
        onPressed: () {
          Clipboard.setData(ClipboardData(text: url.toString()));
          showCopySnackBar(context);
        },
        visualDensity: compact ? VisualDensity.compact : null,
      ),
    );
  }
}
