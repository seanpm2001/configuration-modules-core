# -*- mode: cperl -*-
# ${license-info}
# ${author-info}
# ${build-info}

=pod

=head1 DESCRIPTION

Tests for the C<update_pkgs> method. This method coordinates all the
upgrade process: checks what packages are available, decides which
packages must be removed and installed, and performs the update in a
single transaction.

=head1 TESTS

This method just does nothing on its own. It just calls other methods
so all testing is ensuring that the callees receive the correct
arguments.

The tests are just:

=head2 Basic test

Ensure that an ordinary execution works. Two cases here:

=over

=item * When C<userpkgs> is true, we don't try to remove packages.

=cut

use strict;
use warnings;
use Readonly;


use Test::Quattor;
use Test::More;
use NCM::Component::spma;

use File::Path qw(mkpath rmtree);
use LC::File;

use Set::Scalar;

# Actually, this update_pkgs just coordinates a set of other methods,
# which are not relevant for this testing script. For that purpose, we
# override them.
#
# All our backup methods will return 1 unless specified by the test
# script.
no warnings 'redefine';
no strict 'refs';

foreach my $method (qw(installed_pkgs wanted_pkgs apply_transaction versionlock
		       solve_transaction)) {
    *{"NCM::Component::spma::$method"} = sub {
	my $self = shift;
	$self->{uc($method)}->{args} = \@_;
	$self->{uc($method)}->{called}++;
	return exists($self->{uc($method)}->{return}) ?
	  $self->{uc($method)}->{return} : 1;
    };
}

sub NCM::Component::spma::schedule {
    my ($self, $op, $args) = @_;
    $self->{SCHEDULE}->{$op}->{args} = $args;
    $self->{SCHEDULE}->{$op}->{called}++;
    return "$op\n";
}

use warnings 'redefine';
use strict 'refs';

my $cmp = NCM::Component::spma->new("spma");

my $pkgs = {};
$cmp->{WANTED_PKGS}->{return} = Set::Scalar->new(qw(a b c));
$cmp->{INSTALLED_PKGS}->{return} = Set::Scalar->new(qw(b c d));
$cmp->{SOLVE_TRANSACTION}->{return} = "solve\n";
$cmp->{APPLY_TRANSACTION}->{return} = "apply";

is($cmp->update_pkgs("pkgs", "run", "allow"), 1,
   "Basic invocation returns success");
is($cmp->{INSTALLED_PKGS}->{called}, 1, "Installed packages called");
is(scalar(@{$cmp->{INSTALLED_PKGS}->{args}}), 0,
   "Installed packages called with no arguments");
is($cmp->{WANTED_PKGS}->{args}->[0], "pkgs",
   "wanted_pkgs receives the expected arguments");
ok($cmp->{SOLVE_TRANSACTION}->{called}, "Transaction solving is called");
is($cmp->{SOLVE_TRANSACTION}->{args}->[0], "run",
   "Transaction solving receives the correct flag");
is($cmp->{SCHEDULE}->{install}->{called}, 1, "Installation of packages is called");
ok(!$cmp->{SCHEDULE}->{remove}->{called},
   "With allow userpkgs, no removal is scheduled");

ok($cmp->{APPLY_TRANSACTION}->{called}, "Transaction application is called");
is($cmp->{APPLY_TRANSACTION}->{args}->[0], "install\nsolve\n",
   "Transaction application receives installation but not removal as argument");
is($cmp->{VERSIONLOCK}->{called}, 1, "Versions are locked");
is($cmp->{VERSIONLOCK}->{args}->[0], $cmp->{WANTED_PKGS}->{return},
       "Locked package versions with correct arguments");

is($cmp->{SCHEDULE}->{install}->{args}->[0], 'a',
   "Correct package scheduled to be installed");
is(scalar(@{$cmp->{SCHEDULE}->{install}->{args}}), 1,
   "Already installed packages aren't re-scheduled");

=pod

=item * When C<userpkgs> is false, it tries to remove outdated packages.

=back

=cut

is($cmp->update_pkgs("pkgs", "run", 0), 1, "Basic run without userpkgs succeeds");
is($cmp->{SCHEDULE}->{remove}->{called}, 1,
   "When userpkgs is disabled, the method tries to uninstall stuff");
is($cmp->{SCHEDULE}->{remove}->{args}->members(), 1,
   "Correct packages scheduled for removal without usrpkgs");
is($cmp->{APPLY_TRANSACTION}->{args}->[0], "remove\ninstall\nsolve\n",
   "Transaction applycation without userpkgs receives removal");

=pod

=head2 Error handling

We simulate failures in the callees, from the end to the beginning. We
ensure that the return value is correct and that the execution stops
in the correct point.

=over

=cut

# For easier comparison, reset all call counters

foreach my $m (qw(apply_transaction solve_transaction schedule
		  wanted_pkgs installed_pkgs)) {
    $cmp->{uc($m)}->{called} = 0;
}

$cmp->{SCHEDULE}->{install}->{called} = 0;
$cmp->{SCHEDULE}->{remove}->{called} = 0;

=pod

=item * Failure in C<apply_transaction> means all methods get executed

=cut

$cmp->{APPLY_TRANSACTION}->{return} = 0;

is($cmp->update_pkgs("pkgs", "run", 0), 0,
   "Failure in apply_transaction is propagated");

foreach my $m (qw(apply_transaction solve_transaction
		  wanted_pkgs installed_pkgs)) {
    is($cmp->{uc($m)}->{called}, 1,
       "Method $m called when apply_transaction fails");
}

is($cmp->{SCHEDULE}->{remove}->{called}, 1,
   "Schedule for removal when transaction fails");
is($cmp->{SCHEDULE}->{install}->{called}, 1,
   "Schedule for install when transaction fails");

=pod

=item * Failure in C<wanted_pkgs> means only C<installed_pkgs> and
C<wanted_pkgs> get executed.

=cut

$cmp->{WANTED_PKGS}->{return} = undef;

is($cmp->update_pkgs("pkgs", "run", 0), 0,
   "Failure in wanted_pkgs is propagated");

foreach my $m (qw(apply_transaction solve_transaction)) {
    is($cmp->{uc($m)}->{called}, 1,
       "Method $m called when apply_transaction fails");
}

is($cmp->{SCHEDULE}->{remove}->{called}, 1,
   "No removal scheduling happens when wanted_pkgs fails");
is($cmp->{SCHEDULE}->{install}->{called}, 1,
   "No installation scheduling happens when whanted_pkgs fails");

is($cmp->{WANTED_PKGS}->{called}, 2,
   "Failure was actually triggered by wanted_pkgs");
is($cmp->{INSTALLED_PKGS}->{called}, 2,
   "installed_pkgs called before wanted_pkgs");

=pod

=item * Failure in C<installed_pkgs> means no other method is executed.

=cut

$cmp->{INSTALLED_PKGS}->{return} = undef;

is($cmp->update_pkgs("pkgs", "run", 0), 0,
   "Failure in installed_pkgs is propagated");
is($cmp->{WANTED_PKGS}->{called}, 2,
   "wanted_pkgs is not called when installed_pkgs fails");
foreach my $m (qw(apply_transaction solve_transaction)) {
    is($cmp->{uc($m)}->{called}, 1,
       "Method $m called when apply_transaction fails");
}

is($cmp->{SCHEDULE}->{remove}->{called}, 1,
   "No removal scheduling when installed_pkgs fails");
is($cmp->{SCHEDULE}->{install}->{called}, 1,
   "No install scheduling when installed_pkgs fails");

done_testing();
