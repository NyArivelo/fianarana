import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newUuid() => _uuid.v4();

bool isUuid(String value) {
  final regex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
  return regex.hasMatch(value);
}
