#!/usr/bin/env perl

use Mojo::Base -strict, -signatures;

package Keyboard {
  use Mojo::Base 'Mojo::EventEmitter', -strict, -signatures;
  use Term::TermKey::Async qw( FORMAT_VIM KEYMOD_CTRL );
  has loop => sub { die "Need IOAsync loop" };

  sub new($class, @args) {
    my $self = $class->SUPER::new(@args);
    $self->setup;
    return $self;
  }

  sub setup ($self) {
    my $tka = Term::TermKey::Async->new(
      term => \*STDIN,

      on_key => sub ($tka, $key){
        $self->pressed($tka->format_key($key, FORMAT_VIM));
      },
    );
    $self->loop->add($tka);
  }

  sub pressed($self, $key) {
    $self->emit( 'keyup' => $key );
  }
}

package main;
use RxPerl::IOAsync ':all';
use IO::Async::Loop;
use Mojo::File qw(path);
use YAML qw(LoadFile);
use Mojo::Collection qw(c);
use IO::Async::Process;
use List::Util qw(first);
use Getopt::Long;

binmode STDOUT, ":encoding(UTF-8)";
STDOUT->autoflush(1);
my $loop = IO::Async::Loop->new;
RxPerl::IOAsync::set_loop($loop);

my $script = path($0);
my $stations;
my $index = 0;
my $cmds;
my %globals;

my @opts = qw( player=s conf=s vebose );

sub setup {
  GetOptions (\%globals, @opts) or die "Error parsing options";
  $globals{player}  //= 'mplayer';
  $globals{conf}    //= ($script->to_array->[-1] =~ s/\.pl$/\.yml/r);

  # get from yml radio data
  eval {
    $stations = c(LoadFile($globals{conf})->@*);
  };

  die "Cannot continue, error reading station data" if $@;
  die "No stations" if $stations->size == 0;
}

sub play_radio ($radio) {
  my $url = $radio->{station}{url};
  my $cmd = [$globals{player}, $url];

  my $process = IO::Async::Process->new(
    command => $cmd,
    stdout => {
      on_read => sub {
        my ( $stream, $buffref ) = @_;
        while( $$buffref =~ s/^(.*)\n// ) {
          say "outputting... '$1'\n";
        }
        return 0;
      },
    },
    on_exception => sub {
      warn "Failed to play radio $url";
      $radio->{station}{playing} = 0;
    },
    on_finish => sub {
      say "finished playing $url";
      $radio->{station}{playing} = 0;
    }
  );
  $radio->{station}{playing} = 1;
  return $process;
}

# create keyboard event source
my $keyboard = Keyboard->new(loop => $loop);

# Rx to get keyboard inputs
my $kb_input = rx_from_event_array($keyboard, 'keyup')
->pipe(
  op_map(
    sub ($typed, $idx){ return { text => $typed->[0] } }
  ),
);

# the next station
sub next_station {
  $index++;
  return $stations->[$index % $stations->size];
}

sub previous_station {
  $index--;
  return $stations->[$index % $stations->size];
}

sub curr_station {
  return $stations->first(sub {$_->{station}{playing}});
}

# manage playing station
sub play ($radio){
  # check running station and stop the radio first
  my $on_play = curr_station;
  if ($on_play) {
    $on_play->{station}{process}->kill(15);
    $on_play->{station}{playing} = 0;
  }

  # start the new station
  $radio->{station}{process} = play_radio( $radio );
  $loop->add($radio->{station}{process});
}

sub stop {
  undef $kb_input;
  $loop->stop;
}

sub help {
  say <<~'EOH';
  q - to quit
  n - to next station
  p - to previous station
  h - to help
  l - to list all stations
  EOH
}

sub list_all {
  my $list = '';
  $stations->each(sub ($x, $idx){ $list .= "$idx - $x->{station}{name}\n" });
  my $playing = curr_station;
  $list .= "current playing: $playing->{station}{name}\n" if $playing;
  say $list;
}

# all command table
sub process_user_input($input) {
  $cmds = {
    next => { 
      pattern => qr/^n$/i, 
      func => sub { play(next_station) } 
    },
    previous => { 
      pattern => qr/^p$/i,
      func => sub { play(previous_station) }
    },
    help => {
      pattern =>qr/^h$/i,
      func => sub { help }
    },
    list_all => {
      pattern => qr/^l$/i,
      func => sub {list_all}
    },
    stop => {
      pattern => qr/^q$/i,
      func => sub {stop}
    },
  };

  my $cmd = first { $input->{text} =~ $cmds->{$_}{pattern} } keys %$cmds;
  if ( $cmd ) { $cmds->{$cmd}{func}->(); }
  else {
    warn "Unrecognized command '$input->{text}'\n";
    warn "Type 'h' for help\n";
  }
}

$kb_input->subscribe(
  {
    next => sub ($in) { process_user_input($in) },
    error => sub { ... },
    complete => sub { say "Completed" }
  }
);

setup;
help;
$loop->run;
