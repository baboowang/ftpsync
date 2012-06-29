use utf8;

our $g_base_dir = 'f:/ad_manager/branch/code/';

#监控变化的目录
our $monitor_directories = [
    "${g_base_dir}",
];

#忽略的文件和目录
our $exclude = [
    qr/\.(?:swp|bak|db)$/, 
    qr/\.(svn|git)/, 
    qr/~$/,
];

#ftp
our ($ftphost, $ftpuser, $ftppwd) = (
    '10.241.10.198',  #ftp host
    'webftp', # ftp username
    'WD#sd7258' # ftp password
);

