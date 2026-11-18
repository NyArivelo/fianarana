import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/core/database/seed_importer.dart';
import 'package:fianarana/core/theme/app_theme.dart';
import 'package:fianarana/features/attendance/presentation/attendance_screen.dart';
import 'package:fianarana/features/discipline/presentation/discipline_screen.dart';
import 'package:fianarana/features/facilities/presentation/facilities_screen.dart';
import 'package:fianarana/features/facilities/presentation/facility_operations_screen.dart';
import 'package:fianarana/features/finance/presentation/fee_catalog_screen.dart';
import 'package:fianarana/features/finance/presentation/finance_screen.dart';
import 'package:fianarana/features/finance/presentation/ledger_screen.dart';
import 'package:fianarana/features/grades/presentation/grades_screen.dart';
import 'package:fianarana/features/library/presentation/library_screen.dart';
import 'package:fianarana/features/settings/presentation/settings_screen.dart';
import 'package:fianarana/features/settings/presentation/structure_settings_screen.dart';

/// Vérification de rendu des modules métier sur une base de test complète.
///
/// Ces tests détectent les erreurs de layout (débordements, contraintes non
/// bornées) et les exceptions de chargement sans lancer l'application Windows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('les modules métier se rendent avec les données de test',
      (tester) async {
    late AppDatabase db;
    await tester.runAsync(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await SeedImporter(db).importAll();
    });
    addTearDown(db.close);

    await tester.binding.setSurfaceSize(const Size(1040, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    Future<void> settleDb() async {
      // Drift exécute les requêtes hors de la zone de temps simulé du test :
      // on laisse l'event loop réel progresser puis on redessine.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 120)));
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    Future<void> pumpScreen(Widget screen) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: screen,
          ),
        ),
      );
      await settleDb();
    }

    await pumpScreen(const LibraryScreen());
    expect(find.text('Bibliothèque & Quitus'), findsOneWidget);
    expect(find.text('OUVRAGES'), findsOneWidget);
    expect(find.text('Prêts & retards'), findsOneWidget);
    expect(find.text('Quitus élèves'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpScreen(const FacilitiesScreen());
    expect(find.text('Locaux & équipements'), findsOneWidget);
    expect(find.text('Nouveau local'), findsOneWidget);
    expect(find.textContaining('Salle B101'), findsWidgets);
    expect(tester.takeException(), isNull);

    await pumpScreen(const AttendanceScreen());
    expect(find.text('Présences & Discipline'), findsOneWidget);
    expect(find.text('Faire l\'appel'), findsWidgets);
    expect(find.text('PRÉSENTS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpScreen(const GradesScreen());
    expect(find.text('Évaluations & Notes'), findsOneWidget);
    expect(find.text('Nouvelle note'), findsOneWidget);
    expect(find.text('MOYENNE PONDÉRÉE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpScreen(const FinanceScreen());
    expect(find.text('Finances & Caisse'), findsOneWidget);
    expect(find.text('TOTAL ENCAISSÉ'), findsOneWidget);
    expect(find.textContaining('Journal de caisse'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpScreen(const LedgerScreen());
    expect(find.text('Grand livre comptable'), findsOneWidget);
    expect(find.text('Écritures de compte élève'), findsOneWidget);
    expect(find.text('BRUT DÛ'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpScreen(const SettingsScreen());
    expect(find.text('Paramètres & administration'), findsOneWidget);
    expect(find.text('Données de test'), findsOneWidget);
    expect(find.text('Journal d\'audit'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpScreen(const DisciplineScreen());
    expect(find.text('Discipline & suivi des sanctions'), findsOneWidget);
    expect(find.text('Ouvrir un dossier'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpScreen(const FeeCatalogScreen());
    expect(find.text('Catalogue de frais & remises'), findsOneWidget);
    expect(find.text('Grille tarifaire'), findsWidgets);
    expect(find.text('Bourses & remises'), findsWidgets);
    expect(tester.takeException(), isNull);

    await pumpScreen(const StructureSettingsScreen());
    expect(find.text('Établissement & structure pédagogique'), findsOneWidget);
    expect(find.text('Établissement'), findsWidgets);
    expect(find.text('Années & périodes'), findsWidgets);
    expect(tester.takeException(), isNull);

    await pumpScreen(const FacilityOperationsScreen());
    expect(find.text('Réservations & maintenance'), findsOneWidget);
    expect(find.text('Réservations'), findsWidgets);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
