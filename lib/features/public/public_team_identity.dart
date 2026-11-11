import 'package:flutter/material.dart';
import '../../models/public_league_snapshot.dart';
import '../../core/widgets/sponsor_banner.dart';

const publicSportsCanvas = Color(0xFFF7F9FC);
const publicRoyalGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  stops: [0, 0.34, 0.5, 0.68, 1],
  colors: [
    Color(0xFF16378D),
    Color(0xFF234EBD),
    Color(0xFF6C8BE3),
    Color(0xFF234EBD),
    Color(0xFF184A9E),
  ],
);

ThemeData publicSportsTheme(BuildContext context) {
  final base = Theme.of(context);
  const scheme = ColorScheme.light(
    primary: Color(0xFF234EBD),
    onPrimary: Colors.white,
    secondary: Color(0xFFE7BC5A),
    onSecondary: Color(0xFF0B1D3A),
    surface: Colors.white,
    onSurface: Color(0xFF0B1D3A),
    onSurfaceVariant: Color(0xFF5F6F86),
    outline: Color(0xFFD6DDE7),
  );
  return base.copyWith(
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: publicSportsCanvas,
    canvasColor: publicSportsCanvas,
    cardColor: Colors.white,
    dividerColor: const Color(0xFFE3E8F0),
    textTheme: base.textTheme.apply(
      bodyColor: const Color(0xFF0B1D3A),
      displayColor: const Color(0xFF0B1D3A),
    ),
  );
}

String compactTeamName(String name) {
  const nicknames = [
    'Slayers',
    'Rebels',
    'Celtics',
    'Warriors',
    'Eagles',
    'Knights',
    'Raptors',
    'Flames',
    'Spartans',
    'Wizards',
  ];
  for (final nickname in nicknames) {
    if (name.toLowerCase().endsWith(nickname.toLowerCase())) return nickname;
  }
  return name;
}

class PublicTeamMark extends StatelessWidget {
  const PublicTeamMark({
    super.key,
    required this.snapshot,
    required this.teamId,
    required this.name,
    this.size = 32,
    this.onDarkSurface = false,
  });
  final PublicLeagueSnapshot snapshot;
  final String? teamId;
  final String name;
  final double size;
  final bool onDarkSurface;

  @override
  Widget build(BuildContext context) {
    final logo = snapshot.teams
        .where((t) => t.teamId == teamId)
        .firstOrNull
        ?.logoUrl;
    return SponsorLogo(
      reference: logo,
      width: size,
      height: size,
      semanticLabel: '$name logo',
      onPlate: onDarkSurface || logo == null,
      lightBackground: Theme.of(context).brightness == Brightness.light,
      platePadding: const EdgeInsets.all(2),
    );
  }
}
