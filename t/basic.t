use strictures 2;
use v5.38;
use Test2::V0;
use Encode qw(decode);
use IPC::Run qw(start pump finish timeout);
use Mojo::File qw(path);

my $script = './radio.pl';
my $conf =<<'EOC';
- station:
    name: Radio 1
    url: https://radio1.com
- station:
    name: Radio 2
    url: http://radio2.com
- station:
    name: Радио 3
    url: http://radio3.com
- station:
    name: Radio 4
    url: https://radio4.com
EOC
my $conf_file = '/tmp/test.yml';

my $help_expected =<<~'EOS';
q - to quit
n - to next station
p - to previous station
h - to help
l - to list all stations

EOS

path($conf_file)->spew($conf, 'UTF-8');

# on startup we send a help message
subtest start_radio => sub {
  my ($in,$out,$err);
  my $h = start [ 'perl', $script ], \$in, \$out, \$err,
                timeout(3, exception => 'slow radio start');

  # just quit radio
  $in = 'q'; $h->pump; $h->finish;

  is $out, $help_expected, 'As expected for start';
};

sub send_radio_cmd($cmd, $out) {
  my ($in, $err, $i);
  my $h = start [ 'perl', $script, "--conf=$conf_file", "--player=echo" ], \$in, $out, \$err, 
                timeout(3, exception => "slow radio command $cmd");
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
  1 - Radio 1
  2 - Radio 2
  3 - Радио 3
  4 - Radio 4

  EOL

  is decode('UTF8', $out), $help_expected . $list_radios, 'As expected after typing "l"';
};

subtest play_radio => sub {
  my $out;
  send_radio_cmd("n", \$out);
  my $out_expected = "outputting... http://radio2.com";

  is $out, $help_expected . $out_expected, "Ok and echo radio";
};

unlink $conf_file;
done_testing;
