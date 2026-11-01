/// The first step: the three languages on one pane of the portal's glass,
/// each named in itself (English, Français, العربية) and laid out in its own
/// direction, English marked as the default, as the portal's own chooser
/// draws them (LanguageChooser.tsx, languageChooser.css in foorsa-reward).
///
/// There is no Continue: a tap on a language is the choice. The check moves to
/// it, the screen's words change to it at once, and a beat later the pane
/// folds into the arrow and unfolds as the welcome, in that language. For a
/// screen reader each row is a button named in its own language, and says
/// what a double tap does in that language too.
library;

import 'dart:ui' as ui;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../app_language.dart';
import 'boarding_style.dart';
import 'gesture_demo.dart';
import 'glass.dart';
import 'lucide.dart';
import 'onboarding_flow.dart';
import 'scene_hint.dart';
import 'stage_forms.dart';

/// The languages, in the order the portal lists them.
const languageOrder = <AppLanguage>[
  AppLanguage.en,
  AppLanguage.fr,
  AppLanguage.ar,
];

/// The pane on [stage], centred where the transitions leave the object.
Rect languagePaneRect(Size stage) {
  final size = languagePaneSize(stage);
  return Rect.fromCenter(
      center: stage.center(Offset.zero),
      width: size.width,
      height: size.height);
}

/// The language step's gesture: a tap on the first row, English, the
/// default. Still, a chevron above the pane points down at it.
GestureDemo languageDemo(Size stage) {
  final pane = languagePaneRect(stage);
  final row = Rect.fromLTWH(pane.left, pane.top, pane.width, pane.height / 3);
  return GestureDemo.tap(
      row.center + Offset(row.width * 0.18, 4),
      RRect.fromRectAndCorners(row,
          topLeft: const Radius.circular(languagePaneRadius),
          topRight: const Radius.circular(languagePaneRadius)));
}

/// What a row says to a screen reader, in its own language: its name, and
/// what a double tap does.
AttributedString languageName(AppLanguage language) =>
    _inLanguage(language.nativeName, language);
AttributedString languageHint(AppLanguage language) =>
    _inLanguage(copyFor(BoardingStep.language, language).spoken, language);

AttributedString _inLanguage(String text, AppLanguage language) =>
    AttributedString(text, attributes: [
      LocaleStringAttribute(
          range: ui.TextRange(start: 0, end: text.length),
          locale: language.locale),
    ]);

class LanguageScene extends StatelessWidget {
  const LanguageScene({
    super.key,
    required this.still,
    required this.feel,
    required this.armed,
    required this.chosen,
    required this.hint,
    required this.onChoose,
  });

  final bool still;
  final Feel feel;

  /// The student may choose (the takeoff is over, nothing is moving).
  final bool armed;

  /// The language the screen speaks now: its row is checked.
  final AppLanguage chosen;

  /// What to do, said under the pane and shown on its first row.
  final String hint;
  final ValueChanged<AppLanguage> onChoose;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final stage = box.biggest;
      final pane = languagePaneRect(stage);
      final row = pane.height / 3;
      return SceneGuide(
        instruction: hint,
        demo: languageDemo(stage),
        instructionTop: pane.bottom + 18,
        clearOf: pane.bottom,
        active: armed,
        still: still,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fromRect(
            rect: pane,
            child: GlassPane(
              glass: Glass.pane,
              radius: languagePaneRadius,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(languagePaneRadius),
                child: Column(children: [
                  for (var i = 0; i < languageOrder.length; i++) ...[
                    if (i > 0)
                      Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 18),
                          color: Boarding.hairline),
                    _LanguageRow(
                      language: languageOrder[i],
                      height: row - (i > 0 ? 1 : 0),
                      on: languageOrder[i] == chosen,
                      armed: armed,
                      still: still,
                      feel: feel,
                      onTap: () => onChoose(languageOrder[i]),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

class _LanguageRow extends StatefulWidget {
  const _LanguageRow({
    required this.language,
    required this.height,
    required this.on,
    required this.armed,
    required this.still,
    required this.feel,
    required this.onTap,
  });

  final AppLanguage language;
  final double height;
  final bool on;
  final bool armed;
  final bool still;
  final Feel feel;
  final VoidCallback onTap;

  @override
  State<_LanguageRow> createState() => _LanguageRowState();
}

class _LanguageRowState extends State<_LanguageRow> {
  bool _pressed = false;

  void _press(bool down) {
    if (_pressed == down) return;
    setState(() => _pressed = down);
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final armed = widget.armed;
    // The portal's row: its name, English's Default tag, the check at the
    // end, all in the row's own direction (an Arabic row starts at the right).
    final name = Text(
      language.nativeName,
      maxLines: 1,
      textScaler: InstructionScale.of(context),
      style: TextStyle(
        fontSize: language == AppLanguage.ar ? 20 : 19,
        fontWeight: FontWeight.w600,
        height: language == AppLanguage.ar ? 1.3 : 1.2,
        letterSpacing: language == AppLanguage.ar ? 0 : -0.19,
        color: widget.on ? Boarding.heading : const Color(0xFFC7D2DE),
      ),
    );
    return Semantics(
      button: true,
      selected: widget.on,
      enabled: armed,
      attributedLabel: languageName(language),
      attributedHint: languageHint(language),
      textDirection: language.direction,
      excludeSemantics: true,
      onTap: armed ? widget.onTap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: armed
            ? (_) {
                widget.feel('press');
                _press(true);
              }
            : null,
        onTapUp: armed ? (_) => _press(false) : null,
        onTapCancel: armed ? () => _press(false) : null,
        onTap: armed ? widget.onTap : null,
        child: AnimatedContainer(
          duration: Duration(milliseconds: _pressed ? 60 : 200),
          curve: Curves.easeOut,
          height: widget.height,
          color: _pressed
              ? const Color(0x0DFFFFFF)
              : const Color(0x00FFFFFF),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Directionality(
            textDirection: language.direction,
            child: Row(children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      name,
                      if (language == AppLanguage.en) ...[
                        const SizedBox(width: 12),
                        const _DefaultTag(),
                      ],
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _Check(on: widget.on, still: widget.still),
            ]),
          ),
        ),
      ),
    );
  }
}

/// English's tag, in English, as on the portal's chooser.
class _DefaultTag extends StatelessWidget {
  const _DefaultTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      decoration: BoxDecoration(
        color: const Color(0x24A9C8E6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('Default',
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context)
              .clamp(maxScaleFactor: 1.3),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: Boarding.accent)),
    );
  }
}

/// The check: an empty ring, and on the chosen row a pearl disc with the
/// check, which pops in.
class _Check extends StatelessWidget {
  const _Check({required this.on, required this.still});
  final bool on;
  final bool still;

  @override
  Widget build(BuildContext context) {
    const ease = Cubic(0.23, 1, 0.32, 1);
    return AnimatedContainer(
      duration: Duration(milliseconds: still ? 0 : 180),
      curve: ease,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? const Color(0xFFE8F0F8) : const Color(0x00E8F0F8),
        border: Border.all(
            color: on ? const Color(0x00E4EFFA) : const Color(0x38E4EFFA),
            width: 1.5),
      ),
      child: AnimatedOpacity(
        duration: Duration(milliseconds: still ? 0 : 220),
        curve: ease,
        opacity: on ? 1 : 0,
        child: AnimatedScale(
          duration: Duration(milliseconds: still ? 0 : 220),
          curve: ease,
          scale: on || still ? 1 : 0.6,
          child: const Center(
            child: Lucide(LucideIcons.check,
                size: 18, color: Boarding.nightTop, strokeWidth: 2.6),
          ),
        ),
      ),
    );
  }
}
