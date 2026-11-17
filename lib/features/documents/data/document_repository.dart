import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

class DocumentRepository {
  final AppDatabase db;
  late final AuditService _audit = AuditService(db);
  late final PermissionService _perm = PermissionService(db);
  DocumentRepository(this.db);

  Future<void> _require(String? userId, String permission) async {
    if (userId == null || userId.isEmpty) return;
    if (!await _perm.userHasPermission(userId, permission)) {
      throw StateError('Action non autorisée ($permission)');
    }
  }

  Future<List<DocumentTemplate>> listTemplates({String? docType, String? actorUserId}) async {
    await _require(actorUserId, 'documents.read');
    final q = db.select(db.documentTemplates)..where((t) => t.isDeleted.equals(false));
    if (docType != null && docType.isNotEmpty) q.where((t) => t.docType.equals(docType));
    q.orderBy([(t) => OrderingTerm.asc(t.docType), (t) => OrderingTerm.asc(t.name)]);
    return q.get();
  }

  Future<DocumentTemplate?> getTemplate(String id, {String? actorUserId}) async {
    await _require(actorUserId, 'documents.read');
    return (db.select(db.documentTemplates)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<DocumentTemplate?> defaultTemplate(String docType, {String? actorUserId}) async {
    if (actorUserId != null && actorUserId.isNotEmpty) {
      await _require(actorUserId, 'documents.read');
    }
    final q = db.select(db.documentTemplates)
      ..where((t) => t.isDeleted.equals(false) & t.isActive.equals(true) & t.docType.equals(docType))
      ..orderBy([(t) => OrderingTerm.desc(t.isDefault), (t) => OrderingTerm.asc(t.name)]);
    return q.getSingleOrNull();
  }

  Future<String> upsertTemplate({
    String? id,
    required String name,
    required String docType,
    String pageFormat = 'A4',
    required Map<String, dynamic> content,
    String? description,
    bool isDefault = false,
    bool isActive = true,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId, 'documents.update');
    final tid = id ?? newUuid();
    final now = DateTime.now();
    if (isDefault) {
      // un seul défaut par type
      await (db.update(db.documentTemplates)..where((t) => t.docType.equals(docType)))
          .write(const DocumentTemplatesCompanion(isDefault: Value(false)));
    }
    await db.into(db.documentTemplates).insertOnConflictUpdate(DocumentTemplatesCompanion.insert(
      id: Value(tid),
      name: name,
      docType: docType,
      pageFormat: Value(pageFormat),
      contentJson: Value(jsonEncode(content)),
      description: Value(description),
      isDefault: Value(isDefault),
      isActive: Value(isActive),
      updatedAt: Value(now),
      createdAt: Value(now),
    ));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Document Studio', targetObject: tid, description: 'Modèle document enregistré: $name ($docType)', result: 'Succès');
    return tid;
  }

  Future<void> deleteTemplate(String id, {String? actorUserId, String? actorUsername}) async {
    await _require(actorUserId, 'documents.delete');
    await (db.update(db.documentTemplates)..where((t) => t.id.equals(id)))
        .write(DocumentTemplatesCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Document Studio', targetObject: id, description: 'Modèle document supprimé (corbeille)', result: 'Succès');
  }

  /// Sème les modèles par défaut si absents (ajoute les modèles manquants).
  Future<void> ensureDefaultTemplates() async {
    final existing = await listTemplates();
    final existingIds = existing.map((e) => e.id).toSet();
    final defaults = <Map<String, dynamic>>[
      _tpl('bulletin_default', 'Bulletin de notes (modèle)', 'bulletin', true, {
        'title': 'Bulletin de notes',
        'header': '{{etablissement.nom}}\n{{etablissement.adresse}}',
        'intro': 'Élève : {{eleve.nom}}\nMatricule : {{eleve.matricule}}\nClasse : {{eleve.classe}}\nPériode : {{periode.libelle}}',
        'body': 'Moyenne générale : {{resultats.moyenne}} / 20\nRang : {{resultats.rang}}\nMention : {{resultats.mention}}\nAppréciation : {{resultats.appreciation}}',
        'footer': 'Document généré par Fianarana - {{date.jour}}',
      }),
      _tpl('recu_default', 'Reçu de paiement (modèle)', 'recu', true, {
        'title': 'REÇU DE PAIEMENT',
        'header': '{{etablissement.nom}}',
        'body': 'N° Reçu : {{recu.numero}}\nDate : {{recu.date}}\nÉlève : {{eleve.nom}} ({{eleve.matricule}})\nClasse : {{eleve.classe}}\nLibellé : {{recu.libelle}}\nMontant dû : {{recu.du}} MGA\nMontant payé : {{recu.paye}} MGA\nReste : {{recu.reste}} MGA\nMode : {{recu.mode}}',
        'footer': 'Merci pour votre paiement.',
      }),
      _tpl('certificat_default', 'Certificat de sortie (modèle)', 'certificat', true, {
        'title': 'CERTIFICAT DE RADIATION / SORTIE',
        'header': '{{etablissement.nom}}',
        'body': 'Nous certifions que {{eleve.nom}} ({{eleve.matricule}}), classe {{eleve.classe}}, quitte l\'établissement le {{sortie.date}}.\nMotif : {{sortie.motif}}\nQuitus financier : {{sortie.quitus_finance}}\nQuitus bibliothèque : {{sortie.quitus_bibliotheque}}',
        'footer': 'Fait le {{date.jour}}',
      }),
      _tpl('carte_default', 'Carte scolaire (modèle)', 'carte', true, {
        'title': 'CARTE SCOLAIRE',
        'header': '{{etablissement.nom}}',
        'body': 'Nom : {{eleve.nom}}\nMatricule : {{eleve.matricule}}\nClasse : {{eleve.classe}}\nAnnée : {{annee.libelle}}',
        'footer': 'Document officiel',
      }),
      _tpl('attestation_default', 'Attestation de scolarité (modèle)', 'attestation', true, {
        'title': 'ATTESTATION DE SCOLARITÉ',
        'header': '{{etablissement.nom}}',
        'body': 'Nous attestons que {{eleve.nom}} ({{eleve.matricule}}) est inscrit(e) en classe de {{eleve.classe}} pour l\'année {{annee.libelle}}.',
        'footer': 'Fait le {{date.jour}}',
      }),
      _tpl('attestation_personnel_default', 'Attestation de service - personnel (modèle)', 'attestation_personnel', true, {
        'title': 'ATTESTATION DE SERVICE',
        'header': '{{etablissement.nom}}\n{{etablissement.adresse}}',
        'body': 'Nous attestons que {{personnel.nom}} ({{personnel.matricule}}), exerçant la fonction de {{personnel.fonction}} au sein de {{personnel.departement}}, est en service dans notre établissement pour l\'année {{annee.libelle}}.',
        'footer': 'Fait le {{date.jour}}',
      }),
    ];
    for (final d in defaults) {
      if (existingIds.contains(d['id'] as String)) continue;
      await upsertTemplate(
        id: d['id'] as String,
        name: d['name'] as String,
        docType: d['docType'] as String,
        pageFormat: 'A4',
        content: d['content'] as Map<String, dynamic>,
        description: 'Modèle par défaut',
        isDefault: d['isDefault'] as bool,
      );
    }
  }

  Map<String, dynamic> _tpl(String id, String name, String docType, bool isDefault, Map<String, dynamic> content) => {
        'id': id,
        'name': name,
        'docType': docType,
        'isDefault': isDefault,
        'content': content,
      };
}
