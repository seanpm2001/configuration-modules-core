use strict;
use warnings;

BEGIN {
    *CORE::GLOBAL::sleep = sub {};
}

use Test::More;
use Test::Quattor qw(ipv6);
use Test::MockModule;
use Readonly;

use NCM::Component::nmstate;
my $mock = Test::MockModule->new('NCM::Component::nmstate');
my %executables;
$mock->mock('_is_executable', sub {diag "executables $_[1] ",explain \%executables;return $executables{$_[1]};});

my $cfg = get_config_for_profile('ipv6');
my $cmp = NCM::Component::nmstate->new('network');

Readonly my $ETH0_YML => <<EOF;
# File generated by NCM::Component::nmstate. Do not edit
---
interfaces:
- ipv4:
    address:
    - ip: 4.3.2.1
      prefix-length: 24
    dhcp: false
    enabled: true
  ipv6:
    address:
    - ip: 2001:678:123:E012:0:0:0:45
      prefix-length: 64
    enabled: true
  name: eth0
  profile-name: eth0
  state: up
routes:
  config:
  - next-hop-interface: eth0
    state: absent
  - destination: 0.0.0.0/0
    next-hop-address: 4.3.2.254
    next-hop-interface: eth0
  - destination: ::/0
    next-hop-address: 2001:678:123:e012::2
    next-hop-interface: eth0
EOF

=pod

=head1 DESCRIPTION

Test the C<Configure> method of the component for ipv6 configuration.

=cut

is($cmp->Configure($cfg), 1, "Component runs correctly with a test profile");

my $eth0yml = get_file_contents("/etc/nmstate/eth0.yml");
is($eth0yml, $ETH0_YML, "Exact eth0 route yml config");

done_testing();
