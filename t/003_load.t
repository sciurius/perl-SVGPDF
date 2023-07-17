#!perl -T

use Test::More tests => 17;

BEGIN {
    # Load the elements first.
    use_ok("SVG::Circle");
    use_ok("SVG::CSS");
    use_ok("SVG::Defs");
    use_ok("SVG::Element");
    use_ok("SVG::G");
    use_ok("SVG::Image");
    use_ok("SVG::Line");
    use_ok("SVG::Parser");
    use_ok("SVG::Path");
    use_ok("SVG::Polygon");
    use_ok("SVG::Polyline");
    use_ok("SVG::Rect");
    use_ok("SVG::Svg");
    use_ok("SVG::Text");
    use_ok("SVG::Tspan");
    use_ok("SVG::Use");

    # And the master.
    use_ok("PDF::SVG");
}

