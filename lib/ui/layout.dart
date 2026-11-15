import 'package:flutter/material.dart';

/// Phones and tablets are used by touch, often mid-effort on a stand, so
/// controls there get the 48 px Material minimum. Desktop keeps the slim bar.
bool isTouchUi(BuildContext context) => switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia =>
        true,
      _ => false,
    };

/// Windows at least this wide (desktop or tablet landscape) get side-by-side
/// layouts; narrower ones, including portrait, stack vertically.
const wideLayoutMinWidth = 1000.0;

bool isWideLayout(double width) => width >= wideLayoutMinWidth;

/// Widest the main content grows on a wide window.
const wideContentMaxWidth = 1400.0;

/// Windows at least this wide get the left dock beside the page; narrower
/// ones get it as a drawer behind a menu button.
const dockMinWidth = 720.0;

/// Dock widths: icons only, and with labels.
const dockCollapsedWidth = 72.0, dockExpandedWidth = 208.0;
