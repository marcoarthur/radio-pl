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
use List::Util qw(first);
use DDP;

binmode STDOUT, ":encoding(UTF-8)";
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
          say "outputting... '$1'\n";
        }
        return 0;
      },
    },
    on_exception => sub {
      warn "Failed to play radio $url";
    },
    on_finish => sub {
      say "finished playing $url";
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
my $kb_input = rx_from_event_array($keyboard, 'keyup')        # on keyup event
->pipe(
  op_map(                                                     
    sub { $typed .= $_->[0]; return { text => trim $typed } } # save any typed char, ignoring leading or ending whitespace 
  ),
  op_filter( sub ($txt, $idx) { length($txt->{text}) > 0 } ), # ignores text with less than 2 chars
  op_debounce_time(0.25),                                     # only after long pausing typing
);

my $index = 0;
# the next station
sub next_station {
  $index++;
  return $stations->[$index % $stations->size];
}

sub previous_station {
  $index--;
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
  $stations->each(
    sub ($x, $idx){
      say "$idx - $x->{station}{name}";
    }
  );
  my $playing = $stations->first(sub{ $_->{station}{playing} });
  say "current playing: $playing->{station}{name}" if $playing;
}

# all command table
my $cmds = {
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

$kb_input->subscribe(
  {
    next => sub ($in) {
      my $cmd = first { $cmds->{$_}{pattern} =~ $in->{text} } keys %$cmds;
      if ( $cmd ) { $cmds->{$cmd}->{func}->(); }
      else {
        warn "Unrecognized command '$in->{text}'\n";
        warn "Type 'h' for help\n";
      }
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
