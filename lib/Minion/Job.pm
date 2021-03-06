package Minion::Job;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::IOLoop;
use POSIX 'WNOHANG';

has args => sub { [] };
has [qw(id minion task)];

sub app { shift->minion->app }

sub fail {
  my $self = shift;
  my $err  = shift // 'Unknown error';
  my $ok   = $self->minion->backend->fail_job($self->id, $err);
  return $ok ? !!$self->emit(failed => $err) : undef;
}

sub finish {
  my ($self, $result) = @_;
  my $ok = $self->minion->backend->finish_job($self->id, $result);
  return $ok ? !!$self->emit(finished => $result) : undef;
}

sub info { $_[0]->minion->backend->job_info($_[0]->id) }

sub is_finished {
  my ($self, $pid) = @_;
  return undef unless waitpid($pid, WNOHANG) == $pid;
  $? ? $self->fail("Non-zero exit status (@{[$? >> 8]})") : $self->finish;
  return 1;
}

sub perform {
  my $self = shift;
  waitpid $self->start, 0;
  $? ? $self->fail("Non-zero exit status (@{[$? >> 8]})") : $self->finish;
}

sub remove { $_[0]->minion->backend->remove_job($_[0]->id) }

sub retry { $_[0]->minion->backend->retry_job($_[0]->id, $_[1]) }

sub start {
  my $self = shift;

  # Parent
  die "Can't fork: $!" unless defined(my $pid = fork);
  $self->emit(spawn => $pid) and return $pid if $pid;

  # Reset event loop
  Mojo::IOLoop->reset;

  # Child
  my $task = $self->task;
  $self->app->log->debug(
    qq{Performing job "@{[$self->id]}" with task "$task" in process $$});
  my $cb = $self->minion->tasks->{$task};
  $self->fail($@) unless eval { $self->$cb(@{$self->args}); 1 };
  exit 0;
}

1;

=encoding utf8

=head1 NAME

Minion::Job - Minion job

=head1 SYNOPSIS

  use Minion::Job;

  my $job = Minion::Job->new(id => $id, minion => $minion, task => 'foo');

=head1 DESCRIPTION

L<Minion::Job> is a container for L<Minion> jobs.

=head1 EVENTS

L<Minion::Job> inherits all events from L<Mojo::EventEmitter> and can emit the
following new ones.

=head2 failed

  $job->on(failed => sub {
    my ($job, $err) = @_;
    ...
  });

Emitted in the worker process managing this job or the process performing it,
after it has transitioned to the C<failed> state.

  $job->on(failed => sub {
    my ($job, $err) = @_;
    say "Something went wrong: $err";
  });

=head2 finished

  $job->on(finished => sub {
    my ($job, $result) = @_;
    ...
  });

Emitted in the worker process managing this job or the process performing it,
after it has transitioned to the C<finished> state.

  $job->on(finished => sub {
    my ($job, $result) = @_;
    my $id = $job->id;
    say "Job $id is finished.";
  });

=head2 spawn

  $job->on(spawn => sub {
    my ($job, $pid) = @_;
    ...
  });

Emitted in the worker process managing this job, after a new process has been
spawned for processing.

  $job->on(spawn => sub {
    my ($job, $pid) = @_;
    my $id = $job->id;
    say "Job $id running in process $pid";
  });

=head1 ATTRIBUTES

L<Minion::Job> implements the following attributes.

=head2 args

  my $args = $job->args;
  $job     = $job->args([]);

Arguments passed to task.

=head2 id

  my $id = $job->id;
  $job   = $job->id($id);

Job id.

=head2 minion

  my $minion = $job->minion;
  $job       = $job->minion(Minion->new);

L<Minion> object this job belongs to.

=head2 task

  my $task = $job->task;
  $job     = $job->task('foo');

Task name.

=head1 METHODS

L<Minion::Job> inherits all methods from L<Mojo::EventEmitter> and implements
the following new ones.

=head2 app

  my $app = $job->app;

Get application from L<Minion/"app">.

  # Longer version
  my $app = $job->minion->app;

=head2 fail

  my $bool = $job->fail;
  my $bool = $job->fail('Something went wrong!');
  my $bool = $job->fail({msg => 'Something went wrong!'});

Transition from C<active> to C<failed> state.

=head2 finish

  my $bool = $job->finish;
  my $bool = $job->finish('All went well!');
  my $bool = $job->finish({msg => 'All went well!'});

Transition from C<active> to C<finished> state.

=head2 info

  my $info = $job->info;

Get job information.

  # Check job state
  my $state = $job->info->{state};

  # Get job result
  my $result = $job->info->{result};

These fields are currently available:

=over 2

=item args

Job arguments.

=item created

Time job was created.

=item delayed

Time job was delayed to.

=item finished

Time job was finished.

=item priority

Job priority.

=item result

Job result.

=item retried

Time job has been retried.

=item retries

Number of times job has been retried.

=item started

Time job was started.

=item state

Current job state.

=item task

Task name.

=item worker

Id of worker that is processing the job.

=back

=head2 is_finished

  my $bool = $job->is_finished($pid);

Check if job performed with L</"start"> is finished.

=head2 perform

  $job->perform;

Perform job in new process and wait for it to finish.

=head2 remove

  my $bool = $job->remove;

Remove C<failed>, C<finished> or C<inactive> job from queue.

=head2 retry

  my $bool = $job->retry;
  my $bool = $job->retry({delay => 10});

Transition from C<failed> or C<finished> state back to C<inactive>.

These options are currently available:

=over 2

=item delay

  delay => 10

Delay job for this many seconds (from now).

=back

=head2 start

  my $pid = $job->start;

Perform job in new process, but do not wait for it to finish.

  # Perform two jobs concurrently
  my $pid1 = $job1->start;
  my $pid2 = $job2->start;
  my ($first, $second);
  sleep 1
    until $first  ||= $job1->is_finished($pid1)
    and   $second ||= $job2->is_finished($pid2);

=head1 SEE ALSO

L<Minion>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
