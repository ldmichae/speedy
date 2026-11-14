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
