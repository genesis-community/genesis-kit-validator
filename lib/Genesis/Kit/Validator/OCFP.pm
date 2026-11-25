package Genesis::Kit::Validator::OCFP;
use v5.20;
use warnings;

use File::Basename qw/dirname/;
use File::Spec ();

# Where the shared, curated configs live: an ocfp/ directory beside
# this module.  Everything under lib/ is installed with the modules,
# so the same lookup works from an install, from KIT_VALIDATOR_LIB and
# from a clone.  `our` so a test can point it elsewhere.
our $SHARED_DIR = File::Spec->catdir(dirname(File::Spec->rel2abs(__FILE__)), 'ocfp');

my $NAME = qr/[a-z0-9][a-z0-9_-]*/;

sub shared_dir { $SHARED_DIR }

# parse_selection - turn an ocfp_config option into an ordered list of
# config names.  "base-aws+multi-az" and [qw/base-aws multi-az/] mean
# the same thing: a base, then add-ins merged over it in order.
sub parse_selection {
	my ($class, $selection) = @_;
	return [] unless defined $selection;
	die "ocfp_config must be a name, a '+'-joined string of names, or an arrayref of them\n"
		if ref $selection && ref $selection ne 'ARRAY';

	my @names;
	for my $entry (ref $selection ? @$selection : ($selection)) {
		die "ocfp_config: an entry is undefined or not a plain string\n"
			if !defined $entry || ref $entry;
		# -1 keeps trailing empty fields, so "base-aws+" is caught below.
		my @parts = split /\+/, $entry, -1;
		@parts = ('') unless @parts;
		for my $name (@parts) {
			die "ocfp_config: '$entry' has an invalid config name '$name' ".
			    "(lowercase letters, digits, '-' and '_' only)\n"
				unless $name =~ /\A$NAME\z/;
			push @names, $name;
		}
	}
	return \@names;
}

# resolve - the file a config name refers to.  A kit's own
# spec/ocfp/<name>.yml wins over the shared set, so a kit can override
# a shared config or add one of its own.
sub resolve {
	my ($class, $name, $kit_dir) = @_;
	my $local  = "$kit_dir/spec/ocfp/$name.yml";
	my $shared = "$SHARED_DIR/$name.yml";
	return $local  if -f $local;
	return $shared if -f $shared;
	die "ocfp_config: no config named '$name'.  Looked for:\n".
	    "  $local\n".
	    "  $shared\n";
}

# merge - combine configs in order.  Each is a flat map of vault path,
# relative to the bloc root, to that secret's key/value pairs -- the
# shape `ocfp vault export` writes.  Later configs win key by key.  A
# null value removes a key and a null path removes the whole secret,
# so an add-in can take something away as well as add it.
sub merge {
	my ($class, @configs) = @_;
	my %merged;
	for my $config (@configs) {
		die "ocfp_config: a config file must be a map of vault paths to key/value pairs\n"
			unless ref $config eq 'HASH';
		for my $raw (sort keys %$config) {
			my $path = _normalize_path($raw);
			die "ocfp_config: a config file has an empty vault path\n" unless length $path;
			my $secret = $config->{$raw};
			if (!defined $secret) {
				delete $merged{$path};
				next;
			}
			die "ocfp_config: '$path' must map to key/value pairs\n"
				unless ref $secret eq 'HASH';
			for my $key (keys %$secret) {
				if (defined $secret->{$key}) { $merged{$path}{$key} = $secret->{$key} }
				else                         { delete $merged{$path}{$key} if $merged{$path} }
			}
			delete $merged{$path} unless $merged{$path} && %{$merged{$path}};
		}
	}
	return \%merged;
}

# bloc_root - the vault path of the bloc, given an environment's config
# base.  Genesis reads <mount><bloc>/<mgmt|ocf>; the bloc is everything
# before that last segment.  A config is loaded for the whole bloc, so
# one file serves both environment types.
sub bloc_root {
	my ($class, $config_base) = @_;
	my $base = _normalize_path($config_base);
	die "ocfp_config: cannot find the bloc in config base '".($config_base // '')."': ".
	    "expected it to end in /mgmt or /ocf\n"
		unless $base =~ s{/(?:mgmt|ocf)\z}{} && length $base;
	return $base;
}

# vault_secrets - the merged config as absolute vault paths, ready to
# import.
sub vault_secrets {
	my ($class, $root, $merged) = @_;
	$root = _normalize_path($root);
	return { map { ("$root/$_" => $merged->{$_}) } keys %$merged };
}

# load - read and merge the named configs for a kit.  Needs Genesis
# for its YAML reader; everything above does not.
sub load {
	my ($class, $names, $kit_dir) = @_;
	require Genesis;
	my @configs;
	for my $name (@$names) {
		my $file = $class->resolve($name, $kit_dir);
		my $data = Genesis::load_yaml_file($file);
		die "ocfp_config: $file is not a map of vault paths to key/value pairs\n"
			unless ref $data eq 'HASH';
		push @configs, $data;
	}
	return $class->merge(@configs);
}

sub _normalize_path {
	my ($path) = @_;
	return join('/', grep { length } split(m{/+}, $path // ''));
}

1;

__END__

=head1 NAME

Genesis::Kit::Validator::OCFP - Canned OCFP bloc configs for spec environments

=head1 SYNOPSIS

  test_env(name => 'resolute-mgmt', ocfp_config => 'base-aws');
  test_env(name => 'resolute-mgmt', ocfp_config => 'base-aws+multi-az');
  test_env(name => 'resolute-mgmt', ocfp_config => [qw/base-aws multi-az/]);

=head1 DESCRIPTION

An OCFP environment reads its bloc configuration from the vault, under
C<E<lt>secrets mountE<gt>config/E<lt>blocE<gt>/E<lt>mgmt|ocfE<gt>>.  Kit
hooks that call C<ocfp_config_lookup> need that data to be present.  A
spec environment names the config it wants with C<ocfp_config>, and the
Runner loads it into the test vault before the environment runs.

A selection is a base followed by optional add-ins, merged in order.
Each name resolves to C<spec/ocfp/E<lt>nameE<gt>.yml> in the kit if that
exists, and otherwise to the shared set shipped beside this module.

=head1 CONFIG FILES

A config file is a flat map of vault path, relative to the bloc root, to
that secret's key/value pairs.  This is the shape C<ocfp vault export>
writes.

  mgmt/net/subnets/ocfp-0:              { az: z1 }
  mgmt/net/subnets/ocfp-0/reserved-ips: { shield_ip: 10.0.2.197 }
  mgmt/fqdns:                           { shield: shield.example.com }

Later files win key by key.  A C<null> value removes a key, and a
C<null> path removes the whole secret:

  mgmt/net/subnets/ocfp-0/reserved-ips: { shield_ip: ~ }
  mgmt/fqdns: ~

A file covers the whole bloc, both C<mgmt/> and C<ocf/>, so one file
serves either kind of environment.

=cut
