package Mojolicious::Plugin::Minion;
use Mojo::Base 'Mojolicious::Plugin';

use Minion;
use Scalar::Util 'weaken';

sub register {
  my ($self, $app, $conf) = @_;

  push @{$app->commands->namespaces}, 'Minion::Command';

  my $minion = Minion->new(each %$conf);
  weaken $minion->app($app)->{app};
  $app->helper(minion => sub {$minion});
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Minion - Minion job queue plugin

=head1 SYNOPSIS

  # Mojolicious (choose a backend)
  $self->plugin(Minion => {File => '/home/sri/minion.db'});
  $self->plugin(Minion => {Pg   => 'postgresql://postgres@/test'});

  # Mojolicious::Lite (choose a backend)
  plugin Minion => {File => '/home/sri/minion.db'};
  plugin Minion => {Pg   => 'postgresql://postgres@/test'};

  # Add tasks to your application
  app->minion->add_task(slow_log => sub {
    my ($job, $msg) = @_;
    sleep 5;
    $job->app->log->debug(qq{Received message "$msg"});
  });

  # Start jobs from anywhere in your application
  $c->minion->enqueue(slow_log => ['test 123']);

  # Perform jobs in your tests
  $t->get_ok('/start_slow_log_job')->status_is(200);
  $t->get_ok('/start_another_job')->status_is(200);
  $t->app->minion->perform_jobs;

=head1 DESCRIPTION

L<Mojolicious::Plugin::Minion> is a L<Mojolicious> plugin for the L<Minion> job
queue.

=head1 HELPERS

L<Mojolicious::Plugin::Minion> implements the following helpers.

=head2 minion

  my $minion = $app->minion;
  my $minion = $c->minion;

Get L<Minion> object for application.

  # Add job to the queue
  $c->minion->enqueue(foo => ['bar', 'baz']);

  # Perform jobs for testing
  $app->minion->perform_jobs;

=head1 METHODS

L<Mojolicious::Plugin::Minion> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new, {File => '/home/sri/minion.db'});

Register plugin in L<Mojolicious> application.

=head1 SEE ALSO

L<Minion>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
