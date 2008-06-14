#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2007,2008 -- leonerd@leonerd.org.uk

package String::MatchInterpolate;

our $VERSION = "0.02";

use strict;

use Carp;
use Text::Balanced qw( extract_delimited extract_bracketed );

=head1 NAME

C<String::MatchInterpolate> - perform named regexp capture and variable
interpolation from the same template.

=head1 SYNOPSIS

 use String::MatchInterpolate;

 my $smi = String::MatchInterpolate->new( 'My name is ${NAME/\w+/}' );

 my $vars = $smi->match( "My name is Bob" );
 my $name = $vars->{NAME};

 print $smi->interpolate( { NAME => "Jim" } ) . "\n";

=head1 DESCRIPTION

This module provides an object class which represents a string matching and
interpolation pattern. It contains named-variable placeholders which include
a regexp pattern to match them on. An instance of this class represents a
single pattern, which can be matched against or interpolated into.

Objects in this class are not modified once constructed; they do not store
any runtime state other than data derived arguments passed to the constructor.

=head2 Template Format

The template consists of a string with named variable placeholders embedded in
it. It looks similar to a perl or shell string with interpolation:

 A string here with ${NAME/pattern/} interpolations

The embedded variable is delmited by perl-style C<${ }> braces, and contains
a name and a pattern. The pattern is a normal perl regexp fragment that will
be used by the C<match()> method. This regexp should not contain any capture
brackets C<( )> as these will confuse the parsing logic.

Outside of the embedded variables, the string is interpreted literally; i.e.
not as a regexp pattern. A backslash C<\> may be used to escape the following
character, allowing literal backslashes or dollar signs to be used.

The intended use for this object class is that the template strings would come
from a configuration file, or some other source of "trusted" input. In the
current implementation, there is nothing to stop a carefully-crafted string
from containing arbitrary perl code, which would be executed every time the
C<match()> or C<interpolate()> methods are called. (See "SECURITY" section).
This fact may be changed in a later version.

=head2 Suffices

By default, the beginning and end of the string match are both anchored. If
the C<allow_suffix> option is passed to the constructor, then the end of the
string is not anchored, and instead, any suffix found by the C<match()> method
will be returned in a hash key called C<_suffix>. This may be useful, for
example, when matching directory names, URLs, or other cases of strings with
unconstrained suffices. The C<interpolate()> method will not recognise this
hash key; instead just use normal string concatenation on the result.

 my $userhomematch = String::MatchInterpolate->new(
    '/home/${USER/\w+/}/',
    allow_suffix => 1
 );

 my $vars = $userhomematch->match( "/home/fred/public_html" );
 print "Need to fetch file $vars->{_suffix} from $vars->{USER}\n";

=cut

=head1 CONSTRUCTOR

=cut

=head2 $smi = String::MatchInterpolate->new( $template, %opts )

Constructs a new C<String::MatchInterpolate> object that represents the given
template and returns it.

=over 8

=item $template

A string containing the template in the format given above

=item %opts

A hash containing extra options. The following options are recognised:

=over 4

=item allow_suffix

A boolean flag. If true, then the end of the string will not be anchored, and
instead, an extra suffix will be allowed to follow the matched portion. It
will be returned as C<_suffix> by the C<match()> method.

=back

=back

=cut

sub new
{
   my $class = shift;
   my ( $template, %opts ) = @_;

   my $self = bless {
      template => $template,
      vars     => [],
   }, $class;

   my %vars;

   my $matchpattern = "";
   my $capturenumber = 1;
   my $matchbind = "";

   my @interpparts;

   # The interpsub closure will contain elements of this array in its
   # environment
   my @literals;

   while( length $template ) {
      if( $template =~ m/^\$\{/ ) {
         # Chop off leading dollar sign
         $template =~ s/^\$//;

         ( my $embedded, $template ) = extract_bracketed( $template, '{}' );

         $embedded =~ m#^{(\w+)(.*)}$# or croak "Unrecognised format for embedded variable $embedded";

         my ( $var, $pattern ) = ( $1, $2 );

         croak "Multiple occurances of $var" if exists $vars{$var};
         $vars{$var} = 1;
         push @{ $self->{vars} }, $var;

         ( $pattern, my $remaining ) = extract_delimited( $pattern, "/", '', '' );

         # Remove delimiting slashes
         s{^/}{}, s{/$}{} for $pattern;

         $matchpattern .= "($pattern)";
         $matchbind .= "   \$var->{$var} = \$$capturenumber;\n";
         $capturenumber++;

         push @interpparts, "\$var->{$var}";
      }
      else {
         # Grab up to the next $ that isn't escaped \$
         $template =~ m/^(.*?[^\\])(?:$|\$\{)/;
         my $literal = $1;

         substr( $template, 0, length $literal ) = "";

         # Unescape
         $literal =~ s{\\(.)}{$1}g;

         $matchpattern .= quotemeta $literal;

         push @literals, $literal;
         push @interpparts, "\$literals[$#literals]";
      }
   }

   if( $opts{allow_suffix} ) {
      $matchpattern .= "(.*?)";
      $matchbind .= "   \$var->{_suffix} = \$$capturenumber;\n";
      $capturenumber++;
   }

   my $matchcode = "
   \$_[0] =~ m{^$matchpattern\$} or return undef;
   my \$var = {};
$matchbind
   \$var;
";

   $self->{matchsub} = eval "sub { $matchcode }";
   croak $@ if $@;

   my $interpcode = "
   my ( \$var ) = \@_;
   " . join( " . ", @interpparts ) . ";
";

   $self->{interpsub} = eval "sub { $interpcode }";
   croak $@ if $@;

   return $self;
}

=head1 METHODS

=cut

=head2 $vars = $smi->match( $str )

Attempts to match the given string against the template. If successful,
returns a HASH reference containing the values of the captures. If the string
fails to match, C<undef> is returned.

=over 8

=item $str

The string to match

=back

=cut

sub match
{
   my $self = shift;
   my ( $str ) = @_;
   return $self->{matchsub}->( $str );
}

=head2 $str = $smi->interpolate( $vars )

Interpolates the given variable values into the template and returns the
generated string.

=over 8

=item $vars

Reference to a HASH containing the variable values to interpolate

=back

=cut

sub interpolate
{
   my $self = shift;
   my ( $var ) = @_;
   return $self->{interpsub}->( $var );
}

=head2 @vars = $smi->vars()

Returns the list of variable names defined / used by the template.

=cut

sub vars
{
   my $self = shift;
   return @{ $self->{vars} };
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 NOTES

The template is compiled into a pair of strings containing perl code, which
implement the matching and interpolation operations using normal perl regexps
and string contatenation. These strings are then C<eval()>ed into CODE
references which the object stores. This makes it faster than a simple regexp
that operates over the template string each time a match or interpolation
needs to be performed. (See the F<benchmark.pl> file in the module's
distribution).

=head1 SECURITY CONSIDERATIONS

Because of the way the optimised match and interpolate functions are
generated, it is possible to inject arbitrary perl code via the template given
to the constructor. As such, this object should not be used when the source of
that template is considered untrusted.

Neither the C<match()> not C<interpolate()> methods suffer this problem; any
input into these is safe from exploit in this way.

=head1 SEE ALSO

=over 4

=item *

L<String::Interpolate> - Wrapper for builtin the Perl interpolation engine

=item *

L<Regexp::NamedCaptures> - Saves capture results to your own variables

=back

=head1 AUTHOR

Paul Evans E<lt>leonerd@leonerd.org.ukE<gt>
