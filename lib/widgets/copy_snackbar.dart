import 'package:flutter/material.dart';

/// Shows a compact floating snackbar confirming a clipboard copy.
void showCopySnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('URL copied'),
      duration: const Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
      width: 160,
    ),
  );
}
