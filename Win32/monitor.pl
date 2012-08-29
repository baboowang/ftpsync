#!perl
use strict;
use warnings;
use File::Basename 'dirname';
use lib dirname(__FILE__) . '/..';
use Modification::Log;
use Encode::Locale;
use Encode;
use utf8;
use threads;
use threads::shared;

my %cache : shared;

my $thr = async {
    while (1) {
        my %records;
        {
            lock(%cache);
            %records = %cache;
            %cache = ();
        }

        if (scalar(%records)) {
            my $dbh = Modification::Log->db_Main;
            $dbh->begin_work;
            for my $path (keys %records) {
                my ($action, $last_time) = $records{$path} =~ /^(.)(\d+)$/;

                if ($action eq '+') {
                    Modification::Log->log($path);
                    $dbh->do(qq{
                        insert or ignore into log (id, last_modify_time) values ('$path', $last_time)
                    });
                } else {
                    $dbh->do(qq{
                        delete from log where id='$path'
                    });
                }
            }
            $dbh->commit;
        }
        sleep 1;
    }
};

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
    my $time = time;
    if ($type eq 'modify' or $type eq 'create') {
        if ($cache{$path} and $cache{$path} =~ /^\+/) {
            return;
        }
        $cache{$path} = '+' . $time;
        #Modification::Log->log($path);
    } elsif ($type eq 'delete') {
        #print "delete $path\n";
        $cache{$path} = '-' . $time;
        #Modification::Log->search(id => $path)->delete_all;
    }
}

$thr->join;
