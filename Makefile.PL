use 5.010001;

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Minion',
  VERSION_FROM => 'lib/Minion.pm',
  ABSTRACT     => 'Job Queue',
  AUTHOR       => 'Sebastian Riedel <sri@cpan.org>',
  LICENSE      => 'artistic_2',
  META_MERGE   => {
    requires  => {perl => '5.010001'},
    resources => {
      license    => 'http://www.opensource.org/licenses/artistic-license-2.0',
      homepage   => 'http://mojolicio.us',
      bugtracker => 'https://github.com/kraih/minion/issues',
      repository => 'https://github.com/kraih/minion.git',
      x_IRC      => 'irc://irc.perl.org/#mojo'
    },
    no_index => {directory => ['t']}
  },
  PREREQ_PM => {Mojolicious => '6.0', 'DBM::Deep' => '2.0011'},
  test      => {TESTS       => 't/*.t t/*/*.t'}
);
