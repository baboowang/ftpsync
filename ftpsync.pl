#!perl
use strict;
use warnings;

use threads;
use Data::Dump qw(dump);
use Encode::Locale;
use Encode;
use Modification::Log;
use File::Spec::Functions qw/catdir/;
use File::Basename 'dirname';
use File::Copy;
use Time::HiRes 'usleep';
use autodie;
use utf8;

chdir(dirname(__FILE__));

################################################################
require 'config.pl';

our (
    $g_base_dir, 
    $monitor_directories, 
    $exclude, 
    $ftphost, $ftpuser, $ftppwd
);


################################################################

#Monitor
sub start_monitor {
    my $threads = shift;
    eval {
        require Win32::API;
    };
    
    if ($@) {
        push @$threads, threads->create('start_default_monitor');
    } else {
        for my $path (@$monitor_directories) {
            push @$threads, async {
                (my $path_param = $path) =~ s#/#\\#g;
                my $cmd = "perl Win32\\monitor.pl $path_param";
                `$cmd`;
            };
        }
    }
}

sub start_default_monitor {
    use File::ChangeNotify;

	my $debug = shift;
	my $watcher = 
		File::ChangeNotify->instantiate_watcher(
			directories  => $monitor_directories,
			exclude       => $exclude,
		);

	print '*' x 80, "\n";
	print " " x 30, "FILE MONITOR START\n";
	print '*' x 80, "\n";
	while (my @events = $watcher->wait_for_events()) {
		for my $event (@events) {
			print $event->path(), ' - ', $event->type(), "\n" if $debug;
			my $type = $event->type();
			my $path = $event->path();

            modify_log($type, $path); 
		}
	}
}

sub modify_log {
    my ($type, $path) = @_;
    if ($type eq 'modify' or $type eq 'create') {
        Modification::Log->log($path);
    } elsif ($type eq 'delete') {
        Modification::Log->search(id => $path)->delete_all;
    }
}

#Ftp
sub mftp {
    use utf8;
    binmode(STDOUT, ':encoding(locale)');

	print '*' x 80, "\n";
	print " " x 30, "FTP SYNC CONSOLE\n";
	print '*' x 80, "\n";
    CMD->h;
	while (my $line = <STDIN>) {
		chomp $line;
		if ($line eq '') {
			next;
		}
		my @takens = split /\s+/, $line;
		my $cmd = shift @takens;
		my %alias = (
			'help' => 'h',
			'?' => 'h',
			'upload' => 'u',
			'show' => 's',
			'rm' => 'r',
			'remove' => 'r',
		);
		if (exists $alias{$cmd}) {
			$cmd = $alias{$cmd};
		}
		if (CMD->can($cmd)) {
			CMD->$cmd(@takens);
		} else {
			print 'Valid cmd!', "\n";
		}
	}
}

############################################################################################
#Ftp command
package CMD;
use Net::FTP::AutoReconnect;
use Modification::Log;
use Data::Dumper qw/Dumper/;

my $ftp = new Net::FTP::AutoReconnect($ftphost, Debug => 0)
    or die "Cannot connect to $ftphost: $@";

$ftp->login($ftpuser, $ftppwd)
    or die "Cannot login ", $ftp->message;
$ftp->binary;

my @logs;

my $upload = sub {
    my $path = shift;
    (my $f = $path) =~ s{^$g_base_dir}{};
    
    my $remote_dir_prefix = '/opt/op/';
    
    my ($remote_dir, $remote_file) = ($remote_dir_prefix.$f) =~ m{^(.+?)([^/]+)$};
    
    print "... Uploading $f\n";
	
	#create remote directory
	if (-d $path) {
		$remote_dir = $remote_dir . $remote_file;
		unless ($ftp->mkdir($remote_dir, 1)) {
			print "mkdir $remote_dir failed\n";
			return 0;
		}
		print "Create remote direcotyr $remote_dir\n";
		return 1;
	}
    
    $ftp->mkdir($remote_dir);

    #print "$remote_dir, $remote_file\n";
    unless ($ftp->cwd($remote_dir)) {
        print "cwd $remote_dir failed\n";
        return 0;
    }
    #print "$path\n";
    unless ($ftp->put($path, $remote_file)) {
        print "put $path, $remote_file failed\n";
        return 0;
    }
    
    print "Upload $f\n";
    return 1;
};

sub s {
    @logs = Modification::Log->retrieve_from_sql(qq{
        1 ORDER BY last_modify_time DESC        
    });
    my $i = 1;
    print "-" x 80, "\n";
    for my $log (@logs) {
        my $path = $log->{id};
        $path =~ s{^$g_base_dir}{};
        print "$i, ", $path, "\n";
        $i++;
    }
    unless (@logs) {
        print "No modified files.\n";
    }
    print "-" x 80, "\n";

    if (@logs && @_ && ($_[0] eq 'u' || (@_ == 2 && $_[1] eq 'u'))) {
        __PACKAGE__->u();
    }
}

sub r {
    shift;
    my @index = @_;

    if ($#index == 0 && $index[0] eq 'all') {
        @index = (1..$#logs+1);
    }

    for my $index (@index) {
        my $log = $logs[$index - 1];
        if ($log) {
            $log->delete;
        }
    }

   &s();
}


sub u {
    shift;
    my @index = @_;

    if ($#index == -1) {
        @index = (1..$#logs+1);
    }

    my %stat = (succ => 0, fail => 0);
	my %path = map {$logs[$_ - 1]{id} => $_} grep {$logs[$_ - 1]} @index;
    for my $path (sort keys %path) {
		my $index = $path{$path};
        my $log = $logs[$index - 1];
		if ($upload->($path) and $log->delete) {
			$stat{succ}++;
		} else {
			$stat{fail}++;
		}
    }

    print '-' x 80, "\n";
    print "Upload finished. succ:", $stat{succ}, ' fail:', $stat{fail}, "\n";
    print '-' x 80, "\n";
}

sub h {
print '-' x 80, "\n";
print <<USAGE;
USAGE: 

. s[how] [options] 显示上传文件列表.
options:
    u 立即上传整个文件列表.

. r[m] [options] 将文件从上传列表中移除
options:
    <index> 移除指定的索引文件。索引号即show命令列出的列表中前面的数字。 
    all     将上传列表清空, 默认.

. u[pload] [options] 上传文件 
    <index> 上传指定索引的文件.
    all     将上传列表中所有文件进行上传, 默认.

. h[elp] | ?  显示帮助.
USAGE
print '-' x 80, "\n";
}
1;

package main;
if (@ARGV) {
	if ($ARGV[0] eq 'monitor') {
		start_monitor(1);
		exit;
	}

	if ($ARGV[0] eq 'ftp') {
		mftp();
		exit;
	}
}

my $threads = [];

start_monitor($threads);

mftp();

=dis
$SIG{INT} = sub {
    $_->kill('KILL')->detach() for @$threads;
};
=cut

$_->join for @$threads;
