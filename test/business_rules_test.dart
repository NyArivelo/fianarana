import 'package:flutter_test/flutter_test.dart';

import 'package:fianarana/features/discipline/data/discipline_repository.dart';
import 'package:fianarana/features/facilities/data/facilities_repository.dart';
import 'package:fianarana/features/finance/data/fee_repository.dart';

void main() {
  group('Calcul du net à payer', () {
    test('déduit remise, bourse et avoir', () {
      expect(
        computeNetDue(
          amountDueMga: 600000,
          discountMga: 50000,
          scholarshipMga: 100000,
          creditNoteMga: 25000,
        ),
        425000,
      );
    });

    test('le net ne peut pas être négatif', () {
      expect(
        computeNetDue(amountDueMga: 10000, discountMga: 20000),
        0,
      );
    });

    test('ignore les valeurs négatives', () {
      expect(
        computeNetDue(amountDueMga: 100000, discountMga: -5000, scholarshipMga: 10000),
        90000,
      );
    });

    test('pourcentage de remise borné à 100%', () {
      expect(computePercentDiscount(amountMga: 200000, percent: 25), 50000);
      expect(computePercentDiscount(amountMga: 200000, percent: 150), 200000);
      expect(computePercentDiscount(amountMga: 200000, percent: -10), 0);
    });
  });

  group('Réservations de locaux', () {
    final start = DateTime(2026, 11, 18, 8);
    final end = DateTime(2026, 11, 18, 10);

    test('détecte un chevauchement partiel', () {
      expect(reservationsOverlap(start, end, DateTime(2026, 11, 18, 9), DateTime(2026, 11, 18, 11)), isTrue);
    });

    test('détecte un créneau entièrement inclus', () {
      expect(reservationsOverlap(start, end, DateTime(2026, 11, 18, 8, 30), DateTime(2026, 11, 18, 9, 30)), isTrue);
    });

    test('accepte des créneaux adjacents', () {
      expect(reservationsOverlap(start, end, end, DateTime(2026, 11, 18, 12)), isFalse);
      expect(reservationsOverlap(start, end, DateTime(2026, 11, 18, 6), start), isFalse);
    });

    test('refuse un créneau inversé côté réservation', () {
      expect(reservationsOverlap(start, end, DateTime(2026, 11, 18, 11), DateTime(2026, 11, 18, 9)), isFalse);
    });
  });

  group('Cycle de vie des dossiers de discipline', () {
    test('clôture uniquement après instruction', () {
      expect(canCloseCase('Ouvert'), isFalse);
      expect(canCloseCase('En cours'), isTrue);
      expect(canCloseCase('Traité'), isTrue);
      expect(canCloseCase('Clos'), isFalse);
    });

    test('sanction exécutable après instruction', () {
      expect(canExecuteSanction('Ouvert'), isFalse);
      expect(canExecuteSanction('En cours'), isTrue);
      expect(canExecuteSanction('Traité'), isTrue);
      expect(canExecuteSanction('Clos'), isFalse);
    });
  });
}
