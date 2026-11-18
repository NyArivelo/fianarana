import 'package:flutter/material.dart';

/// Couleurs sémantiques utilisées par les badges et cartes de statistiques.
enum AppTone { neutral, info, success, warning, danger }

/// Formate un entier avec séparateur d'espace fine (norme française).
String formatNumber(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}$buffer';
}

/// Montant en ariary malgache, ex: `1 250 000 MGA`.
String formatMga(num value) => '${formatNumber(value.round())} MGA';

String formatDateIso(DateTime? date) {
  if (date == null) return '-';
  final d = date.toLocal();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String formatDateFr(DateTime? date) {
  if (date == null) return '-';
  const months = <String>[
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];
  final d = date.toLocal();
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

({Color background, Color foreground, Color border}) appToneColors(BuildContext context, AppTone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (tone) {
    case AppTone.info:
      return dark
          ? (background: const Color(0xFF172554), foreground: const Color(0xFF93C5FD), border: const Color(0xFF1E3A8A))
          : (background: const Color(0xFFEFF6FF), foreground: const Color(0xFF1D4ED8), border: const Color(0xFFBFDBFE));
    case AppTone.success:
      return dark
          ? (background: const Color(0xFF052E2B), foreground: const Color(0xFF6EE7B7), border: const Color(0xFF065F46))
          : (background: const Color(0xFFECFDF5), foreground: const Color(0xFF047857), border: const Color(0xFFA7F3D0));
    case AppTone.warning:
      return dark
          ? (background: const Color(0xFF451A03), foreground: const Color(0xFFFCD34D), border: const Color(0xFF78350F))
          : (background: const Color(0xFFFFFBEB), foreground: const Color(0xFFB45309), border: const Color(0xFFFDE68A));
    case AppTone.danger:
      return dark
          ? (background: const Color(0xFF450A0A), foreground: const Color(0xFFFCA5A5), border: const Color(0xFF7F1D1D))
          : (background: const Color(0xFFFEF2F2), foreground: const Color(0xFFB91C1C), border: const Color(0xFFFECACA));
    case AppTone.neutral:
      return dark
          ? (background: const Color(0xFF1E293B), foreground: const Color(0xFFCBD5E1), border: const Color(0xFF334155))
          : (background: const Color(0xFFF1F5F9), foreground: const Color(0xFF475569), border: const Color(0xFFE2E8F0));
  }
}

/// Petit badge arrondi (statut, quitus, disponibilité...).
class AppBadge extends StatelessWidget {
  final String text;
  final AppTone tone;
  final IconData? icon;

  const AppBadge(this.text, {super.key, this.tone = AppTone.neutral, this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = appToneColors(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: colors.foreground),
          const SizedBox(width: 4),
        ],
        Text(text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.foreground)),
      ]),
    );
  }
}

/// Carte d'indicateur (KPI) avec icône teintée.
class AppStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final AppTone tone;
  final double width;

  const AppStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
    this.tone = AppTone.info,
    this.width = 218,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = appToneColors(context, tone);
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 18, color: colors.foreground),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                if (hint != null)
                  Text(hint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Carte de section avec titre, sous-titre et actions optionnelles.
class AppSectionCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppSectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null || trailing != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (title != null)
                    Text(title!,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          style: TextStyle(
                              fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                    ),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        if (title != null || trailing != null)
          Divider(height: 1, color: theme.dividerColor),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}

/// État vide homogène (icône + message + action optionnelle).
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 34, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ]),
      ),
    );
  }
}

/// Bandeau d'alerte pleine largeur (ex: prêts en retard).
class AppAlertBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final AppTone tone;

  const AppAlertBanner({
    super.key,
    this.icon = Icons.warning_amber_rounded,
    required this.title,
    this.message,
    this.action,
    this.tone = AppTone.warning,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appToneColors(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: colors.foreground),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: colors.foreground)),
            if (message != null)
              Text(message!,
                  style: TextStyle(fontSize: 11, color: colors.foreground.withValues(alpha: 0.85))),
          ]),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ]),
    );
  }
}

/// En-tête de page cohérent avec la maquette (titre + sous-titre + actions).
class AppPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!,
                  style:
                      TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            ),
        ]),
      ),
      ...actions,
    ]);
  }
}

/// Champ texte standard de l'application.
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? Function(String?)? validator;
  final bool enabled;
  final bool autofocus;
  final double? width;

  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.enabled = true,
    this.autofocus = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      obscureText: obscureText,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      enabled: enabled,
      autofocus: autofocus,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 18),
        suffixIcon: suffixIcon,
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

/// Liste déroulante standard de l'application.
class AppSelectField<T> extends StatelessWidget {
  final T value;
  final String? label;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final double? width;

  const AppSelectField({
    super.key,
    required this.value,
    this.label,
    required this.items,
    this.onChanged,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final field = DropdownButtonFormField<T>(
      value: value,
      isDense: true,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: onChanged,
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

/// Zone de texte multilignes standard.
class AppTextArea extends AppTextField {
  const AppTextArea({
    super.key,
    super.controller,
    super.label,
    super.hint,
    super.prefixIcon,
    super.suffixIcon,
    super.keyboardType,
    super.onChanged,
    super.validator,
    super.enabled,
    super.width,
    int lines = 3,
  }) : super(maxLines: lines);
}

/// Disposition responsive sans débordement horizontal fixe.
class AppResponsiveWrap extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final WrapAlignment alignment;

  const AppResponsiveWrap({
    super.key,
    required this.children,
    this.spacing = 10,
    this.runSpacing = 10,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
