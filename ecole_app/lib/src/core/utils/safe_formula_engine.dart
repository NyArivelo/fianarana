/// Secure, deterministic formula/placeholder engine for Document Studio.
/// - No eval, no code execution.
/// - Placeholders: {{key}} or {{key|default}}
/// - Expressions: ={{ 100 - 20 + (5 * 2) }} or ={{ paid / total * 100 }}
///   Supports numbers, + - * / %, parentheses, and variable names resolved
///   from the provided context (numeric values). Unknown/non-numeric values
///   resolve to 0. Division/modulo by zero yields 0.
class SafeFormulaEngine {
  const SafeFormulaEngine();

  String render(String template, Map<String, Object?> context) {
    var out = template;
    // Expressions first: ={{ ... }}
    out = out.replaceAllMapped(RegExp(r'=\{\{([^}]+)\}\}'), (m) {
      final expr = m.group(1)!.trim();
      final value = _eval(expr, context);
      return _formatNumber(value);
    });
    // Simple placeholders: {{key}} or {{key|default}}
    out = out.replaceAllMapped(RegExp(r'\{\{([^}]+)\}\}'), (m) {
      final raw = m.group(1)!.trim();
      final parts = raw.split('|');
      final key = parts.first.trim();
      final def = parts.length > 1 ? parts.sublist(1).join('|').trim() : '';
      final v = context[key];
      if (v == null) return def;
      final s = v.toString();
      return s.isEmpty ? def : s;
    });
    return out;
  }

  double evaluate(String expression, Map<String, Object?> context) =>
      _eval(expression, context);

  String _formatNumber(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    if (v == v.roundToDouble()) return v.toInt().toString();
    // trim trailing zeros
    var s = v.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  double _eval(String expr, Map<String, Object?> ctx) {
    try {
      final tokens = _tokenize(expr);
      final parser = _Parser(tokens, ctx);
      final result = parser.parse();
      if (!parser.atEnd) return 0;
      return result;
    } catch (_) {
      return 0;
    }
  }

  List<_Tok> _tokenize(String s) {
    final tokens = <_Tok>[];
    int i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c.trim().isEmpty) {
        i++;
        continue;
      }
      if (_isDigit(c) || (c == '.' && i + 1 < s.length && _isDigit(s[i + 1]))) {
        int j = i + 1;
        bool dot = c == '.';
        while (j < s.length) {
          final ch = s[j];
          if (_isDigit(ch)) {
            j++;
          } else if (ch == '.' && !dot) {
            dot = true;
            j++;
          } else {
            break;
          }
        }
        tokens.add(_Tok.num(double.tryParse(s.substring(i, j)) ?? 0));
        i = j;
        continue;
      }
      if (_isIdentStart(c)) {
        int j = i + 1;
        while (j < s.length && _isIdentPart(s[j])) j++;
        tokens.add(_Tok.ident(s.substring(i, j)));
        i = j;
        continue;
      }
      switch (c) {
        case '+':
          tokens.add(_Tok.op('+'));
          break;
        case '-':
          tokens.add(_Tok.op('-'));
          break;
        case '*':
          tokens.add(_Tok.op('*'));
          break;
        case '/':
          tokens.add(_Tok.op('/'));
          break;
        case '%':
          tokens.add(_Tok.op('%'));
          break;
        case '(':
          tokens.add(_Tok.op('('));
          break;
        case ')':
          tokens.add(_Tok.op(')'));
          break;
        default:
          // ignore unknown chars to stay safe/lenient
          break;
      }
      i++;
    }
    return tokens;
  }

  bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  bool _isIdentStart(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || c == '_';
  }
  bool _isIdentPart(String c) => _isIdentStart(c) || _isDigit(c) || c == '.';
}

enum _TokType { num, ident, op }

class _Tok {
  final _TokType type;
  final String text;
  final double value;
  _Tok.num(this.value) : type = _TokType.num, text = '';
  _Tok.ident(this.text) : type = _TokType.ident, value = 0;
  _Tok.op(this.text) : type = _TokType.op, value = 0;
}

class _Parser {
  final List<_Tok> t;
  final Map<String, Object?> ctx;
  int i = 0;
  _Parser(this.t, this.ctx);
  bool get atEnd => i >= t.length;

  double parse() => _expr();

  double _expr() {
    var v = _term();
    while (!atEnd && t[i].type == _TokType.op && (t[i].text == '+' || t[i].text == '-')) {
      final op = t[i++].text;
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _factor();
    while (!atEnd && t[i].type == _TokType.op && (t[i].text == '*' || t[i].text == '/' || t[i].text == '%')) {
      final op = t[i++].text;
      final r = _factor();
      if (op == '*') {
        v = v * r;
      } else if (op == '/') {
        v = r == 0 ? 0 : v / r;
      } else {
        v = r == 0 ? 0 : v % r;
      }
    }
    return v;
  }

  double _factor() {
    if (!atEnd && t[i].type == _TokType.op && t[i].text == '+') { i++; return _factor(); }
    if (!atEnd && t[i].type == _TokType.op && t[i].text == '-') { i++; return -_factor(); }
    if (!atEnd && t[i].type == _TokType.op && t[i].text == '(') {
      i++;
      final v = _expr();
      if (!atEnd && t[i].type == _TokType.op && t[i].text == ')') i++;
      return v;
    }
    if (!atEnd && t[i].type == _TokType.num) {
      return t[i++].value;
    }
    if (!atEnd && t[i].type == _TokType.ident) {
      final name = t[i++].text;
      final v = ctx[name];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
      return 0;
    }
    return 0;
  }
}
