import 'package:flutter/material.dart';

import '../library/local_music_library.dart';

/// Shared discovery status for playlist browsing and the multi-select picker.
class PlaylistLibraryState extends StatelessWidget {
  const PlaylistLibraryState({
    super.key,
    required this.library,
    required this.child,
  });
  final LocalMusicLibrary library;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    switch (library.status) {
      case LibraryStatus.idle:
      case LibraryStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case LibraryStatus.denied:
      case LibraryStatus.failed:
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  library.status == LibraryStatus.denied
                      ? 'Allow Music and audio access for Melodify in Android Settings, then try again.'
                      : 'Local music could not be loaded. Please try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => library.load(retry: true),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ),
        );
      case LibraryStatus.ready:
        return child;
    }
  }
}
