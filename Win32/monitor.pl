#!perl
use strict;
use warnings;
use File::Basename 'dirname';
use lib dirname(__FILE__) . '/..';
use Modification::Log;
use Encode::Locale;
use Encode;
use utf8;

binmode(STDOUT, ':encoding(locale)');

my $dir = $ARGV[0];

die "Directory not exists" unless $dir && -d $dir;

chdir(dirname(__FILE__) . '/..');

require 'config.pl';

our $exclude;

my %actions = (
    'create' => 1, 
    'modify' => 1, 
    'delete' => 1
);

my $cmd = "Win32/DirectoryChangeWatcher.exe $dir"; 
my $pid = open my $fh, '-|', $cmd or die;

binmode($fh, ':encoding(locale)');

MAIN:
while(<$fh>) {
    s/\s+$//g;

    my ($action, $filepath) = m/^(\w+)\s(.+)$/;

    next unless $action && exists $actions{$action};

    for my $exclude (@$exclude) {
        next MAIN if $filepath =~ m/$exclude/xsmi;        
    }

    $filepath =~ tr#\\#/#;
    
    #print "pl:$action $filepath\n";

    modify_log($action, $filepath);
}

sub modify_log {
    my ($type, $path) = @_;
    if ($type eq 'modify' or $type eq 'create') {
        Modification::Log->log($path);
    } elsif ($type eq 'delete') {
        Modification::Log->search(id => $path)->delete_all;
    }
}
