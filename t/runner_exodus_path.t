#!perl
use strict;
use warnings;
use Test::More;

use_ok 'Genesis::Kit::Validator::Runner';

# _exodus_vault_path maps a top-level key of a spec/exodus/<name>.yml
# stub to the vault path its fields are written under.  The Go testkit
# treated a key containing "/" as an absolute vault path, which is how
# a kit seeds another environment's exodus data, or data under a
# customized exodus mount.  Dropping that form silently relocates the
# data under secret/exodus/<env>/, and the env under test then fails
# to find it.

sub path { Genesis::Kit::Validator::Runner::_exodus_vault_path(@_) }

subtest 'bare key -> service type under this env\'s exodus path' => sub {
	is path('upgrade', 'bosh'), 'secret/exodus/upgrade/bosh',
		'a plain type name stays under secret/exodus/<env>/';
};

subtest 'key containing "/" -> absolute vault path' => sub {
	is path('workers', 'secret/custom/exodus/web-env/concourse'),
		'secret/custom/exodus/web-env/concourse',
		'a path-shaped key is used verbatim';
	is path('workers', 'secret/exodus/other-env/bosh'),
		'secret/exodus/other-env/bosh',
		'another env under the default mount is reachable too';
};

subtest 'leading slash on an absolute key is dropped' => sub {
	is path('workers', '/secret/custom/exodus/web-env/concourse'),
		'secret/custom/exodus/web-env/concourse',
		'safe paths carry no leading slash';
};

done_testing;
