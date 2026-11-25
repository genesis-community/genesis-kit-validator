#!perl
use strict;
use warnings;
use Test::More;

use_ok 'Genesis::Kit::Validator::Runner';

# _run_genesis_step with a matcher.  A matcher asserts on output, and
# what happens next depends on whether the step failed: a failed step
# ends the env's claim on it, while a step that succeeded and printed
# the expected text (a warning, say) carries on exactly like a step
# with no matcher.  The Go testkit compared the golden manifest in
# that second case, and dropping the comparison would retire it
# without a word.

my @canned;
{
	no warnings 'redefine';
	*Genesis::Kit::Validator::Runner::_run_cmd = sub { return @canned };
}

sub step {
	Genesis::Kit::Validator::Runner::_run_genesis_step(
		cmd => ['genesis', 'manifest'], step_name => 'genesis manifest', @_);
}

subtest 'matched and failed -> undef, and the failure is reported' => sub {
	@canned = ('', 1, "boom: not allowed\n");
	my $failed;
	my $got = step(matcher => qr/not allowed/, capture => 1, failed => \$failed);
	is $got, undef, 'no output to carry forward';
	ok $failed, 'caller is told the step failed';
};

subtest 'matched and succeeded -> output carried forward' => sub {
	@canned = ("---\nname: x\n", 0, "warning: careful\n");
	my $failed;
	my $got = step(matcher => qr/careful/, capture => 1, failed => \$failed);
	is $got, "---\nname: x\n", 'stdout is returned for the golden comparison';
	ok !$failed, 'caller is told the step succeeded';
};

subtest 'matcher that does not fire still dies, whatever the exit status' => sub {
	for my $rc (0, 1) {
		@canned = ("---\nname: x\n", $rc, "something else\n");
		my $ok = eval { step(matcher => qr/careful/, capture => 1); 1 };
		ok !$ok, "rc=$rc: dies";
		like $@, qr/output_matcher did not match/, "rc=$rc: names the mismatch";
	}
};

subtest 'no matcher: unchanged' => sub {
	@canned = ("---\nname: x\n", 0, '');
	is step(capture => 1), "---\nname: x\n", 'clean exit returns stdout';
	@canned = ('', 2, "broke\n");
	ok !eval { step(capture => 1); 1 }, 'non-zero exit dies';
	like $@, qr/genesis manifest failed \(rc=2\)/, 'with the exit status';
};

done_testing;
