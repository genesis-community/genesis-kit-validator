#!perl
use strict;
use warnings;
use Test::More;
use File::Temp qw/tempdir/;
use File::Path qw/make_path/;

use_ok 'Genesis::Kit::Validator::OCFP';
use_ok 'Genesis::Kit::Validator::Environment';

# Referenced from a `local` below; name it twice so perl does not warn.
$Genesis::Kit::Validator::OCFP::SHARED_DIR = $Genesis::Kit::Validator::OCFP::SHARED_DIR;

my $O = 'Genesis::Kit::Validator::OCFP';

# An OCFP environment reads its bloc config from the vault.  A spec env
# names the config it wants as a base plus optional add-ins, and the
# pieces below turn that selection into the secrets to import.  All of
# them are pure, so none needs a vault or Genesis.

# --- selection --------------------------------------------------------------

subtest 'parse_selection: a base plus add-ins, as a string or a list' => sub {
	is_deeply $O->parse_selection(undef), [], 'nothing selected';
	is_deeply $O->parse_selection('base-aws'), ['base-aws'], 'a single name';
	is_deeply $O->parse_selection('base-aws+multi-az+public-ips'),
		[qw/base-aws multi-az public-ips/], 'a "+" string splits in order';
	is_deeply $O->parse_selection([qw/base-aws multi-az/]),
		[qw/base-aws multi-az/], 'a list is taken as given';
	is_deeply $O->parse_selection(['base-aws+multi-az', 'public-ips']),
		[qw/base-aws multi-az public-ips/], 'a list entry may itself use "+"';

	for my $bad ('', 'base-aws+', '+multi-az', 'base aws', '../etc', 'a/b', 'Base') {
		ok !eval { $O->parse_selection($bad); 1 }, "rejects '$bad'";
		like $@, qr/ocfp_config/, "'$bad': the error names the option";
	}
	ok !eval { $O->parse_selection({}); 1 }, 'rejects a hashref';
};

subtest 'Environment carries the parsed selection' => sub {
	my $env = Genesis::Kit::Validator::Environment->new(name => 'x');
	is_deeply $env->ocfp_config, [], 'defaults to nothing';
	$env = Genesis::Kit::Validator::Environment->new(name => 'x', ocfp_config => 'base-aws+multi-az');
	is_deeply $env->ocfp_config, [qw/base-aws multi-az/], 'parsed on construction';
	ok !eval { Genesis::Kit::Validator::Environment->new(name => 'x', ocfp_config => 'a b'); 1 },
		'a bad selection fails when the env is declared, not when it runs';
};

# --- where a name resolves ----------------------------------------------------

subtest 'resolve: kit-local wins over the shared set' => sub {
	my $kit    = tempdir(CLEANUP => 1);
	my $shared = tempdir(CLEANUP => 1);
	make_path("$kit/spec/ocfp");
	for my $f ("$shared/base-aws.yml", "$shared/multi-az.yml", "$kit/spec/ocfp/multi-az.yml", "$kit/spec/ocfp/mine.yml") {
		open my $fh, '>', $f or die $!; print $fh "{}\n"; close $fh;
	}
	local $Genesis::Kit::Validator::OCFP::SHARED_DIR = $shared;

	is $O->resolve('base-aws', $kit), "$shared/base-aws.yml",       'only shared -> shared';
	is $O->resolve('mine',     $kit), "$kit/spec/ocfp/mine.yml",    'only kit-local -> kit-local';
	is $O->resolve('multi-az', $kit), "$kit/spec/ocfp/multi-az.yml", 'both -> kit-local';

	ok !eval { $O->resolve('nope', $kit); 1 }, 'unknown name dies';
	like $@, qr{nope}, 'naming it';
	like $@, qr{\Q$kit/spec/ocfp\E}, 'and the kit-local place it looked';
	like $@, qr{\Q$shared\E}, 'and the shared place it looked';
};

subtest 'the shared set ships next to the module' => sub {
	my $dir = $O->shared_dir;
	like $dir, qr{Genesis/Kit/Validator/ocfp$}, 'under lib/, so it installs with the modules';
	ok -d $dir, 'and it exists';
};

# --- merging ----------------------------------------------------------------

subtest 'merge: by path, then by key, later files winning' => sub {
	my $base = {
		'mgmt/net/subnets/ocfp-0'              => { az => 'z1', cidr_block => '10.0.2.0/24' },
		'mgmt/net/subnets/ocfp-0/reserved-ips' => { shield_ip => '10.0.2.197', vault_ip => '10.0.2.5' },
		'mgmt/fqdns'                           => { shield => 'shield.example.com' },
	};
	my $addin = {
		'mgmt/net/subnets/ocfp-0'              => { az => 'z9' },
		'mgmt/net/subnets/ocfp-1'              => { az => 'z2' },
		'mgmt/net/subnets/ocfp-0/reserved-ips' => { vault_ip => undef, doomsday_ip => '10.0.2.9' },
		'mgmt/fqdns'                           => undef,
	};
	is_deeply $O->merge($base, $addin), {
		'mgmt/net/subnets/ocfp-0'              => { az => 'z9', cidr_block => '10.0.2.0/24' },
		'mgmt/net/subnets/ocfp-0/reserved-ips' => { shield_ip => '10.0.2.197', doomsday_ip => '10.0.2.9' },
		'mgmt/net/subnets/ocfp-1'              => { az => 'z2' },
	}, 'keys override and add; a null key is removed; a null path is removed';

	is_deeply $base->{'mgmt/net/subnets/ocfp-0'}, { az => 'z1', cidr_block => '10.0.2.0/24' },
		'the inputs are not modified';

	is_deeply $O->merge({ 'a' => { k => 1 } }, { 'a' => { k => undef } }), {},
		'a secret left with no keys is dropped';
	is_deeply $O->merge({ '/mgmt//net/' => { k => 1 } }), { 'mgmt/net' => { k => 1 } },
		'paths are normalised';
	is_deeply $O->merge(), {}, 'nothing to merge';
};

subtest 'merge: malformed files are refused' => sub {
	ok !eval { $O->merge({ 'mgmt/net' => 'cidr' }); 1 }, 'a path must map to key/value pairs';
	like $@, qr{mgmt/net}, 'naming the path';
	ok !eval { $O->merge([]); 1 }, 'a file must be a map of paths';
	ok !eval { $O->merge({ '' => { k => 1 } }); 1 }, 'an empty path is refused';
};

# --- where it lands in the vault ---------------------------------------------

subtest 'bloc_root: the config base without its environment type' => sub {
	is $O->bloc_root('/secret/config/resolute/mgmt'),        'secret/config/resolute',        'mgmt';
	is $O->bloc_root('/secret/config/resolute/ocf'),         'secret/config/resolute',        'ocf';
	is $O->bloc_root('secret/custom/config/vaults/mgmt/'),   'secret/custom/config/vaults',   'an alternative mount';
	is $O->bloc_root('/secret/config/ocfp-aws-mgmt-us/mgmt'), 'secret/config/ocfp-aws-mgmt-us', 'type inside the bloc name is kept';
	ok !eval { $O->bloc_root('/secret/config/resolute'); 1 }, 'a base that names no type is refused';
	ok !eval { $O->bloc_root(''); 1 }, 'an empty base is refused';
};

subtest 'vault_secrets: merged config placed under the bloc root' => sub {
	is_deeply $O->vault_secrets('secret/config/resolute', {
		'mgmt/fqdns' => { shield => 'shield.example.com' },
		'fqdns/base' => { value => 'example.com' },
	}), {
		'secret/config/resolute/mgmt/fqdns' => { shield => 'shield.example.com' },
		'secret/config/resolute/fqdns/base' => { value => 'example.com' },
	}, 'each path is joined to the root';
};

done_testing;
