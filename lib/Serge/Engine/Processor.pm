package Serge::Engine::Processor;

use strict;

use Serge::Engine::Job;

sub new {
    my ($class, $engine, $config) = @_;

    die "engine object not provided" unless $engine;
    die "config object not provided" unless $config;

    my $self = {
        engine => $engine,
        config => $config,
    };
    bless $self, $class;

    return $self;
}

sub run {
    my ($self, $dry_run) = @_;

    $self->{total_jobs} = 0;
    $self->{skipped_jobs} = 0;
    $self->{failed_jobs} = 0;

    foreach my $job_data (@{$self->{config}->{data}->{jobs}}) {
        $self->{total_jobs}++;

        my $job;

        eval {
            # create a job object — this will validate the job description,
            # load plugins, validate their data and die if there's any error
            $job = Serge::Engine::Job->new($job_data, $self->{engine}, $self->{config}->{base_dir});
            print "Job definition is OK\n" if $dry_run;
        };

        if ($@) {
            print "Job '$job_data->{id}' will be skipped: $@\n";
            $self->{skipped_jobs}++;
            next;
        }

        eval {
            $self->{engine}->process_job($job) unless $dry_run;
        };

        if ($@) {
            print "Exception occurred while processing job '$job_data->{id}': $@\n";
            $self->{failed_jobs}++;
            next;
        }
    }
}

sub dry_run {
    my $self = shift;

    $self->run(1);
}

1;