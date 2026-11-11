import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';

enum TeamRegistrationStatus { draft, submitted, reviewed }

typedef TeamRegistrationTarget = ({String teamId, String seasonId});

class RegistrationPlayer {
  const RegistrationPlayer({
    required this.id,
    required this.name,
    required this.jersey,
    this.position,
    this.heightCm,
    this.weightKg,
    this.shortsSize,
    this.vestSize,
    this.shoeSize,
  });

  factory RegistrationPlayer.fromMap(Map<Object?, Object?> data) =>
      RegistrationPlayer(
        id: data['id'] as String,
        name: data['name'] as String,
        jersey: data['jersey'] as String,
        position: data['position'] as String?,
        heightCm: data['heightCm'] as num?,
        weightKg: data['weightKg'] as num?,
        shortsSize: data['shortsSize'] as String?,
        vestSize: data['vestSize'] as String?,
        shoeSize: data['shoeSize'] as String?,
      );

  final String id;
  final String name;
  final String jersey;
  final String? position;
  final num? heightCm;
  final num? weightKg;
  final String? shortsSize;
  final String? vestSize;
  final String? shoeSize;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'jersey': jersey,
    'position': position,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'shortsSize': shortsSize,
    'vestSize': vestSize,
    'shoeSize': shoeSize,
  };

  List<String> get summary => [
    'Jersey $jersey',
    ?position,
    if (heightCm != null) '$heightCm cm',
    if (weightKg != null) '$weightKg kg',
    if (shortsSize != null) 'Shorts $shortsSize',
    if (vestSize != null) 'Vest $vestSize',
    if (shoeSize != null) 'Shoe $shoeSize',
  ];
}

class TeamRegistration {
  TeamRegistration.fromMap(Map<Object?, Object?> data)
    : revision = data['revision'] as int,
      status = TeamRegistrationStatus.values.byName(data['status'] as String),
      players = List.unmodifiable(
        (data['players'] as List).map(
          (player) => RegistrationPlayer.fromMap(player as Map),
        ),
      ),
      canEdit = data['canEdit'] as bool,
      canReview = data['canReview'] as bool;

  final int revision;
  final TeamRegistrationStatus status;
  final List<RegistrationPlayer> players;
  final bool canEdit;
  final bool canReview;
}

class TeamRegistrationRepository {
  TeamRegistrationRepository({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  static String newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<TeamRegistration> load(TeamRegistrationTarget target) =>
      _invoke(target, 'load', const {});

  Future<TeamRegistration> save(
    TeamRegistrationTarget target,
    String action,
    int revision, {
    required String operationId,
    RegistrationPlayer? player,
    String? playerId,
  }) => _invoke(target, action, {
    'expectedRevision': revision,
    'operationId': operationId,
    if (player != null) 'player': player.toMap(),
    'playerId': ?playerId,
  });

  Future<TeamRegistration> _invoke(
    TeamRegistrationTarget target,
    String action,
    Map<String, Object?> arguments,
  ) async {
    final result = await _functions
        .httpsCallable('teamRegistration')
        .call<Map<Object?, Object?>>({
          'schemaVersion': 1,
          'action': action,
          'teamId': target.teamId,
          'seasonId': target.seasonId,
          ...arguments,
        });
    return TeamRegistration.fromMap(result.data);
  }
}

final teamRegistrationRepositoryProvider = Provider(
  (ref) => TeamRegistrationRepository(),
);

final teamRegistrationProvider = FutureProvider.autoDispose
    .family<TeamRegistration, TeamRegistrationTarget>((ref, target) {
      final user = ref.watch(currentUserProvider).valueOrNull;
      if (user == null) throw StateError('Sign in to open team registration.');
      return ref.watch(teamRegistrationRepositoryProvider).load(target);
    });
