package Logic::Minimizer;

use 5.010001;

use Moose;
use namespace::autoclean;

use Carp qw(croak);

use List::Compare::Functional qw(get_intersection);


#
# Required attributes to create the object.
#
# 1. 'width' is absolutely required (handled via Moose).
#
# 2. If 'columnstring' is provided, 'minterms', 'maxterms', and
#    'dontcares' can't be used.
#
# 3. Either 'minterms' or 'maxterms' is used, but not both.
#
# 4. 'dontcares' are used with either 'minterms' or 'maxterms', but
#    cannot be used by itself.
#
has 'width' => (
	isa => 'Int', is => 'ro', required => 1
);

has 'minterms' => (
	isa => 'ArrayRef[Int]', is => 'rw', required => 0,
	predicate => 'has_minterms'
);
has 'maxterms' => (
	isa => 'ArrayRef[Int]', is => 'rw', required => 0,
	predicate => 'has_maxterms'
);
has 'dontcares' => (
	isa => 'ArrayRef[Int]', is => 'rw', required => 0,
	predicate => 'has_dontcares'
);
has 'columnstring' => (
	isa => 'Str', is => 'ro', required => 0,
	predicate => 'has_columnstring',
	lazy => 1,
	builder => 'to_columnstring'
);
has 'dc' => (
	isa => 'Str', is => 'rw',
	default => '-'
);

has 'algorithm' => (
	isa => 'Str', is => 'rw',
	builder => 'extract_algorithm',
);

#
# Required attribute to return the solution.
#
# The terms that cover the primes needed to solve the
# truth table.
#
# Covers (the building blocks of the final form of the solution to
# the equation) is a "lazy" attribute and is calculated when asked
# for in code or by the user.
#
has 'covers'	=> (
	isa => 'ArrayRef[ArrayRef[Str]]', is => 'ro', required => 0,
	init_arg => undef,
	reader => 'get_covers',
	writer => '_set_covers',
	predicate => 'has_covers',
	clearer => 'clear_covers',
	lazy => 1,
	builder => 'generate_covers'
);

#
# $self->catch_errors();
#
# Sanity checking for parameters that contradict each other
# or which aren't sufficient to create the object.
#
# These are fatal errors. No return value needs to be checked,
# because any error results in a using croak().
#
sub catch_errors
{
	my $self = shift;
	my $w = $self->width;
	my $last_idx = (1 << $w) - 1;

	#
	# Catch errors involving minterms, maxterms, and don't-cares.
	#
	croak "Mixing minterms and maxterms not allowed"
		if ($self->has_minterms and $self->has_maxterms);

	if ($self->has_columnstring)
	{
		croak "Other terms are redundant when using the columnstring attribute"
			if ($self->has_minterms or $self->has_maxterms or $self->has_dontcares);

		my $cl = $last_idx + 1 - length $self->columnstring;

		croak "Columnstring length is too short by ", $cl if ($cl > 0);
		croak "Columnstring length is too long by ", -$cl if ($cl < 0);
	}
	else
	{
		my @terms;

		if ($self->has_minterms)
		{
			@terms = @{ $self->minterms };
		}
		elsif ($self->has_maxterms)
		{
			@terms = @{ $self->maxterms };
		}
		else
		{
			croak "Must supply either minterms or maxterms";
		}

		if ($self->has_dontcares)
		{
			my @intersect = get_intersection([$self->dontcares, \@terms]);
			if (scalar @intersect != 0)
			{
				croak "Term(s) ", join(", ", @intersect),
					" are in both the don't-care list and the term list.";
			}

			push @terms, @{$self->dontcares};
		}

		#
		# Can those terms be expressed in 'width' bits?
		#
		my @outside = grep {$_ > $last_idx or $_ < 0} @terms;

		if (scalar @outside)
		{
			croak "Terms (" . join(", ", @outside) . ") are larger than $w bits";
		}
	}

	#
	# Do we really need to check if they've set the
	# don't-care character to '0' or '1'? Oh well...
	#
	croak "Don't-care must be a single character" if (length $self->dc != 1);
	croak "The don't-care character cannot be '0' or '1'" if ($self->dc =~ qr([01]));

	#
	# Make sure we have enough variable names.
	#
	croak "Not enough variable names for your width" if (scalar @{$self->vars} < $w);

	return 1;
}

#
# minmax_bit_terms()
#
# Return the list of terms in bit format; either minterms or maxterms.
#
sub minmax_bit_terms
{
	my $self = shift;

	return ($self->has_min_bits)? @{$self->min_bits}: @{$self->max_bits};
}

#
# Return an array reference made up of the function column.
# Position 0 in the array is the 0th row of the column, and so on.
#
sub to_columnlist
{
	my $self = shift;
	my ($dfltbit, $setbit) = ($self->has_min_bits)? qw(0 1): qw(1 0);
	my @bitlist = ($dfltbit) x (1 << $self->width);

	my @terms;

	push @terms, @{$self->minterms} if ($self->has_minterms);
	push @terms, @{$self->maxterms} if ($self->has_maxterms);

	map {$bitlist[$_] = $setbit} @terms;

	if ($self->has_dontcares)
	{
		map {$bitlist[$_] = $self->dc} (@{ $self->dontcares});
	}

	return \@bitlist;
}

#
# Return a string made up of the function column. Position 0 in the string is
# the 0th row of the column, and so on.
#
sub to_columnstring
{
	my $self = shift;

	return join "", @{ $self->to_columnlist };
}

#
# Take a column string and return array refs usable as parameters for
# minterm, maxterm, and don't-care attributes.
#
sub break_columnstring
{
	my $self = shift;
	my @bitlist = split(//, $self->columnstring);
	my $x = 0;

	my(@maxterms, @minterms, @dontcares);

	for (@bitlist)
	{
		push @minterms, $x if ($_ eq '1');
		push @maxterms, $x if ($_ eq '0');
		push @dontcares, $x if ($_ eq $self->dc);
		$x++;
	}

	return (\@minterms, \@maxterms, \@dontcares);
}

#
# Get the algorithm name from the algorithm package name, suitable for
# using in the 'algorithm' parameter of Logic::TruthTable->new().
#
sub extract_algorithm
{
	my $self = shift;
	my $al =  ref $self;

	#
	# There is probably a better way to do this.
	#
	$al=~ s/^Algorithm:://;
	$al =~ s/::/-/g;
	return $al;
}

=head1 NAME

Logic::Minimizer - The parent class of boolean minimizers.

=head1 VERSION

Version 1.00

=cut

our $VERSION = '1.00';


=head1 SYNOPSIS

This is the base class for logic minimizers that are used by
L<Logic::TruthTable>. You do not need to use this class (or
indeed read any further) unless you are creating a logic
minimizer package.

    package Algorithm::SomethingNiftyLikeEspresso;
    extends 'Logic::Minimizer';

(C<Logic::TruthTable> requires the Algorithm::SomethingNiftyLikeEspresso
to use Logic::Minimizer as its base class.)

Then, either use the package directly in your program:

    my $fn = Algorithm::SomethingNiftyLikeEspresso->new(
        width => 4,
        minterms => [1, 8, 9, 14, 15],
	dontcares => [2, 3, 11, 12]
    );
    ...

or as a algorithm choice in C<Logic::TruthTable>:

    my $tt = Logic::TruthTable->new(
        width => 4,
        algorithm => 'SomethingNiftyLikeEspresso',
        columns => [
            {
                minterms => [1, 8, 9, 14, 15],
	        dontcares => [2, 3, 11, 12],
            }
            {
	        minterms => [4, 5, 6, 10, 13],
	        dontcares => [2, 3, 11, 12],
            }
        ],
    );

This class provides the methods

=head1 AUTHOR

John M. Gamble, C<< <jgamble at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-logic-minimizer at rt.cpan.org>,
or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Logic-Minimizer>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Logic::Minimizer

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Logic-Minimizer>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Logic-Minimizer>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Logic-Minimizer>

=item * Search CPAN

L<http://search.cpan.org/dist/Logic-Minimizer/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2015 John M. Gamble.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.


=cut

1;
