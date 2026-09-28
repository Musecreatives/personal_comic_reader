import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';

/// Things you can do to a series beyond reading it: stop following it, clear
/// its downloads from this device, (Suwayomi) drop it from the library, or
/// (imported comics) edit its details.
/// Anything that destroys something asks first, and says exactly what goes.
class SeriesActionsSheet {
  static Future<void> show(
    BuildContext context, {
    required String title,
    required int downloadedCount,
    required bool canRemoveFromLibrary,
    required Future<void> Function() onStopReading,
    required Future<void> Function() onDeleteDownloads,
    required Future<void> Function() onRemoveFromLibrary,
    Future<void> Function()? onEditDetails,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: Motion.sheetStyle,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        Future<void> confirmThen({
          required String heading,
          required String body,
          required String action,
          required Future<void> Function() run,
        }) async {
          final ok = await showDialog<bool>(
            context: sheetContext,
            builder: (d) => AlertDialog(
              backgroundColor: AppColors.card,
              title: Text(heading),
              content: Text(body),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: Text(
                    action,
                    style: TextStyle(color: AppColors.dangerText),
                  ),
                ),
              ],
            ),
          );
          if (ok == true && sheetContext.mounted) {
            Navigator.pop(sheetContext);
            await run();
          }
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.text30,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.heading(size: 18),
                ),
              ),
              if (onEditDetails != null)
                _Action(
                  icon: Icons.edit_outlined,
                  title: 'Edit details',
                  hint: 'Title, summary, credits, publisher, year, genres',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await onEditDetails();
                  },
                ),
              _Action(
                icon: Icons.visibility_off_outlined,
                title: 'Stop reading',
                hint: 'Hide it from Home until you read it again',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await onStopReading();
                },
              ),
              _Action(
                icon: Icons.delete_outline_rounded,
                title: 'Delete downloads',
                hint: downloadedCount == 0
                    ? 'Nothing downloaded to this device'
                    : '$downloadedCount chapters on this device',
                enabled: downloadedCount > 0,
                destructive: true,
                onTap: () => confirmThen(
                  heading: 'Delete downloads?',
                  body:
                      'This removes $downloadedCount downloaded chapters of "$title" from this device. Nothing on the server changes, and you can download them again.',
                  action: 'Delete',
                  run: onDeleteDownloads,
                ),
              ),
              if (canRemoveFromLibrary)
                _Action(
                  icon: Icons.bookmark_remove_outlined,
                  title: 'Remove from library',
                  hint: 'Stops following it. Chapters are not deleted.',
                  destructive: true,
                  onTap: () => confirmThen(
                    heading: 'Remove from library?',
                    body:
                        '"$title" will leave your Library and updates. You can add it again from Browse sources.',
                    action: 'Remove',
                    run: onRemoveFromLibrary,
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final bool enabled;
  final bool destructive;
  final VoidCallback onTap;
  const _Action({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.dangerText : AppColors.text;
    return PressScale(
      scale: 0.985,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppText.body(
                          size: 15,
                          weight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        hint,
                        style: AppText.body(size: 12, color: AppColors.text45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
