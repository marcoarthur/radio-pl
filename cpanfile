requires 'Getopt::Long';
requires 'IO::Async::Loop';
requires 'IO::Async::Process';
requires 'List::Util';
requires 'Mojo::Base';
requires 'Mojo::Collection';
requires 'Mojo::File';
requires 'RxPerl::IOAsync';
requires 'Term::TermKey::Async';
requires 'YAML';

on test => sub {
    requires 'Encode';
    requires 'IPC::Run';
    requires 'Test2::V0';
    requires 'perl', 'v5.38.0';
    requires 'strictures', '2';
};
