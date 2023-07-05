#! perl

use v5.36;
use Object::Pad;
use utf8;
use Carp;

class PDF::SVG::CSS;

field $css    :accessor;
field $errstr :accessor;
field @stack;

BUILD {
    $css = {};
    $self->push( @_ ) if @_;
}

# Parse a string with one or more styles. Augments.
method read_string ( $string ) {

    # Flatten whitespace and remove /* comment */ style comments.
    $string =~ s/\s+/ /g;
    $string =~ s!/\*.*?\*\/!!g;

    # Split into styles.
    foreach ( grep { /\S/ } split /(?<=\})/, $string ) {
	unless ( /^\s*([^{]+?)\s*\{(.*)\}\s*$/ ) {
	    $errstr = "Invalid or unexpected style data '$_'";
	    return;
	}

	# Split in such a way as to support grouped styles.
	my $style      = $1;
	my $properties = $2;
	$style =~ s/\s{2,}/ /g;
	my @styles =
	  grep { s/\s+/ /g; 1; }
	    grep { /\S/ }
	      split( /\s*,\s*/, $style );
	foreach ( @styles ) {
	    $css->{$_} //= {};
	}

	# Split into properties.
	foreach ( grep { /\S/ } split /\;/, $properties ) {
	    unless ( /^\s*(\*?[\w._-]+)\s*:\s*(.*?)\s*$/ ) {
		$errstr = "Invalid or unexpected property '$_' in style '$style'";
		return;
	    }
	    foreach ( @styles ) {
		$css->{$_}->{lc $1} = $2;
	    }
	}
    }

    my @keys = keys( %$css );
    for my $k ( @keys ) {
	next unless $k =~ /^(\S+)\s+(\S+)$/;
	$css->{$1}->{$2} //= {};
	$self->merge( $css->{$1}->{$2}, $css->{$k} );
	delete ( $css->{$k} );
    }

    1;
}

# Merge hashes (and only hashes), recursive.
method merge ( $left, $right ) {
    return unless defined $right;
    if ( ref($left) eq 'HASH' && ref($right) eq 'HASH' ) {
	for ( keys %$right ) {
	    if ( exists $left->{$_}
		 && ref($left->{$_}) eq 'HASH'
		 && ref($right->{$_}) eq 'HASH' ) {
		$self->merge( $left->{$_}, $right->{$_} );
	    }
	    else {
		$left->{$_} = $right->{$_};
	    }
	}
	return;
    }
    croak("Cannot merge " . ref($left) . " and " . ref($right));
}

method push ( %args ) {
    my $ret = $css->{_} // {};
    if ( $args{element} && exists( $css->{$args{element}} ) ) {
	$self->merge( $ret, $css->{$args{element}} );
    }
    if ( $args{class} ) {
	for ( split( ' ', $args{class} ) ) {
	    next unless exists( $css->{".$_"} );
	    $self->merge( $ret, $css->{".$_"} );
	}
    }
    if ( $args{style} ) {
	$self->read_string( "_ {" . $args{style} . "}" )
	  or croak($errstr);
	$self->merge( $ret, delete $css->{_} );
    }
    if ( $args{id} && exists( $css->{ "#" . $args{id} } ) ) {
	$self->merge( $ret, $css->{ "#" . $args{id} } );
    }

    for ( keys %args ) {
	next if /^element|class|style|id$/;
	$ret->{$_} = $args{$_};
    }

    push( @stack, {%$css} );
    $self->merge( $css, { _ => $ret } );
    $ret;
}

method pop () {
    Carp::croak("CSS stack underflow") unless @stack;
    $css = pop(@stack);
}

1;
