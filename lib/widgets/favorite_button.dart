import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../library/favorites.dart';
import '../theme/melodify_theme.dart';

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.favorites,
    required this.song,
  });

  final Favorites favorites;
  final SongModel song;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: favorites,
    builder: (context, _) {
      final liked = favorites.isLiked(song);
      return IconButton(
        tooltip: liked ? 'Unlike ${song.title}' : 'Like ${song.title}',
        isSelected: liked,
        icon: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        ),
        color: liked ? context.palette.primary : context.palette.secondaryText,
        onPressed: () async {
          await favorites.toggle(song);
          if (!context.mounted || favorites.storageAvailable) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Favorites could not be saved. Changes are available for this session.',
              ),
            ),
          );
        },
      );
    },
  );
}
