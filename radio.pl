use Mojo::Base -strict, -signatures;

package Keyboard {
  use Mojo::Base 'Mojo::EventEmitter', -strict, -signatures;

  sub pressed($self, $key) {
    $self->emit( 'keyup' => $key );
  }
}

package main;
use RxPerl::IOAsync ':all';
use Term::TermKey::Async qw( FORMAT_VIM KEYMOD_CTRL );
use Mojo::Util qw(trim);
use IO::Async::Loop;
use Mojo::File qw(path);
use YAML qw(LoadFile);
use Mojo::Collection qw(c);
use IO::Async::Process;
use DDP;

my $loop = IO::Async::Loop->new;
RxPerl::IOAsync::set_loop($loop);

my $script = path($0);
my $stations;

# get from yml radio data
eval {
  my $data = $script->to_array->[-1] =~ s/\.pl$/\.yml/r;
  $stations = LoadFile($data);
  $stations = c(@$stations);
};

die "Cannot continue, error reading station data" if $@;
die "No stations" if $stations->size == 0;

sub play_radio ($url) {
  my $cmd = ['mplayer', $url];

  my $process = IO::Async::Process->new(
    command => $cmd,
    stdout => {
      on_read => sub {
        my ( $stream, $buffref ) = @_;
        while( $$buffref =~ s/^(.*)\n// ) {
          print "outputting... '$1'\n";
        }
        return 0;
      },
    },
    on_finish => sub {
      say "finished";
    }
  );
  return $process;
}

# create event source and attach to real source tka
my $keyboard = Keyboard->new;
my $tka = Term::TermKey::Async->new(
  term => \*STDIN,

  on_key => sub ($self, $key){
    $keyboard->pressed($self->format_key($key, FORMAT_VIM));
  },
);

# typed string
my $typed = '';

# Rx to get keyboard inputs
my $kb_input = rx_from_event_array($keyboard, 'keyup')                 # on keyup event
->pipe(
  op_map( sub { $typed .= $_->[0]; return { text => trim $typed } } ), # save any typed char, ignoring leading or ending whitespace
  op_filter( sub ($txt, $idx) { length($txt->{text}) > 0 } ),          # ignores text with less than 2 chars
  op_debounce_time(0.25),                                              # only after long pausing typing
  op_distinct_until_key_changed( 'text' ),                             # pass a new value if after pause typing it changed
);

# the next station
sub next_station {
  state $index = -1;
  $index++;
  return $stations->[$index % $stations->size];
}

# manage playing station
sub play ($radio){
  # check running station and stop the radio first
  my $on_play = $stations->first( sub { $_->{station}{playing} } );
  $on_play->{station}{playing} = 0 if $on_play;
  $on_play->{station}{process}->kill(15) if $on_play;

  # start the new station
  $radio->{station}{process} = play_radio( $radio->{station}{url} );
  $loop->add($radio->{station}{process});
  $radio->{station}{playing} = 1;
}

sub stop {
  undef $kb_input;
  $loop->stop;
}

$kb_input->subscribe(
  {
    next => sub ($in) {
      play(next_station) if $in->{text} =~ /ne?x?t?/i;
      stop if $in->{text} =~ /qu?i?t?/i;
      $typed = '';
    },
    error => sub {
      ...
    },
    complete => sub {
      say "Completed";
    }
  }
);

$loop->add( $tka );
$loop->run;
