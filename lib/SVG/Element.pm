#! perl

use v5.26;
use Object::Pad;
use utf8;
class SVG::Element;

use Carp;

field $xo       :mutator;
field $style    :accessor;
field $name     :param :accessor;
field $atts     :param :accessor;
field $css      :accessor;
field $content  :param :accessor;	# array of children
field $root     :param :accessor;	# top module

BUILD {
    $css  = $root->css;
    $xo   = $root->xoforms->[-1]->{xo};
};

method _dbg (@args) {
    $root->_dbg(@args);
}

method css_push ( $updated_atts = undef ) {
    $style = $css->push( element => $name, %{$updated_atts // $atts} );
}

method css_pop () {
    $css->pop;
}

method set_graphics () {

    my $msg = $name;

    my $lw = $style->{'stroke-width'} || 0.01;
    $xo->line_width($lw);
    $msg .= " stroke-width=$lw";

    my $stroke = $style->{stroke};
    if ( lc($stroke) eq "currentcolor" ) {
	# Nothing. Use current.
	$msg .= " stroke=current";
    }
    elsif ( $stroke ne "none" ) {
	$stroke =~ s/\s+//g;
	if ( $stroke =~ /rgb\((\d+),(\d+),(\d+)\)/ ) {
	    $stroke = sprintf("#%02X%02X%02X", $1, $2, $3);
	}
	$xo->stroke_color($stroke);
	$msg .= " stroke=$stroke";
    }
    else {
	$msg .= " stroke=none";
    }

    my $fill = $style->{fill};
    if ( lc($fill) eq "currentcolor" ) {
	# Nothing. Use current.
	$msg .= " fill=current";
    }
    elsif ( lc($fill) ne "none" && $fill ne "transparent" ) {
	$fill =~ s/\s+//g;
	if ( $fill =~ /rgb\((\d+),(\d+),(\d+)\)/ ) {
	    $fill = sprintf("#%02X%02X%02X", $1, $2, $3);
	}
	$xo->fill_color($fill);
	$msg .= " fill=$fill";
    }
    else {
	$msg .= " fill=none";
    }

    if ( my $sda = $style->{'stroke-dasharray'}  ) {
	$sda =~ s/,/ /g;
	my @sda = split( ' ', $sda );
	$msg .= " sda=@sda";
	$xo->line_dash_pattern(@sda);
    }

    $self->_dbg($msg);
    return $style;
}

method _paintsub () {
    sub {
	if ( $style->{stroke}
	     && $style->{stroke} ne 'none'
	     && $style->{stroke} ne 'transparent'
	   ) {
	    if ( $style->{fill}
		 && $style->{fill} ne 'none'
		 && $style->{fill} ne 'transparent'
	       ) {
		$self->_dbg("xo paint (",
			    join(" ", $style->{stroke}, $style->{fill} ), ")");
		$xo->paint;
	    }
	    else {
		$self->_dbg("xo stroke (",
			    join(" ", $style->{stroke}, $style->{fill} ), ")");
		$xo->stroke;
	    }
	}
	elsif ( $style->{fill}
		&& $style->{fill} ne 'none'
		&& $style->{fill} ne 'transparent'
	      ) {
	    $self->_dbg("xo fill (",
			join(" ", $style->{stroke}, $style->{fill} ), ")");
	    $xo->fill;
	}
    }
}

method process () {
    # Unless overridden in a subclass there's not much we can do.
    $self->_dbg("skipping $name (not implemented)");
    $self->traverse;
}

method get_children () {

    # Note: This is the only place where these objects are created.

    my @res;
    for my $e ( @{$self->content} ) {
	if ( $e->{type} eq 'e' ) {
	    my $pkg = "SVG::" . ucfirst(lc $e->{name});
	    $pkg = "SVG::Element" unless $pkg->can("process");
	    push( @res, $pkg->new
		  ( name    => $e->{name},
		    atts    => $e->{attrib},
		    content => $e->{content},
		    root    => $self->root,
		  ) );
	}
	elsif ( $e->{type} eq 't' ) {
	    push( @res, SVG::TextElement->new
		  ( content => $e->{content},
		  ) );
	}
	else {
	    # Basically a 'cannot happen',
	    croak("Unhandled node type ", $e->{type});
	}
    }
    return @res;
}

method traverse () {
    for my $c ( $self->get_children ) {
	next if ref($c) eq "SVG::TextElement";
	$self->_dbg("+ start handling ", $c->name, " (", ref($c), ")");
	$c->process;
	$self->_dbg("- end handling ", $c->name);
    }
}

method u ( $a ) {
    confess("Undef in units") unless defined $a;
    return undef unless $a =~ /^([-+]?\d+(?:\.\d+)?)(.*)$/;
    return $1 if $2 eq "" || $2 eq "pt";
    return $1 if $2 eq "px";	# approx
    return $1*12 if $2 eq "em";	# approx
    return $1*10 if $2 eq "ex";	# approx
    return $1*72/2.54 if $2 eq "cm";
    return $1*72/25.4 if $2 eq "mm";
    return $1;			# will hopefully crash somewhere...
}

method getargs ( $a ) {
    confess("Null attr?") unless defined $a;
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    map { $self->u($_) } split( /\s*[,\s]\s*/, $a );
}

# Initial fiddling with entity attributes.
method get_params ( @desc ) {
    my $atts = shift(@desc) if ref($desc[0]) eq 'HASH';
    my @res;
    my %atts = %{ $atts // $self->atts }; # copy

    for my $param ( @desc ) {

	# Attribute may be followed by ':' and flags.
	# 0   undef -> 0
	# s   undef -> ""
	# u   process units
	# U   undef -> 0, process units
	# !   barf if undef
	my $flags;
	( $param, $flags ) = $param =~ /^(.*):(.*)$/;

	# Get and remove the attribute.
	my $p = delete( $atts{$param} );

	unless ( defined $p ) {
	    if    ( $flags =~ /s/ )    { $p = ""; }
	    elsif ( $flags =~ /[0U]/ ) { $p = 0;  }
	    else {
		croak("Undefined mandatory attribute: $param")
		  if $flags =~ /\!/;
		push( @res, $p );
		next;
	    }
	}

	# Convert units if 'u' flag.
	$p = $self->u($p) if $flags =~ /u/i;

	push( @res, $p );
    }

    # CSS push with updated attributes.
    $self->css_push( \%atts );

    # Return param values.
    return @res;
}

method get_cdata () {
    my $res = "";
    for ( $self->get_children ) {
	$res .= "\n" . $_->content if ref($_) eq "SVG::TextElement";
    }
    $res;
}

method nfi ( $tag ) {
    state $aw = {};
    warn("SVG: $tag - not fully implemented, expect strange results.")
      unless $aw->{$tag}++;
}

################ Styles and Fonts ################

method makefont ( $style ) {

    my ( $fn, $sz, $em, $bd ) = ("Times-Roman", 12, 0, 0 );

    $fn = $style->{'font-family'} // "Times-Roman";
    $sz = $style->{'font-size'} || 12;
    $sz = $1 if $sz =~ /^([.\d]+)p[xt]/; # TODO: units
    $em = $style->{'font-style'}
      && $style->{'font-style'} =~ /^(italic|oblique)$/;
    $bd = $style->{'font-weight'}
      && $style->{'font-weight'} =~ /^(bold|black)$/;

    if ( $fn =~ /^(sans|helvetica|(?:text,)?sans-serif)$/i ) {
	$fn = $bd
	  ? $em ? "Helvetica-BoldOblique" : "Helvetica-Bold"
	  : $em ? "Helvetica-Oblique" : "Helvetica";
    }
    elsif ( $fn =~ /^abc2svg(?:\.ttf)?/ or $fn eq "music" ) {
	$fn = "abc2svg.ttf";
    }
    elsif ( $fn =~ /^musejazz\s*text$/ ) {
	$fn = "MuseJazzText.otf";
    }
    else {
	$fn = $bd
	  ? $em ? "Times-BoldItalic" : "Times-Bold"
	  : $em ? "Times-Italic" : "Times-Roman";
    }
    my $font = $root->ps->{pr}->{pdf}->{__fontcache__}->{$fn} //= do {
	$root->ps->{pr}->{pdf}->font($fn);
    };
    ( $font, $sz, $fn );
}

class SVG::TextElement;

field $content  :param :accessor;

method process () {
    # Nothing to process.
}

1;
