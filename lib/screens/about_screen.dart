import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/melodify_theme.dart';
import '../widgets/music_artwork.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<String> _version() async {
    final pubspec = await rootBundle.loadString('pubspec.yaml');
    final match = RegExp(
      r'^version:\s*([^\s#]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    return match?.group(1) ?? 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About Melodify')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
              children: [
                const Center(
                  child: MusicArtwork(
                    size: 104,
                    icon: Icons.graphic_eq_rounded,
                    active: true,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Melodify',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                FutureBuilder<String>(
                  future: _version(),
                  builder: (context, snapshot) => Text(
                    snapshot.hasData ? 'Version ${snapshot.data}' : 'Version',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: context.palette.secondaryText),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'A personal music player for your local music library.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 14),
                Text(
                  'Developed by DMJ Labs',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: context.palette.secondaryText),
                ),
                const SizedBox(height: 44),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: const Text('Open Source Licenses'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Melodify',
                      applicationIcon: const MusicArtwork(
                        size: 48,
                        icon: Icons.graphic_eq_rounded,
                        active: true,
                      ),
                    ),
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
