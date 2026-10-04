/// Shared notice banner: 16px icon + 12sp text, amber by default.
/// Unifies the stale-data banner, the missing-permissions banner, and the
/// history cap warning tile — one row pattern, two container styles.
library;

import 'package:flutter/material.dart';

const kNoticeAmberBg = Color(0xFFFFF3CD);
const kNoticeAmberFg = Color(0xFF664D03);

class NoticeBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Text line limit: 2 for the fixed header banners; the in-list card
  /// tile passes null so the whole warning is always visible.
  final int? maxLines;

  /// When true, renders as a Card floating in a scrolling list (the cap
  /// warning tile); otherwise as a full-bleed banner (stale/permissions).
  final bool card;

  const NoticeBanner({
    super.key,
    required this.icon,
    required this.text,
    this.background = kNoticeAmberBg,
    this.foreground = kNoticeAmberFg,
    this.onTap,
    this.trailing,
    this.maxLines = 2,
    this.card = false,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Icon(icon, size: 16, color: foreground),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: foreground, fontSize: 12),
            maxLines: maxLines,
            overflow:
                maxLines == null ? null : TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
    final Widget body = card
        ? Card(
            color: background,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: row,
            ),
          )
        : Container(
            width: double.infinity,
            color: background,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: row,
          );
    if (onTap == null) return body;
    return InkWell(onTap: onTap, child: body);
  }
}
