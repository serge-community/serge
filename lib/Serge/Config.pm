package Serge::Config;

use strict;

no warnings qw(redefine);

use Config::Neat::Inheritable;
use Config::Neat::Schema;
use File::Basename;
use File::Spec::Functions qw(rel2abs);
use Serge::Util;

#
# Initialize object
#
sub new {
    my ($class, $path) = @_;

    die "path not provided" unless $path;
    $path = rel2abs($path);

    # Load config file
    my $data;

    my $s = Config::Neat::Schema->new();
    $s->load(dirname(__FILE__).'/config_schema.serge');

    my $c = Config::Neat::Inheritable->new();
    $data = $c->parse_file($path);

    die "Config is not a hash\n" unless ref($data) eq 'HASH';

    $s->validate($data);

    # Check config validity

    my $self = {
        base_dir => dirname($path),
        data => $data,
    };
    bless $self, $class;

    return $self;
}

sub abspath {
    my ($self, $path) = @_;

    return Serge::Util::abspath($self->{base_dir}, $path);
}

sub chdir {
    my ($self) = @_;

    chdir($self->{base_dir});
}

#
# Get database sources
#
sub get_db_sources {
    my $self = shift;

    my %db_sources;

    for my $job (@{$self->{data}->{jobs}}) {
        # skip configs that don't have the db_source defined
        if (exists $job->{db_source}) {
            my $value = {};
            my $key = join("\001", map {$value->{$_} = subst_macros($job->{$_}); $job->{$_}} qw(db_source db_username db_password));
            $db_sources{$key} = $value unless exists $db_sources{$key};
        }
    }

    return \%db_sources;
}

#
# Test if any job from the provided hash exists in the config
#
sub any_job_exists {
    my ($self, $jobs) = @_;

    for my $job (@{$self->{data}->{jobs}}) {
        return 1 if exists $jobs->{$job->{id}};
    }

    return undef;
}

#
# Test if any language from the provided hash exists in the config
#
sub any_language_exists {
    my ($self, $languages) = @_;

    for my $job (@{$self->{data}->{jobs}}) {
        map {
            return 1 if exists $languages->{$_}
        } @{$job->{destination_languages}};
    }

    return undef;
}

1;