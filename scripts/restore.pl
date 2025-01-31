#!/usr/bin/perl
# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . "/Kernel/cpan-lib";

use Getopt::Std;

use Kernel::System::ObjectManager;

# get options
my %Opts;
my $DB     = '';
my $DBDump = '';
getopt( 'hbd', \%Opts );
if ( exists $Opts{h} ) {
    print "restore.pl - restore script\n";
    print "Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de\n";
    print "usage: restore.pl -b /data_backup/<TIME>/ -d /opt/kix17/\n";
    exit 1;
}
if ( !$Opts{b} ) {
    print STDERR "ERROR: Need -b for backup directory\n";
    exit 1;
}
elsif ( !-d $Opts{b} ) {
    print STDERR "ERROR: No such directory: $Opts{b}\n";
    exit 1;
}
if ( !$Opts{d} ) {
    print STDERR "ERROR: Need -d for destination directory\n";
    exit 1;
}
elsif ( !-d $Opts{d} ) {
    print STDERR "ERROR: No such directory: $Opts{d}\n";
    exit 1;
}

# restore config
print "Restore $Opts{b}/Config.tar.gz ...\n";
chdir( $Opts{d} );
if ( -e "$Opts{b}/Config.tar.gz" ) {
    system("tar -xzf $Opts{b}/Config.tar.gz");
}

# create common objects
local $Kernel::OM = Kernel::System::ObjectManager->new(
    'Kernel::System::Log' => {
        LogPrefix => 'KIX-restore.pl',
    },
);

my $DatabaseHost = $Kernel::OM->Get('Kernel::Config')->Get('DatabaseHost');
my $Database     = $Kernel::OM->Get('Kernel::Config')->Get('Database');
my $DatabaseUser = $Kernel::OM->Get('Kernel::Config')->Get('DatabaseUser');
my $DatabasePw   = $Kernel::OM->Get('Kernel::Config')->Get('DatabasePw');
my $DatabaseDSN  = $Kernel::OM->Get('Kernel::Config')->Get('DatabaseDSN');
my $ArticleDir   = $Kernel::OM->Get('Kernel::Config')->Get('ArticleDir');

# decrypt pw (if needed)
if ( $DatabasePw =~ m/^\{(.*)\}$/ ) {
    $DatabasePw = $Kernel::OM->Get('Kernel::System::DB')->_Decrypt($1);
}

# check db backup support
if ( $DatabaseDSN =~ m/:mysql/i ) {
    $DB     = 'MySQL';
    $DBDump = 'mysql';
}
elsif ( $DatabaseDSN =~ m/:pg/i ) {
    $DB     = 'PostgreSQL';
    $DBDump = 'psql';
    if ( $DatabaseDSN !~ m/host=/i ) {
        $DatabaseHost = ''
    }
}
else {
    print STDERR "ERROR: Can't backup, no database dump support!\n";
    exit 1;
}

# check needed programs
for my $CMD ( 'cp', 'tar', $DBDump ) {
    my $Installed = 0;
    open( my $Input, '-|', "which $CMD" );    ## no critic
    while (<$Input>) {
        $Installed = 1;
    }
    close $Input;
    if ( !$Installed ) {
        print STDERR "ERROR: Can't locate $CMD!\n";
        exit 1;
    }
}

# check database env
if ( $DB =~ m/mysql/i ) {
    $Kernel::OM->Get('Kernel::System::DB')->Prepare( SQL => "SHOW TABLES" );
    my $Check = 0;
    while ( my @RowTmp = $Kernel::OM->Get('Kernel::System::DB')->FetchrowArray() ) {
        $Check++;
    }
    if ($Check) {
        print STDERR
            "ERROR: Already existing tables in this database. A empty database is required for restore!\n";
        exit 1;
    }
}
else {
    $Kernel::OM->Get('Kernel::System::DB')->Prepare(
        SQL =>
            "SELECT table_name FROM information_schema.tables WHERE table_catalog = 'kix17' AND table_schema = 'public'",
    );
    my $Check = 0;
    while ( my @RowTmp = $Kernel::OM->Get('Kernel::System::DB')->FetchrowArray() ) {
        $Check++;
    }
    if ($Check) {
        print STDERR
            "ERROR: Already existing tables in this database. A empty database is required for restore!\n";
        exit 1;
    }
}

# restore
my $Home = $Kernel::OM->Get('Kernel::Config')->Get('Home');
chdir($Home);

# extract application
if ( -e "$Opts{b}/Application.tar.gz" ) {
    print "Restore $Opts{b}/Application.tar.gz ...\n";
    system("tar -xzf $Opts{b}/Application.tar.gz");
}

# extract vardir
if ( -e "$Opts{b}/VarDir.tar.gz" ) {
    print "Restore $Opts{b}/VarDir.tar.gz ...\n";
    system("tar -xzf $Opts{b}/VarDir.tar.gz");
}

# extract datadir
if ( -e "$Opts{b}/DataDir.tar.gz" ) {
    print "Restore $Opts{b}/DataDir.tar.gz ...\n";
    system("tar -xzf $Opts{b}/DataDir.tar.gz");
}

# import database
if ( $DB =~ m/mysql/i ) {
    print "create $DB\n";
    if ($DatabasePw) {
        $DatabasePw = "-p'$DatabasePw'";
    }
    if ( -e "$Opts{b}/DatabaseBackup.sql.gz" ) {
        print "decompresses SQL-file ...\n";
        system("gunzip $Opts{b}/DatabaseBackup.sql.gz");
        print "cat SQL-file into $DB database\n";
        system(
            "mysql -f -u$DatabaseUser $DatabasePw -h$DatabaseHost $Database < $Opts{b}/DatabaseBackup.sql"
        );
        print "compress SQL-file...\n";
        system("gzip $Opts{b}/DatabaseBackup.sql");
    }
    elsif ( -e "$Opts{b}/DatabaseBackup.sql.bz2" ) {
        print "decompresses SQL-file ...\n";
        system("bunzip2 $Opts{b}/DatabaseBackup.sql.bz2");
        print "cat SQL-file into $DB database\n";
        system(
            "mysql -f -u$DatabaseUser $DatabasePw -h$DatabaseHost $Database < $Opts{b}/DatabaseBackup.sql"
        );
        print "compress SQL-file...\n";
        system("bzip2 $Opts{b}/DatabaseBackup.sql");
    }
}
else {
    if ($DatabaseHost) {
        $DatabaseHost = "-h $DatabaseHost"
    }

    if ( -e "$Opts{b}/DatabaseBackup.sql.gz" ) {
        print "decompresses SQL-file ...\n";
        system("gunzip $Opts{b}/DatabaseBackup.sql.gz");

        # set password via environment variable if there is one
        if ($DatabasePw) {
            $ENV{'PGPASSWORD'} = $DatabasePw;
        }
        print "cat SQL-file into $DB database\n";
        system(
            "cat $Opts{b}/DatabaseBackup.sql | psql -U$DatabaseUser $DatabaseHost $Database"
        );
        print "compress SQL-file...\n";
        system("gzip $Opts{b}/DatabaseBackup.sql");
    }
    elsif ( -e "$Opts{b}/DatabaseBackup.sql.bz2" ) {
        print "decompresses SQL-file ...\n";
        system("bunzip2 $Opts{b}/DatabaseBackup.sql.bz2");

        # set password via environment variable if there is one
        if ($DatabasePw) {
            $ENV{'PGPASSWORD'} = $DatabasePw;
        }
        print "cat SQL-file into $DB database\n";
        system(
            "cat $Opts{b}/DatabaseBackup.sql | psql -U$DatabaseUser $DatabaseHost $Database"
        );
        print "compress SQL-file...\n";
        system("bzip2 $Opts{b}/DatabaseBackup.sql");
    }
}

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut
