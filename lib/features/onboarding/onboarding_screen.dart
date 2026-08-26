import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../core/backend/reader_backend.dart';

/// First-run screen (5f): welcome, then pick a server type to add. There is
/// no separate "step 3" here (a Paperback import flow) - that doesn't exist
/// as an in-app feature yet, so this doesn't pretend it does. "Skip for now"
/// drops straight into the empty home screen, which still explains what to
/// do next.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text('SR',
                    style: AppText.mono(size: 17, weight: FontWeight.w700, color: AppColors.accentSoft)),
              ),
              const SizedBox(height: 24),
              Text('Shaddai Reader', style: AppText.largeTitle(size: 32)),
              const SizedBox(height: 12),
              Text(
                'Everything you read stays on hardware you own. Point it at your '
                'Komga, Kavita, Suwayomi, or OPDS server to get started.',
                style: AppText.body(size: 14, color: AppColors.text60),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 1.55,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: [
                    _SourceCard(
                      type: ServerType.komga,
                      subtitle: 'MANGA + COMICS',
                      onTap: () => _addServer(context, ServerType.komga),
                    ),
                    _SourceCard(
                      type: ServerType.kavita,
                      subtitle: 'COMICS + EPUB',
                      onTap: () => _addServer(context, ServerType.kavita),
                    ),
                    _SourceCard(
                      type: ServerType.suwayomi,
                      subtitle: 'TRACKED SOURCES',
                      onTap: () => _addServer(context, ServerType.suwayomi),
                    ),
                    _SourceCard(
                      type: ServerType.opds,
                      subtitle: 'ANY 1.2 FEED',
                      onTap: () => _addServer(context, ServerType.opds),
                    ),
                  ],
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => context.go('/home'),
                  child: Text('Skip for now',
                      style: AppText.body(size: 13, weight: FontWeight.w600, color: AppColors.accentLink)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addServer(BuildContext context, ServerType type) {
    context.push('/onboarding/add-server', extra: type);
  }
}

class _SourceCard extends StatelessWidget {
  final ServerType type;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceCard({required this.type, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.sourceColor(type.name);
    final label = switch (type) {
      ServerType.komga => 'Komga',
      ServerType.kavita => 'Kavita',
      ServerType.suwayomi => 'Suwayomi',
      ServerType.opds => 'OPDS',
    };
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(label, style: AppText.body(size: 14, weight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: AppText.mono(size: 9.5, color: AppColors.text45)),
            ],
          ),
        ),
      ),
    );
  }
}
