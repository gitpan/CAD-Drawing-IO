package CAD::Drawing::IO;
our $VERSION = '0.25';

use CAD::Drawing;
use CAD::Drawing::Defined;

use Storable;

# value set within BEGIN block:
my $plgindbg = $CAD::Drawing::IO::plgindbg;


use strict;
use Carp;
########################################################################
=pod

=head1 NAME 

CAD::Drawing::IO - I/O methods for the CAD::Drawing module

=head1 Description

This module provides the load() and save() functions for CAD::Drawing
and provides a point of flow-control to deal with the inheritance and
other trickiness of having multiple formats handled through a single
module.

=head1 AUTHOR

  Eric L. Wilhelm
  ewilhelm at sbcglobal dot net
  http://pages.sbcglobal.net/mycroft

=head1 COPYRIGHT

This module is copyright (C) 2003 by Eric L. Wilhelm and A. Zahner Co.

=head1 LICENSE

This module is distributed under the same terms as Perl.  See the Perl
source package for details.

You may use this software under one of the following licenses:

  (1) GNU General Public License
    (found at http://www.gnu.org/copyleft/gpl.html)
  (2) Artistic License
    (found at http://www.perl.com/pub/language/misc/Artistic.html)

=head1 NO WARRANTY

This software is distributed with ABSOLUTELY NO WARRANTY.  The author
and his employer will in no way be held liable for any loss or damages
resulting from its use.

=head1 Modifications

The source code of this module is made freely available and
distributable under the GPL or Artistic License.  Modifications to and
use of this software must adhere to one of these licenses.  Changes to
the code should be noted as such and this notification (as well as the
above copyright information) must remain intact on all copies of the
code.

Additionally, while the author is actively developing this code,
notification of any intended changes or extensions would be most helpful
in avoiding repeated work for all parties involved.  Please contact the
author with any such development plans.


=head1 SEE ALSO

  CAD::Drawing
  CAD::Drawing::IO::*

=head1 Changes

  0.20 First public release
  0.25 Changed to plug-in-style architecture

=cut
########################################################################

=head1 front-end Input and output methods

The functions load() and save() are responsible for determining the
filetype (with forced types available via $options{type}.)  These then
call the appropriate <Package>::load() or <Package>::save() functions.

See the Plug-In Architecture section for details on how to add support
for additional filetypes.

=cut
########################################################################

=head2 save

Saves a file to disk.  See the save<type> functions in this file and the
other filetype functions in the CAD::Drawing::IO::<type> modules.

See each save<type> function for available options for that type.

While you may call the save<type> function directly (if you include the
module), it is recommended that you stick to the single point of
interface provided here so that your code does not become overwhelmingly
infected with hard-coded filetypes.

Note that this method also implements forking.  If $options{forkokay} is
true, save() will return the pid of the child process to the parent
process and setup the child to exit after saving (with currently no way
for the child to give a return value to the parent.)

  $drw->save($filename, \%options);

=cut
sub save {
	my $self = shift;
	my ( $filename, $opt) = @_;
	my $type = $$opt{type};
	if($$opt{forkokay}) {
		$SIG{CHLD} = 'IGNORE';
		my $kidpid;
		if($kidpid = fork) {
			return($kidpid);
		}
		defined($kidpid) or die "cannot fork $!\n";
		$$opt{forkokay} = 0;
		$self->diskaction("save", $filename, $type, $opt);
		exit;
	}
	return($self->diskaction("save", $filename, $type, $opt));
} # end subroutine save definition
########################################################################

=head2 load

Loads a file from disk.  See the load<type> functions in this file and
the other filetype functions in the CAD::Drawing::IO::<type> modules.

See each load<type> function for available options for that type.

In most cases %options may contain the selection methods available via
the CAD::Drawing::check_select() function.

While you may call the load<type> function directly (if you include the
module), it is recommended that you stick to the single point of
interface provided here.

  $drw->load($filename, \%options);

=cut
sub load {
	my $self = shift;
	my ($filename, $opt) = @_;
	my $type = $$opt{type};
	return($self->diskaction("load", $filename, $type, $opt));
} # end subroutine load definition
########################################################################

=head1 Plug-In Architecture

Plug-ins are modules which are under the CAD::Drawing::IO::*
namespace.  This namespace is searched at compile time, and any modules
found are require()d inside of an eval() block (see BEGIN.)  Compile
failure in any one of these modules will be printed to STDERR, but will
not halt the running program.

Each plug-in is responsible for declaring one or all of the following
variables:

  our $can_save_type = "type";
  our $can_load_type = "type (or another type)";
  our $is_inherited = 1; # or 0 (or undef())

If a package claims to be able to load or save a type, then it must
contain the functions load() or save() (respectively.)  Package which
declare $is_inherited as a true value will become methods of the
CAD::Drawing class (though their load() and save() functions will not
be visible due to their location in the inheritance tree.)

=cut
########################################################################

=head2 BEGIN

The BEGIN block implements the module path searching (looking only in
directories of @INC which contain a "CAD/Drawing/IO/" directory.)

For each plug-in which is found, code references are saved for later
use by the diskaction() function.

=cut
BEGIN {
	use File::Find;
	my %found;
	our %handlers;
	our %check_type;
	our @ISA;
	our $plgindbg = 0;
	use strict;
	foreach my $inc (@INC) {
		# (if it starts with CAD/Drawing/IO/, then we are good)
		my $look = "$inc/CAD/Drawing/IO/";
		(-d "$look") || next;
#        print "looking in $look\n";

		# I suppose deeper nested namespaces are allowed
		find(sub {
			($_ =~ m/\.pm$/) || next;
			my $mod = $File::Find::name;
			$mod =~ s#^$inc/+##;
			$mod =~ s#/+#::#g;
			$mod =~ s/\.pm//;
			$found{$mod} && next;
			$found{$mod}++;
			# print "$File::Find::name\n";
			# print "mod: $mod\n";
		}, $look );
	}
	foreach my $mod (keys(%found)) {
		# see if they are usable
		$plgindbg && print "checking $mod\n";
		if(eval("require " . $mod)) {
			my $useful;
			foreach my $action qw(load save) {
				my $type = eval(
					'$' . $mod . '::can_' . $action . '_type'
					);
				$type || next;
				$handlers{$action}{$type} && next;
				$useful++;
				$handlers{$action}{$type} = $mod . '::' . $action;
				$check_type{$type} = $mod . '::check_type';
				$plgindbg && 
					print "$action ($type) claimed by $mod\n";
				$plgindbg && 
					print "(found $handlers{$action}{$type})\n";
			}
			if(eval('$' . $mod . '::is_inherited')) {
				push(@ISA, $mod);
				$useful++;
			}
			$plgindbg && ($useful && print "using $mod\n");
		}
		else {
			$@ && warn("warning:\n$@ for $mod\n\n");
		}
	} # end foreach $mod
} # end BEGIN
########################################################################

=head2 diskaction

This function is for internal use, intended to consolidate the type
selection and calling of load/save methods.

  $drw->diskaction("load|save", $filename, $type, \%options);

For each plug-in package which was located in the BEGIN block, the
function <Package>::check_type() will be called, and must return a true
value for the package to be used for $action.

=cut
sub diskaction {
	my $self = shift;
	my ($action, $filename, $type, $opt) = @_;
	my %opts;
	(ref($opt) eq "HASH") && (%opts = %$opt);
	($action =~ m/save|load/) or 
		croak("Cannot access disk with action:  $action\n");
	$filename or
		croak("Cannot $action without filename\n");

	# FIXME: somewhat problematic:  if type is passed explicitly, we are
	# still strolling through the list to determine which module to call
	
    ####################################################################
	# choose filetype:
	my %handlers = %CAD::Drawing::IO::handlers;
	my %check = %CAD::Drawing::IO::check_type;
	foreach my $mod (keys(%{$handlers{$action}})) {
		$plgindbg && print "checking $mod\n";
		no strict 'refs';
		my $real_type = $check{$mod}($filename, $type);
		# check must return true
		$real_type || next;
		my $call = $handlers{$action}{$mod};
		$plgindbg && print "trying $call\n";
		return($call->($self, $filename, {%opts, type => $real_type}));
	}
	# FIXME: # maybe the fallback is a Storable or YAML file?
	croak("could not $action $filename as type: $type");
} # end subroutine diskaction definition
########################################################################

=head2 outloop

Crazy new experimental output method.  Each entity supported by the
format should have a key to a function in %functions, which is expected
to accept the following input data:

  $functions{$ent_type}->($obj, \%data);

  $drw->outloop(\%functions, \%data);

=cut
sub outloop {
	my $self = shift;
	my ($funcs, $data) = @_;
	my %functions = %$funcs;
	# we should ignore data here
	foreach my $layer (keys(%{$self->{g}})) {
		foreach my $ent (keys(%{$self->{g}{$layer}})) {
			if($functions{$ent}) {
				foreach my $id (keys(%{$self->{g}{$layer}{$ent}})) {
					my %addr = (
						"layer" => $layer,
						"type"  => $ent,
						"id"    => $id,
						);
					my $obj = $self->getobj(\%addr);
					$functions{before} && ($functions{before}->($obj, $data));
					$functions{$ent}->($obj, $data);
					$functions{after} && ($functions{after}->($obj, $data));
				}
			}
			else {
				carp("not supporting type: $ent");
			}
			
		}
	}
} # end subroutine outloop definition
########################################################################


1;
