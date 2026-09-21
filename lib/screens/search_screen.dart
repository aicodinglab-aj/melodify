import 'package:flutter/material.dart';

import '../theme/melodify_colors.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            Text(
              'Find your next favorite sound.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            const TextField(
              decoration: InputDecoration(
                hintText: 'What do you want to listen to?',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 28),
            Text('Browse all', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final singleColumn =
                    constraints.maxWidth < 280 ||
                    MediaQuery.textScalerOf(context).scale(14) > 22;
                final width = singleColumn
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 14) / 2;
                const categories = [
                  _CategoryCard(
                    title: 'Pop',
                    colors: MelodifyColors.pinkArtwork,
                    icon: Icons.auto_awesome_rounded,
                  ),
                  _CategoryCard(
                    title: 'Rock',
                    colors: MelodifyColors.duskArtwork,
                    icon: Icons.bolt_rounded,
                  ),
                  _CategoryCard(
                    title: 'Chill',
                    colors: MelodifyColors.blueArtwork,
                    icon: Icons.waves_rounded,
                  ),
                  _CategoryCard(
                    title: 'Workout',
                    colors: MelodifyColors.greenArtwork,
                    icon: Icons.graphic_eq_rounded,
                  ),
                ];
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final category in categories)
                      SizedBox(width: width, child: category),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.title,
    required this.colors,
    required this.icon,
  });

  final String title;
  final List<Color> colors;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Container(
          color: const Color(0xFF121212).withValues(alpha: 0.4),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 26),
              Align(
                alignment: Alignment.centerRight,
                child: ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: 44,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
