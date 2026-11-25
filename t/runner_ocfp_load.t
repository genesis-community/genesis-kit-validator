#!perl
use strict;
use warnings;
use Test::More;
use JSON::PP ();

use_ok 'Genesis::Kit::Validator::Runner';
use_ok 'Genesis::Kit::Validator::Environment';
use_ok 'Genesis::Kit::Validator::OCFP';

# _load_ocfp_config: read the env's selected configs, ask Genesis where
# the env's bloc config lives, and import the merged result there.  The
# question to Genesis and the import are replaced so the test needs
# neither Genesis nor a vault; the pieces it composes are covered in
# t/ocfp_config.t.

my @calls;
my $config_base;
{
	no warnings 'redefine';
	*Genesis::Kit::Validator::Runner::_run_cmd = sub {
		my ($argv, %opts) = @_;
		push @calls, { argv => $argv, opts => \%opts };
		return '';
	};
	*Genesis::Kit::Validator::Runner::_ocfp_config_base = sub { $config_base };
	*Genesis::Kit::Validator::Runner::_step = sub { };
	*Genesis::Kit::Validator::OCFP::load = sub {
		return {
			'mgmt/fqdns'                           => { shield => 'shield.example.com' },
			'mgmt/net/subnets/ocfp-0/reserved-ips' => { shield_ip => '10.0.2.197' },
		};
	};
}

sub load {
	@calls = ();
	Genesis::Kit::Validator::Runner::_load_ocfp_config(
		Genesis::Kit::Validator::Environment->new(name => 'resolute-mgmt', @_),
		'/kit');
}

subtest 'no selection: nothing is asked or written' => sub {
	$config_base = '/secret/config/resolute/mgmt';
	load();
	is scalar(@calls), 0, 'no commands run';
};

subtest 'a selection is imported under the bloc root Genesis reports' => sub {
	$config_base = "/secret/config/resolute/mgmt";
	load(ocfp_config => 'base-aws');

	is scalar(@calls), 1, 'one command';
	is_deeply $calls[0]{argv}, ['safe', 'import'], 'safe import';
	is_deeply JSON::PP::decode_json($calls[0]{opts}{stdin}), {
		'secret/config/resolute/mgmt/fqdns' => { shield => 'shield.example.com' },
		'secret/config/resolute/mgmt/net/subnets/ocfp-0/reserved-ips' => { shield_ip => '10.0.2.197' },
	}, 'with the merged config placed under the bloc';
};

subtest 'an alternative config mount is honoured' => sub {
	$config_base = "/secret/custom/config/vaults/mgmt";
	load(ocfp_config => 'base-aws');
	ok exists JSON::PP::decode_json($calls[0]{opts}{stdin})->{'secret/custom/config/vaults/mgmt/fqdns'},
		'the import follows the mount Genesis reported';
};

subtest 'an env with no config base is refused' => sub {
	for my $none (undef, '', "  \n") {
		$config_base = $none;
		ok !eval { load(ocfp_config => 'base-aws'); 1 }, 'dies';
		like $@, qr/resolute-mgmt/, 'naming the env';
		like $@, qr/ocfp/i, 'and the reason';
		is scalar(@calls), 0, 'and nothing is imported';
	}
};

done_testing;
