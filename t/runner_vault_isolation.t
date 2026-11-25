#!perl
use strict;
use warnings;
use Test::More;

use_ok 'Genesis::Kit::Validator::Runner';

# One vault is shared by every env in a run.  Each env writes mostly
# under its own secret/<env>/<kit> subtree, but not only there: an
# exodus stub can name an absolute path, and a kit can read a path
# that belongs to no env at all (cf kit reads secret/certs/org).  What
# one env leaves behind, the next one reads.  The Go testkit gave each
# env a vault of its own, so the Runner empties the mount before each
# env instead.
#
# _top_level_secret_paths picks what to remove from `safe paths`
# output: every first-level entry under the mount, leaf or subtree,
# except safe's own handshake secret.

sub tops { [ Genesis::Kit::Validator::Runner::_top_level_secret_paths(@_) ] }

is_deeply tops(''), [], 'an empty vault has nothing to clear';
is_deeply tops(undef), [], 'no output at all is treated as empty';
is_deeply tops("secret/handshake\n"), [], 'the handshake secret is left alone';

is_deeply tops(join("\n",
	'secret/aws/bosh/blobstore/agent',
	'secret/aws/bosh/db',
	'secret/certs/org',
	'secret/exodus/aws/bosh',
	'secret/exodus/other-env/bosh',
	'secret/handshake',
	'secret/leaf',
	'',
)), [qw(secret/aws secret/certs secret/exodus secret/leaf)],
	'each first-level entry once, sorted, subtree or leaf';

is_deeply tops("secret/handshake-like/x\nsecret/handshake\n"), ['secret/handshake-like'],
	'only the exact handshake path is spared';

done_testing;
