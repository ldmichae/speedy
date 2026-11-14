/// Windows at least this wide (desktop or tablet landscape) get side-by-side
/// layouts; narrower ones, including portrait, stack vertically.
const wideLayoutMinWidth = 1000.0;

bool isWideLayout(double width) => width >= wideLayoutMinWidth;

/// Widest the main content grows on a wide window.
const wideContentMaxWidth = 1400.0;
