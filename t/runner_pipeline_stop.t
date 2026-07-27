#!perl
use strict;
use warnings;
use Test::More;

use_ok 'Genesis::Kit::Validator::Runner';
use_ok 'Genesis::Kit::Validator::Environment';

# _assertions_done_after_check decides whether a fired genesis_check
# matcher is the whole of an env's claim.  Getting it wrong is silent:
# stopping too early retires a genesis_manifest assertion while the
# suite still reports green, which is exactly the failure this guard
# exists to prevent.

sub env_with {
	Genesis::Kit::Validator::Environment->new(name => 'x', output_matchers => {@_});
}

subtest 'no matchers -> pipeline continues' => sub {
	ok !Genesis::Kit::Validator::Runner::_assertions_done_after_check(env_with()),
		'an ordinary env runs the full pipeline';
};

subtest 'genesis_check only -> stop after check' => sub {
	ok Genesis::Kit::Validator::Runner::_assertions_done_after_check(
		env_with(genesis_check => qr/boom/)),
		'check-only env has nothing left to assert';
};

subtest 'genesis_check + genesis_manifest -> must continue' => sub {
	# bosh kit's too-old-to-upgrade and openbao-proxy-conflict both set
	# these together, asserting failure at every step.
	ok !Genesis::Kit::Validator::Runner::_assertions_done_after_check(
		env_with(genesis_check => qr/boom/, genesis_manifest => qr/boom/)),
		'manifest assertion must still be evaluated';
};

subtest 'genesis_manifest only -> pipeline continues' => sub {
	ok !Genesis::Kit::Validator::Runner::_assertions_done_after_check(
		env_with(genesis_manifest => qr/boom/)),
		'check passes normally; manifest matcher handled downstream';
};

done_testing;
