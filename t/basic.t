use strictures 2;
use v5.38;
use Test2::V0;
use Encode qw(decode);
use IPC::Run qw(start pump finish timeout);

my $script = './radio.pl';
my $help_expected =<<~'EOS';
q - to quit
n - to next station
p - to previous station
h - to help
l - to list all stations

EOS

# on startup we send a help message
subtest start_radio => sub {
  my ($in,$out,$err);
  my $h = start [ 'perl', $script ], \$in, \$out, \$err, timeout(3);

  # just quit radio
  $in = 'q'; $h->pump; $h->finish;

  is $out, $help_expected, 'As expected for start';
};

sub send_radio_cmd($cmd, $out) {
  my ($in, $err, $i);
  my $h = start [ 'perl', $script ], \$in, $out, \$err, timeout(3);
  do {
    $out = '';
    $in = $cmd;
    $h->pump;
    $i++;
  } until (length $in == 0);

  # just quit radio to get the output
  $in = 'q'; $h->pump; $h->finish;

}

subtest print_help => sub {
  my $out;
  send_radio_cmd('h',\$out);
  # the help message twice (on start) and after 'h'
  is $out, $help_expected . $help_expected, 'As expected after typing "h"';
};

subtest list_radios => sub {
  my $out;
  send_radio_cmd('l', \$out);

  my $list_radios = <<~'EOL';
  1 - Classic Russian
  2 - Russian Music
  3 - Радио старого полковника
  4 - Radio USP
  5 - Radio JaH
  EOL

  is decode('UTF8', $out), $help_expected . $list_radios, 'As expected after typing "l"';
};

done_testing;
