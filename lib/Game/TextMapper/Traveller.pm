# Copyright (C) 2009-2021  Alex Schroeder <alex@gnu.org>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option) any
# later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

=encoding utf8

=head1 NAME

Game::TextMapper::Traveller - generate Traveller subsector maps

=head1 DESCRIPTION

This generates subsector maps suitable for the Traveller game in its various
editions. Trade and communication routes are based on starports, bases, and
trade codes and jump distance; the potential connections are then winnowed down
using a minimal spanning tree.

=head1 METHODS

=cut

package Game::TextMapper::Traveller;
use Game::TextMapper::Log;
use Modern::Perl '2018';
use List::Util qw(shuffle max any);
use Mojo::Base -base;
use Role::Tiny::With;
with 'Game::TextMapper::Schroeder::Hex';

my $log = Game::TextMapper::Log->get;

has 'rows' => 10;
has 'cols' => 8;
has 'digraphs';

=head2 generate_map

This method takes no arguments. Subsectors are always 8×10.

=cut

sub generate_map {
  my $self = shift;
  $self->digraphs($self->compute_digraphs);
  # coordinates are an index into the system array
  my @coordinates = (0 .. $self->rows * $self->cols - 1);
  my @randomized =  shuffle(@coordinates);
  # %systems maps coordinates to arrays of tiles
  my %systems = map { $_ => $self->system() } grep { roll1d6() > 3 } @randomized; # density
  my $comms = $self->comms(\%systems);
  my $tiles = [map { $systems{$_} || ["empty"] } (@coordinates)];
  return $self->to_text($tiles, $comms);
}

# Each system is an array of tiles, e.g. ["size-1", "population-3", ...]
sub system {
  my $self = shift;
  my $size = roll2d6() - 2;
  my $atmosphere = max(0, roll2d6() - 7 + $size);
  $atmosphere = 0 if $size == 0;
  my $hydro = roll2d6() - 7 + $atmosphere;
  $hydro -= 4 if $atmosphere < 2 or $atmosphere >= 10;
  $hydro = 0 if $hydro < 0 or $size < 2;
  $hydro = 10 if $hydro > 10;
  my $population = roll2d6() - 2;
  my $government = max(0, roll2d6() - 7 + $population);
  my $law = max(0, roll2d6() - 7 + $government);
  my $starport = roll2d6();
  my $naval_base = 0;
  my $scout_base = 0;
  my $research_base = 0;
  my $pirate_base = 0;
  my $tech = roll1d6();
  if ($starport <= 4) {
    $starport = "A";
    $tech += 6;
    $scout_base = 1 if roll2d6() >= 10;
    $naval_base = 1 if roll2d6() >= 8;
    $research_base = 1 if roll2d6() >= 8;
  } elsif ($starport <= 6)  {
    $starport = "B";
    $tech += 4;
    $scout_base = 1 if roll2d6() >=  9;
    $naval_base = 1 if roll2d6() >= 8;
    $research_base = 1 if roll2d6() >= 10;
  } elsif ($starport <= 8)  {
    $starport = "C";
    $tech += 2;
    $scout_base = 1 if roll2d6() >=  8;
    $research_base = 1 if roll2d6() >= 10;
    $pirate_base = 1 if roll2d6() >= 12;
  } elsif ($starport <= 9)  {
    $starport = "D";
    $scout_base = 1 if roll2d6() >=  7;
    $pirate_base = 1 if roll2d6() >= 10;
  } elsif ($starport <= 11) {
    $starport = "E";
    $pirate_base = 1 if roll2d6() >= 10;
  } else {
    $starport = "X";
    $tech -= 4;
  }
  $tech += 1 if $size <= 4;
  $tech += 1 if $size <= 1; # +2 total
  $tech += 1 if $atmosphere <= 3 or $atmosphere >= 10;
  $tech += 1 if $hydro >= 9;
  $tech += 1 if $hydro >= 10; # +2 total
  $tech += 1 if $population >= 1 and $population <= 5;
  $tech += 2 if $population >= 9;
  $tech += 2 if $population >= 10; # +4 total
  $tech += 1 if $government == 0 or $government == 5;
  $tech -= 2 if $government == 13; # D
  $tech = 0 if $tech < 0;
  my $gas_giant = roll1d6() <= 9;
  my $name = $self->compute_name();
  $name = uc($name) if $population >= 9;
  my $uwp = join("", $starport, map { code($_) } $size, $atmosphere, $hydro, $population, $government, $law) . "-" . code($tech);
  # these things determine the order in which text is generated by Hex Describe
  my @tiles;
  push(@tiles, "gas") if $gas_giant;
  push(@tiles, "size-" . code($size));
  push(@tiles, "asteroid")
      if $size == 0;
  push(@tiles, "atmosphere-" . code($atmosphere));
  push(@tiles, "vacuum")
      if $atmosphere == 0;
  push(@tiles, "hydrosphere-" . code($hydro));
  push(@tiles, "water")
      if $hydro eq "A";
  push(@tiles, "desert")
      if $atmosphere >= 2
      and $hydro == 0;
  push(@tiles, "ice")
      if $hydro >= 1
      and $atmosphere <= 1;
  push(@tiles, "fluid")
      if $hydro >= 1
      and $atmosphere >= 10;
  push(@tiles, "population-" . code($population));
  push(@tiles, "barren")
      if $population eq 0
      and $law eq 0
      and $government eq 0;
  push(@tiles, "low")
      if $population >= 1 and $population <= 3;
  push(@tiles, "high")
      if $population >= 9;
  push(@tiles, "agriculture")
      if $atmosphere >= 4 and $atmosphere <= 9
      and $hydro >= 4 and $hydro <= 8
      and $population >= 5 and $population <= 7;
  push(@tiles, "non-agriculture")
      if $atmosphere <= 3
      and $hydro <= 3
      and $population >= 6;
  push(@tiles, "industrial")
      if any { $atmosphere == $_ } 0, 1, 2, 4, 7, 9
      and $population >= 9;
  push(@tiles, "non-industrial")
      if $population <= 6;
  push(@tiles, "rich")
      if $government >= 4 and $government <= 9
      and ($atmosphere == 6 or $atmosphere == 8)
      and $population >= 6 and $population <= 8;
  push(@tiles, "poor")
      if $atmosphere >= 2 and $atmosphere <= 5
      and $hydro <= 3;
  push(@tiles, "tech-" . code($tech));
  push(@tiles, "government-" . code($government));
  push(@tiles, "starport-$starport");
  push(@tiles, "law-" . code($law));
  push(@tiles, "naval") if $naval_base;
  push(@tiles, "scout") if $scout_base;
  push(@tiles, "research") if $research_base;
  push(@tiles, "pirate", "red") if $pirate_base;
  push(@tiles, "amber")
      if not $pirate_base
      and ($atmosphere >= 10
	   or $population and $government == 0
	   or $population and $law == 0
	   or $government == 7
	   or $government == 10
	   or $law >= 9);
  # last is the name
  push(@tiles, qq{name="$name"}, qq{uwp="$uwp"});
  return \@tiles;
}

sub code {
  my $code = shift;
  return $code if $code <= 9;
  return chr(55+$code); # 10 is A
}

sub compute_digraphs {
  my @first = qw(b c d f g h j k l m n p q r s t v w x y z
		 b c d f g h j k l m n p q r s t v w x y z .
		 sc ng ch gh ph rh sh th wh zh wr qu
		 st sp tr tw fl dr pr dr);
  # make missing vowel rare
  my @second = qw(a e i o u a e i o u a e i o u .);
  my @d;
  for (1 .. 10+rand(20)) {
    push(@d, one(@first));
    push(@d, one(@second));
  }
  return \@d;
}

sub compute_name {
  my $self = shift;
  my $max = scalar @{$self->digraphs};
  my $length = 3 + rand(3); # length of name before adding one more
  my $name = '';
  while (length($name) < $length) {
    my $i = 2*int(rand($max/2));
    $name .= $self->digraphs->[$i];
    $name .= $self->digraphs->[$i+1];
  }
  $name =~ s/\.//g;
  return ucfirst($name);
}

sub one {
  return $_[int(rand(scalar @_))];
}

sub roll1d6 {
  return 1+int(rand(6));
}

sub roll2d6 {
  return roll1d6() + roll1d6();
}

sub xy {
  my $self = shift;
  my $i = shift;
  my $y = int($i / $self->cols);
  my $x = $i % $self->cols;
  $log->debug("$i ($x, $y)");
  return $x + 1, $y + 1;
}

sub label {
  my ($self, $from, $to, $d, $label) = @_;
  return sprintf("%02d%02d-%02d%02d $label", @$from[0..1], @$to[0..1]);
}

# Communication routes have distance 1–2 and connect navy bases and A-class
# starports.
sub comms {
  my $self = shift;
  my %systems = %{shift()};
  my @coordinates = map { [ $self->xy($_), $systems{$_} ] } keys(%systems);
  my @comms;
  my @trade;
  my @rich_trade;
  while (@coordinates) {
    my $from = shift(@coordinates);
    my ($x1, $y1, $system1) = @$from;
    next if any { /^starport-X$/ } @$system1; # skip systems without starports
    for my $to (@coordinates) {
      my ($x2, $y2, $system2) = @$to;
      next if any { /^starport-X$/ } @$system2; # skip systems without starports
      my $d = $self->distance($x1, $y1, $x2, $y2);
      if ($d <= 2 and match(qr/^(starport-[AB]|naval)$/, qr/^(starport-[AB]|naval)$/, $system1, $system2)) {
	push(@comms, [$from, $to, $d]);
      }
      if ($d <= 2
	  # many of these can be eliminated, but who knows, perhaps one day
	  # directionality will make a difference
	  and (match(qr/^agriculture$/,
		     qr/^(agriculture|astroid|desert|high|industrial|low|non-agriculture|rich)$/,
		     $system1, $system2)
	       or match(qr/^asteroid$/,
			qr/^(asteroid|industrial|non-agriculture|rich|vacuum)$/,
			$system1, $system2)
	       or match(qr/^desert$/,
			qr/^(desert|non-agriculture)$/,
			$system1, $system2)
	       or match(qr/^fluid$/,
			qr/^(fluid|industrial)$/,
			$system1, $system2)
	       or match(qr/^high$/,
			qr/^(high|low|rich)$/,
			$system1, $system2)
	       or match(qr/^ice$/,
			qr/^industrial$/,
			$system1, $system2)
	       or match(qr/^industrial$/,
			qr/^(agriculture|astroid|desert|fluid|high|industrial|non-industrial|poor|rich|vacuum|water)$/,
			$system1, $system2)
	       or match(qr/^low$/,
			qr/^(industrial|rich)$/,
			$system1, $system2)
	       or match(qr/^non-agriculture$/,
			qr/^(asteroid|desert|vacuum)$/,
			$system1, $system2)
	       or match(qr/^non-industrial$/,
			qr/^industrial$/,
			$system1, $system2)
	       or match(qr/^rich$/,
			qr/^(agriculture|desert|high|industrial|non-agriculture|rich)$/,
			$system1, $system2)
	       or match(qr/^vacuum$/,
			qr/^(asteroid|industrial|vacuum)$/,
			$system1, $system2)
	       or match(qr/^water$/,
			qr/^(industrial|rich|water)$/,
			$system1, $system2))) {
	push(@trade, [$from, $to, $d]);
      }
      if ($d <= 3
	  # subsidized liners only
	  and match(qr/^rich$/,
		    qr/^(asteroid|agriculture|desert|high|industrial|non-agriculture|water|rich|low)$/,
		    $system1, $system2)) {
	push(@rich_trade, [$from, $to, $d]);
      }
    }
  }
  @comms = sort map { $self->label(@$_, "communication") } @{$self->minimal_spanning_tree(@comms)};
  @trade = sort map { $self->label(@$_, "trade") } @{$self->minimal_spanning_tree(@trade)};
  @rich_trade = sort map { $self->label(@$_, "rich") } @{$self->minimal_spanning_tree(@rich_trade)};
  return [@rich_trade, @comms, @trade];
}

sub match {
  my ($re1, $re2, $sys1, $sys2) = @_;
  return 1 if any { /$re1/ } @$sys1 and any { /$re2/ } @$sys2;
  return 1 if any { /$re2/ } @$sys1 and any { /$re1/ } @$sys2;
  return 0;
}

sub minimal_spanning_tree {
  # http://en.wikipedia.org/wiki/Kruskal%27s_algorithm
  my $self = shift;
  # Initialize a priority queue Q to contain all edges in G, using the
  # weights as keys.
  my @Q = sort { @{$a}[2] <=> @{$b}[2] } @_;
  # Define a forest T ← Ø; T will ultimately contain the edges of the MST
  my @T;
  # Define an elementary cluster C(v) ← {v}.
  my %C;
  my $id;
  foreach my $edge (@Q) {
    # edge u,v is the minimum weighted route from u to v
    my ($u, $v) = @{$edge};
    # prevent cycles in T; add u,v only if T does not already contain
    # a path between u and v; also silence warnings
    if (not $C{$u} or not $C{$v} or $C{$u} != $C{$v}) {
      # Add edge (v,u) to T.
      push(@T, $edge);
      # Merge C(v) and C(u) into one cluster, that is, union C(v) and C(u).
      if ($C{$u} and $C{$v}) {
	my @group;
	foreach (keys %C) {
	  push(@group, $_) if $C{$_} == $C{$v};
	}
	$C{$_} = $C{$u} foreach @group;
      } elsif ($C{$v} and not $C{$u}) {
	$C{$u} = $C{$v};
      } elsif ($C{$u} and not $C{$v}) {
	$C{$v} = $C{$u};
      } elsif (not $C{$u} and not $C{$v}) {
	$C{$v} = $C{$u} = ++$id;
      }
    }
  }
  return \@T;
}

sub to_text {
  my $self = shift;
  my $tiles = shift;
  my $comms = shift;
  my $text = "";
  for my $x (0 .. $self->cols - 1) {
    for my $y (0 .. $self->rows - 1) {
      my $tile = $tiles->[$x + $y * $self->cols];
      if ($tile) {
	$text .= sprintf("%02d%02d @$tile\n", $x + 1, $y + 1);
      }
    }
  }
  $text .= join("\n", @$comms, "\ninclude traveller.txt\n");
  return $text;
}

1;
