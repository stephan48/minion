package Minion;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Minion::Job;
use Minion::Worker;
use Mojo::Loader 'load_class';
use Mojo::Server;
use Mojo::URL;
use Scalar::Util 'weaken';

has app => sub { Mojo::Server->new->build_app('Mojo::HelloWorld') };
has 'backend';
has missing_after => 86400;
has remove_after  => 864000;
has tasks         => sub { {} };

our $VERSION = '1.18';

sub add_task { ($_[0]->tasks->{$_[1]} = $_[2]) and return $_[0] }

sub enqueue { shift->backend->enqueue(@_) }

sub job {
  my ($self, $id) = @_;

  return undef unless my $job = $self->backend->job_info($id);
  return Minion::Job->new(
    args   => $job->{args},
    id     => $job->{id},
    minion => $self,
    task   => $job->{task}
  );
}

sub new {
  my $self = shift->SUPER::new;

  my $class = 'Minion::Backend::' . shift;
  my $e     = load_class $class;
  croak ref $e ? $e : qq{Backend "$class" missing} if $e;

  $self->backend($class->new(@_));
  weaken $self->backend->minion($self)->{minion};

  return $self;
}

sub perform_jobs {
  my $self   = shift;
  my $worker = $self->worker;
  while (my $job = $worker->register->dequeue(0)) { $job->perform }
  $worker->unregister;
}

sub repair { shift->_delegate('repair') }
sub reset  { shift->_delegate('reset') }

sub stats { shift->backend->stats }

sub worker {
  my $self = shift;
  my $worker = Minion::Worker->new(minion => $self);
  $self->emit(worker => $worker);
  return $worker;
}

sub _delegate {
  my ($self, $method) = @_;
  $self->backend->$method;
  return $self;
}

1;

=encoding utf8

=head1 NAME

Minion - Job queue

=head1 SYNOPSIS

  use Minion;

  # Connect to backend
  my $minion = Minion->new(File => '/home/sri/minion.db');
  my $minion = Minion->new(Pg   => 'postgresql://postgres@/test');

  # Add tasks
  $minion->add_task(something_slow => sub {
    my ($job, @args) = @_;
    sleep 5;
    say 'This is a background worker process.';
  });

  # Enqueue jobs
  $minion->enqueue(something_slow => ['foo', 'bar']);
  $minion->enqueue(something_slow => [1, 2, 3] => {priority => 5});

  # Perform jobs for testing
  $minion->enqueue(something_slow => ['foo', 'bar']);
  $minion->perform_jobs;

  # Build more sophisticated workers
  my $worker = $minion->repair->worker;
  while (int rand 2) {
    if (my $job = $worker->register->dequeue(5)) { $job->perform }
  }
  $worker->unregister;

=head1 DESCRIPTION

L<Minion> is a job queue for the L<Mojolicious|http://mojolicio.us> real-time
web framework with support for multiple backends, such as L<DBM::Deep> and
L<PostgreSQL|http://www.postgresql.org>.

A job queue allows you to process time and/or computationally intensive tasks
in background processes, outside of the request/response lifecycle. Among those
tasks you'll commonly find image resizing, spam filtering, HTTP downloads,
building tarballs, warming caches and basically everything else you can imagine
that's not super fast.

  use Mojolicious::Lite;

  plugin Minion => {Pg => 'postgresql://sri:s3cret@localhost/test'};

  # Slow task
  app->minion->add_task(poke_mojo => sub {
    my $job = shift;
    $job->app->ua->get('mojolicio.us');
    $job->app->log->debug('We have poked mojolicio.us for a visitor');
  });

  # Perform job in a background worker process
  get '/' => sub {
    my $c = shift;
    $c->minion->enqueue('poke_mojo');
    $c->render(text => 'We will poke mojolicio.us for you soon.');
  };

  app->start;

Background worker processes are usually started with the command
L<Minion::Command::minion::worker>, which becomes automatically available when
an application loads the plugin L<Mojolicious::Plugin::Minion>.

  $ ./myapp.pl minion worker

Jobs can be managed right from the command line with
L<Minion::Command::minion::job>.

  $ ./myapp.pl minion job

=head1 GROWING

And as your application grows, you can move tasks into application specific
plugins.

  package MyApp::Task::PokeMojo;
  use Mojo::Base 'Mojolicious::Plugin';

  sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(poke_mojo => sub {
      my $job = shift;
      $job->app->ua->get('mojolicio.us');
      $job->app->log->debug('We have poked mojolicio.us for a visitor');
    });
  }

  1;

Which are loaded like any other plugin from your application.

  # Mojolicious
  $app->plugin('MyApp::Task::PokeMojo');

  # Mojolicious::Lite
  plugin 'MyApp::Task::PokeMojo';

Every job can fail or succeed, but not get lost, the system is eventually
consistent and will preserve job results for as long as you like, depending on
L</"remove_after">. While individual workers can fail in the middle of
processing a job, the system will detect this and ensure that no job is left in
an uncertain state, depending on L</"missing_after">.

=head1 EVENTS

L<Minion> inherits all events from L<Mojo::EventEmitter> and can emit the
following new ones.

=head2 worker

  $minion->on(worker => sub {
    my ($minion, $worker) = @_;
    ...
  });

Emitted in the worker process after it has been created.

  $minion->on(worker => sub {
    my ($minion, $worker) = @_;
    my $id = $worker->id;
    say "Worker $$:$id started.";
  });

=head1 ATTRIBUTES

L<Minion> implements the following attributes.

=head2 app

  my $app = $minion->app;
  $minion = $minion->app(MyApp->new);

Application for job queue, defaults to a L<Mojo::HelloWorld> object.

=head2 backend

  my $backend = $minion->backend;
  $minion     = $minion->backend(Minion::Backend::File->new);

Backend, usually a L<Minion::Backend::File> or L<Minion::Backend::Pg> object.

=head2 missing_after

  my $after = $minion->missing_after;
  $minion   = $minion->missing_after(172800);

Amount of time in seconds after which workers without a heartbeat will be
considered missing and removed from the registry by L</"repair">, defaults to
C<86400> (1 day).

=head2 remove_after

  my $after = $minion->remove_after;
  $minion   = $minion->remove_after(86400);

Amount of time in seconds after which jobs that have reached the state
C<finished> will be removed automatically by L</"repair">, defaults to
C<864000> (10 days).

=head2 tasks

  my $tasks = $minion->tasks;
  $minion   = $minion->tasks({foo => sub {...}});

Registered tasks.

=head1 METHODS

L<Minion> inherits all methods from L<Mojo::EventEmitter> and implements the
following new ones.

=head2 add_task

  $minion = $minion->add_task(foo => sub {...});

Register a new task.

=head2 enqueue

  my $id = $minion->enqueue('foo');
  my $id = $minion->enqueue(foo => [@args]);
  my $id = $minion->enqueue(foo => [@args] => {priority => 1});

Enqueue a new job with C<inactive> state. Arguments get serialized, so you
shouldn't send objects, nested data structures with hash and array references
are fine though.

These options are currently available:

=over 2

=item delay

  delay => 10

Delay job for this many seconds (from now).

=item priority

  priority => 5

Job priority, defaults to C<0>.

=back

=head2 job

  my $job = $minion->job($id);

Get L<Minion::Job> object without making any changes to the actual job or
return C<undef> if job does not exist.

  # Check job state
  my $state = $minion->job($id)->info->{state};

  # Get job result
  my $result = $minion->job($id)->info->{result};

=head2 new

  my $minion = Minion->new(File => '/home/sri/minion.db');

Construct a new L<Minion> object.

=head2 perform_jobs

  $minion->perform_jobs;

Perform all jobs, very useful for testing.

=head2 repair

  $minion = $minion->repair;

Repair worker registry and job queue if necessary.

=head2 reset

  $minion = $minion->reset;

Reset job queue.

=head2 stats

  my $stats = $minion->stats;

Get statistics for jobs and workers.

=head2 worker

  my $worker = $minion->worker;

Build L<Minion::Worker> object.

=head1 REFERENCE

This is the class hierarchy of the L<Minion> distribution.

=over 2

=item * L<Minion>

=item * L<Minion::Backend>

=over 2

=item * L<Minion::Backend::File>

=item * L<Minion::Backend::Pg>

=back

=item * L<Minion::Command::minion>

=item * L<Minion::Command::minion::job>

=item * L<Minion::Command::minion::worker>

=item * L<Minion::Job>

=item * L<Minion::Worker>

=item * L<Mojolicious::Plugin::Minion>

=back

=head1 AUTHOR

Sebastian Riedel, C<sri@cpan.org>.

=head1 CREDITS

In alphabetical order:

=over 2

Andrey Khozov

Brian Medley

Paul Williams

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014-2015, Sebastian Riedel.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<https://github.com/kraih/minion>, L<Mojolicious::Guides>,
L<http://mojolicio.us>.

=cut
