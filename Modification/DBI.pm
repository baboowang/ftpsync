#!perl
package Modification::DBI;

use base 'Class::DBI';

Modification::DBI->connection('dbi:SQLite:modification.db', '', '', {sqlite_unicode => 1});
1;

