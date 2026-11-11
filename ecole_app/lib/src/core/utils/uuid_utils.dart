import 'package:uuid/uuid.dart';

class UuidUtils {
  static const Uuid _uuid = Uuid();

  static String v4() => _uuid.v4();
}
