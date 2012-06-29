package Modification::Log;

use base 'Modification::DBI';

__PACKAGE__->table('log');
__PACKAGE__->columns(All => qw/id last_modify_time/);

sub log {
    my $class = shift;
    my $path = shift;

    $class->search(id => $path)->delete_all;
    $class->insert({
        id => $path,
        last_modify_time => time,
    });
}

sub create_table {
    shift->db_Main->do(qq{
        create table if not exists log (
            id varchar(255),
            last_modify_time TIMESTAMP default CURRENT_TIMESTAMP
        );
    });
}
1;

