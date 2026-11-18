import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';

/// Informations d'en-tête utilisées par les documents imprimés
/// (reçus, bulletins, certificats, modèles Document Studio).
class EstablishmentInfo {
  final String id;
  final String code;
  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final String? logoPath;
  final String? motto;
  final String currency;
  final String? legalMentions;

  const EstablishmentInfo({
    required this.id,
    required this.code,
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.logoPath,
    this.motto,
    this.currency = 'MGA',
    this.legalMentions,
  });

  static const fallback = EstablishmentInfo(
    id: '',
    code: '',
    name: 'Établissement scolaire',
  );

  /// Contexte exploitable par le moteur de modèles Document Studio.
  Map<String, dynamic> toTemplateContext() => {
        'nom': name,
        'adresse': address ?? '',
        'telephone': phone ?? '',
        'email': email ?? '',
        'devise': currency,
        'mentions_legales': legalMentions ?? '',
        'devise_affichage': currency,
      };
}

class EstablishmentService {
  final AppDatabase db;
  EstablishmentService(this.db);

  Future<EstablishmentInfo?> current() async {
    final row = await (db.select(db.establishments)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return EstablishmentInfo(
      id: row.id,
      code: row.code,
      name: row.name,
      address: row.address,
      phone: row.phone,
      email: row.email,
      logoPath: row.logoPath,
      motto: row.motto,
      currency: row.currency,
      legalMentions: row.legalMentions,
    );
  }

  Future<EstablishmentInfo> currentOrDefault() async {
    return await current() ?? EstablishmentInfo.fallback;
  }

  Future<String> save({
    String? id,
    required String name,
    String? code,
    String? address,
    String? phone,
    String? email,
    String? logoPath,
    String? motto,
    String? currency,
    String? legalMentions,
    String? status,
  }) async {
    final now = DateTime.now();
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Le nom de l\'établissement est obligatoire.');
    }
    if (id == null || id.isEmpty) {
      final existing = await current();
      if (existing != null) {
        return save(
          id: existing.id,
          name: trimmedName,
          code: code,
          address: address,
          phone: phone,
          email: email,
          logoPath: logoPath,
          motto: motto,
          currency: currency,
          legalMentions: legalMentions,
          status: status,
        );
      }
      final newId = AppDatabase.ensureId(null);
      await db.into(db.establishments).insert(EstablishmentsCompanion.insert(
        id: Value(newId),
        code: (code == null || code.trim().isEmpty) ? 'ETAB-01' : code.trim(),
        name: trimmedName,
        address: Value(address),
        phone: Value(phone),
        email: Value(email),
        logoPath: Value(logoPath),
        motto: Value(motto),
        currency: Value(currency ?? 'MGA'),
        legalMentions: Value(legalMentions),
        status: Value(status ?? 'Actif'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      return newId;
    }
    await (db.update(db.establishments)..where((t) => t.id.equals(id))).write(
      EstablishmentsCompanion(
        code: code == null || code.trim().isEmpty ? const Value.absent() : Value(code.trim()),
        name: Value(trimmedName),
        address: Value(address),
        phone: Value(phone),
        email: Value(email),
        logoPath: Value(logoPath),
        motto: Value(motto),
        currency: Value(currency ?? 'MGA'),
        legalMentions: Value(legalMentions),
        status: Value(status ?? 'Actif'),
        updatedAt: Value(now),
      ),
    );
    return id;
  }
}

final establishmentServiceProvider = Provider<EstablishmentService>((ref) {
  return EstablishmentService(ref.watch(appDatabaseProvider));
});

final establishmentProvider = FutureProvider<EstablishmentInfo>((ref) async {
  return ref.watch(establishmentServiceProvider).currentOrDefault();
});

final establishmentInfoProvider = FutureProvider<EstablishmentInfo>((ref) async {
  return ref.watch(establishmentServiceProvider).currentOrDefault();
});
