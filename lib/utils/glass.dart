import 'dart:ui';
import 'package:flutter/material.dart';

// ── Brand gradient (used as scaffold background everywhere) ───────────
const kBgGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF03050F),
    Color(0xFF06112B),
    Color(0xFF091D55),
    Color(0xFF0D3599),
  ],
  stops: [0.0, 0.28, 0.62, 1.0],
);

// ── Reusable gradient background scaffold ─────────────────────────────
class GradientScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool safeArea;

  const GradientScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.safeArea = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: safeArea ? SafeArea(child: body) : body,
      ),
    );
  }
}

// ── Glassy card ───────────────────────────────────────────────────────
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double blurSigma;
  final Color? borderColor;
  final Color? bgColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.blurSigma = 16,
    this.borderColor,
    this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(20);
    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                bgColor ?? Colors.white.withAlpha(28),
                bgColor?.withAlpha(10) ?? Colors.white.withAlpha(10),
              ],
            ),
            borderRadius: br,
            border: Border.all(
              color: borderColor ?? Colors.white.withAlpha(45),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── Glassy app bar ────────────────────────────────────────────────────
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;

  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.centerTitle = false,
  });

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AppBar(
          backgroundColor: Colors.white.withAlpha(15),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: centerTitle,
          leading: leading,
          title: Text(title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: actions,
          bottom: bottom,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Glassy tab bar ────────────────────────────────────────────────────
class GlassTabBar extends StatelessWidget implements PreferredSizeWidget {
  final List<Tab> tabs;
  final Color? indicatorColor;

  const GlassTabBar({super.key, required this.tabs, this.indicatorColor});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return TabBar(
      tabs: tabs,
      indicatorColor: indicatorColor ?? const Color(0xFF4F8AFF),
      indicatorWeight: 2.5,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white.withAlpha(120),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.6),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13),
      dividerColor: Colors.white.withAlpha(20),
    );
  }
}

// ── Glassy input decoration ───────────────────────────────────────────
InputDecoration glassInputDecoration({
  String? hint,
  Widget? prefix,
  Widget? prefixIcon,
  Widget? suffix,
  String? counterText,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.white.withAlpha(100), fontSize: 15),
    prefixIcon: prefixIcon,
    prefix: prefix,
    suffix: suffix,
    counterText: counterText ?? '',
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    filled: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  );
}

// ── Glow orbs background ──────────────────────────────────────────────
class GlowOrbs extends StatelessWidget {
  const GlowOrbs({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -120, right: -120,
          child: Container(
            width: 360, height: 360,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFF2563EB).withAlpha(55),
                Colors.transparent,
              ]),
            ),
          ),
        ),
        Positioned(
          bottom: -90, left: -90,
          child: Container(
            width: 280, height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFF4F8AFF).withAlpha(35),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Glass list tile ───────────────────────────────────────────────────
class GlassTile extends StatelessWidget {
  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  const GlassTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: BorderRadius.circular(16),
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle(
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                    child: title,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    DefaultTextStyle(
                      style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13),
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing case final t?) t,
          ],
        ),
      ),
    );
  }
}
