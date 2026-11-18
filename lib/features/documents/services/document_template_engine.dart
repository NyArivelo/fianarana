import 'dart:convert';

/// Moteur de rendu sécurisé pour Document Studio.
/// - Substitution de variables {{chemin.variable}} depuis un contexte.
/// - Formules simples autorisées via {{calc:expression}} sans eval (opérateurs + - * /, parenthèses, nombres, variables numériques du contexte).
/// - Aucune exécution de code arbitraire.
class DocumentTemplateEngine {
  String render(String template, Map<String, dynamic> context) {
    var out = template;
    // formules {{calc:...}}
    out = out.replaceAllMapped(RegExp(r'\{\{\s*calc:([^}]+)\}\}'), (m) {
      final expr = m.group(1)!.trim();
      final value = _safeEval(expr, context);
      return value == null ? '' : _fmt(value);
    });
    // variables {{a.b}}
    out = out.replaceAllMapped(RegExp(r'\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}'), (m) {
      final key = m.group(1)!.trim();
      final v = _resolve(context, key);
      if (v == null) return '';
      return v is num ? _fmt(v) : v.toString();
    });
    return out;
  }

  dynamic _resolve(Map<String, dynamic> ctx, String path) {
    dynamic cur = ctx;
    for (final part in path.split('.')) {
      if (cur is Map) {
        cur = cur[part];
      } else {
        return null;
      }
    }
    return cur;
  }

  String _fmt(num n) {
    if (n is int || n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }

  /// Évaluateur arithmétique sécurisé (nombres, + - * /, parenthèses, variables numériques).
  num? _safeEval(String expr, Map<String, dynamic> context) {
    try {
      final tokens = _tokenize(expr, context);
      if (tokens.isEmpty) return null;
      final parser = _Parser(tokens);
      final result = parser.parseExpression();
      if (result == null || !parser.atEnd) return null;
      return result;
    } catch (_) {
      return null;
    }
  }

  List<_Tok> _tokenize(String s, Map<String, dynamic> context) {
    final out = <_Tok>[];
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c.trim().isEmpty) {
        i++;
        continue;
      }
      if ('+-*/()'.contains(c)) {
        out.add(_Tok(c, c));
        i++;
        continue;
      }
      if (RegExp(r'[0-9.]').hasMatch(c)) {
        var j = i + 1;
        while (j < s.length && RegExp(r'[0-9.]').hasMatch(s[j])) j++;
        final n = num.tryParse(s.substring(i, j));
        if (n != null) out.add(_Tok('n', n));
        i = j;
        continue;
      }
      if (RegExp(r'[a-zA-Z_]').hasMatch(c)) {
        var j = i + 1;
        while (j < s.length && RegExp(r'[a-zA-Z0-9_.]').hasMatch(s[j])) j++;
        final name = s.substring(i, j);
        final v = _resolve(context, name);
        if (v is num) out.add(_Tok('n', v));
        i = j;
        continue;
      }
      i++; // ignore unknown
    }
    return out;
  }

  Map<String, dynamic> decodeContent(String jsonStr) {
    try {
      final v = jsonDecode(jsonStr);
      if (v is Map<String, dynamic>) return v;
      return {};
    } catch (_) {
      return {};
    }
  }
}

class _Tok {
  final String type; // n, + - * / ( )
  final dynamic value;
  _Tok(this.type, this.value);
}

class _Parser {
  final List<_Tok> t;
  int i = 0;
  _Parser(this.t);
  bool get atEnd => i >= t.length;
  _Tok? peek() => atEnd ? null : t[i];
  _Tok? consume() => atEnd ? null : t[i++];

  num? parseExpression() => _parseAdd();
  num? _parseAdd() {
    final first = _parseMul();
    if (first == null) return null;
    var acc = first;
    while (!atEnd) {
      final p = peek();
      if (p == null || (p.type != '+' && p.type != '-')) break;
      consume();
      final right = _parseMul();
      if (right == null) return null;
      acc = p.type == '+' ? acc + right : acc - right;
    }
    return acc;
  }

  num? _parseMul() {
    final first = _parseUnary();
    if (first == null) return null;
    var acc = first;
    while (!atEnd) {
      final p = peek();
      if (p == null || (p.type != '*' && p.type != '/')) break;
      consume();
      final right = _parseUnary();
      if (right == null) return null;
      acc = p.type == '*' ? acc * right : (right == 0 ? 0 : acc / right);
    }
    return acc;
  }

  num? _parseUnary() {
    final p = peek();
    if (p != null && (p.type == '+' || p.type == '-')) {
      consume();
      final v = _parseUnary();
      if (v == null) return null;
      return p.type == '-' ? -v : v;
    }
    return _parsePrimary();
  }

  num? _parsePrimary() {
    final p = peek();
    if (p == null) return null;
    if (p.type == 'n') {
      consume();
      return p.value as num;
    }
    if (p.type == '(') {
      consume();
      final v = parseExpression();
      if (peek()?.type == ')') consume();
      return v;
    }
    return null;
  }
}
