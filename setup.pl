#!/usr/bin/perl

use File::Copy;

sub install_modules {
    my @modules = @_;

    if ($^O ~~ /Win32/i && system('ppm help > NUL 2>&1') == 0) {
        system("ppm install $_") for @modules; 
    } else {
        system("cpan $_") for @modules;
    }
}


install_modules(
    qw/Unicode::String File::ChangeNotify Class::DBI Net::FTP::AutoReconnect Data::Dumper Encode Encode::Locale/
);

move('modification.db.origin', 'modification.db') unless -e 'modification.db'; 

