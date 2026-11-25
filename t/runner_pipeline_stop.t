#!perl
use strict;
use warnings;
use Test::More;

use_ok 'Genesis::Kit::Validator::Runner';
use_ok 'Genesis::Kit::Validator::Environment';

# _assertions_done_after_check decides whether a genesis_check that
# failed as its matcher expected is the whole of an env's claim.
# Getting it wrong is silent in both directions: stopping too early
# retires a genesis_manifest assertion, or a golden comparison, while
# the suite still reports green.

sub env_with {
	Genesis::Kit::Validator::Environment->new(name => 'x', output_matchers => {@_});
}
sub done { Genesis::Kit::Validator::Runner::_assertions_done_after_check(@_) }

subtest 'no matchers -> pipeline continues' => sub {
	ok !done(env_with(), 0), 'an ordinary env runs the full pipeline';
};

subtest 'genesis_check only, check failed -> stop after check' => sub {
	ok done(env_with(genesis_check => qr/boom/), 1),
		'a failed preflight has nothing left to assert';
};

subtest 'genesis_check only, check succeeded -> must continue' => sub {
	# A matcher on a warning: the check passes and prints it, so the
	# env still owes its manifest and golden comparison.
	ok !done(env_with(genesis_check => qr/careful/), 0),
		'a check that passed carries on to the manifest';
};

subtest 'genesis_check + genesis_manifest, check failed -> must continue' => sub {
	# bosh kit's too-old-to-upgrade and openbao-proxy-conflict both set
	# these together, asserting failure at every step.
	ok !done(env_with(genesis_check => qr/boom/, genesis_manifest => qr/boom/), 1),
		'manifest assertion must still be evaluated';
};

subtest 'genesis_manifest only -> pipeline continues' => sub {
	ok !done(env_with(genesis_manifest => qr/boom/), 0),
		'check passes normally; manifest matcher handled downstream';
};

done_testing;
