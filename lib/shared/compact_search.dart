import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Shared geometry and focus treatment for home and collection searches.
double compactSearchHeight(BuildContext context) =>
    40 * MediaQuery.textScalerOf(context).scale(14) / 14;

InputDecoration compactSearchDecoration({
  required String hintText,
  Widget? suffixIcon,
}) => InputDecoration(
  hintText: hintText,
  isDense: true,
  filled: true,
  fillColor: Colors.white,
  hintStyle: const TextStyle(fontSize: 14, color: lxMuted),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  prefixIcon: const Icon(Icons.search_rounded, size: 20),
  prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
  suffixIconConstraints: const BoxConstraints.tightFor(width: 40, height: 40),
  suffixIcon: suffixIcon ?? const SizedBox(width: 40, height: 40),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(24),
    borderSide: BorderSide.none,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(24),
    borderSide: BorderSide.none,
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: const BorderSide(color: lxGreen, width: 2),
  ),
);
