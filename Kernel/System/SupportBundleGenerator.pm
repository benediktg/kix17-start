# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::SupportBundleGenerator;

use strict;
use warnings;

use Archive::Tar;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::CSV',
    'Kernel::System::JSON',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::Package',
    'Kernel::System::SupportDataCollector',
    'Kernel::System::Time',
);

## no critic qw(InputOutput::RequireBriefOpen)

=head1 NAME

Kernel::System::SupportBundleGenerator - support bundle generator

=head1 SYNOPSIS

All support bundle generator functions.

=head1 PUBLIC INTERFACE

=over 4

=item new()

create an object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $SupportBundleGeneratorObject = $Kernel::OM->Get('Kernel::System::SupportBundleGenerator');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash ref to object
    my $Self = {};
    bless( $Self, $Type );

    # cleanup the Home variable (remove tailing "/")
    $Self->{Home} = $Kernel::OM->Get('Kernel::Config')->Get('Home');
    $Self->{Home} =~ s{\/\z}{};

    $Self->{RandomID} = $Kernel::OM->Get('Kernel::System::Main')->GenerateRandomString(
        Length     => 8,
        Dictionary => [ 0 .. 9, 'a' .. 'f' ],
    );

    return $Self;
}

=item Generate()

Generates a support bundle tar or tar.gz with the following contents:
Support Data, Installed Packages, and another tar or tar.gz with all changed or new files in the
KIX installation directory.

    my $Result = $SupportBundleGeneratorObject->Generate();

Returns:

    $Result = {
        Success => 1,                                # Or false, in case of an error
        Data    => {
            Filecontent => \$Tar,                    # Outer tar content reference
            Filename    => 'SupportBundle.tar',      # The outer tar filename
            Filesize    =>  123                      # The size of the file in mega bytes
        },

=cut

sub Generate {
    my ( $Self, %Param ) = @_;

    if ( !-e $Self->{Home} . '/ARCHIVE' ) {
        my $Message = $Self->{Home} . '/ARCHIVE: Is missing, can not continue!';
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => $Message,
        );
        return {
            Success => 0,
            Message => $Message,
        };
    }

    my %SupportFiles;

    # get the list of installed packages
    ( $SupportFiles{PackageListContent}, $SupportFiles{PackageListFilename} ) = $Self->GeneratePackageList();
    if ( !$SupportFiles{PackageListFilename} ) {
        my $Message = 'Can not generate the list of installed packages!';
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => $Message,
        );
        return {
            Success => 0,
            Message => $Message,
        };
    }

    # get the support data
    ( $SupportFiles{SupportDataContent}, $SupportFiles{SupportDataFilename} ) = $Self->GenerateSupportData();
    if ( !$SupportFiles{SupportDataFilename} ) {
        my $Message = 'Can not collect the support data!';
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => $Message,
        );
        return {
            Success => 0,
            Message => $Message,
        };
    }

    # get the archive of custom files
    ( $SupportFiles{CustomFilesArchiveContent}, $SupportFiles{CustomFilesArchiveFilename} )
        = $Self->GenerateCustomFilesArchive();
    if ( !$SupportFiles{CustomFilesArchiveFilename} ) {
        my $Message = 'Can not generate the custom files archive!';
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => $Message,
        );
        return {
            Success => 0,
            Message => $Message,
        };
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # save and create archive
    my $TempDir = $ConfigObject->Get('TempDir') . '/SupportBundle';

    if ( !-d $TempDir ) {
        mkdir $TempDir;
    }

    $TempDir = $ConfigObject->Get('TempDir') . '/SupportBundle/' . $Self->{RandomID};

    if ( !-d $TempDir ) {
        mkdir $TempDir;
    }

    # remove all files
    my @ListOld = glob( $TempDir . '/*' );
    for my $File (@ListOld) {
        unlink $File;
    }

    # get main object
    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

    my @List;
    for my $Key (qw(PackageList SupportData CustomFilesArchive)) {

        if ( $SupportFiles{ $Key . 'Filename' } && $SupportFiles{ $Key . 'Content' } ) {

            my $Location = $TempDir . '/' . $SupportFiles{ $Key . 'Filename' };
            my $Content  = $SupportFiles{ $Key . 'Content' };

            my $FileLocation = $MainObject->FileWrite(
                Location   => $Location,
                Content    => $Content,
                Mode       => 'binmode',
                Type       => 'Local',
                Permission => '644',
            );

            push @List, $Location;
        }
    }

    # get time object
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    my ( $s, $m, $h, $D, $M, $Y, $wd, $yd, $dst ) = $TimeObject->SystemTime2Date(
        SystemTime => $TimeObject->SystemTime(),
    );
    my $Filename = "SupportBundle_$Y-$M-$D" . '_' . "$h-$m";

    # add files to the tar archive
    my $Archive   = $TempDir . '/' . $Filename;
    my $TarObject = Archive::Tar->new();
    $TarObject->add_files(@List);
    $TarObject->write( $Archive, 0 ) || die "Could not write: $_!";

    # add files to the tar archive
    open( my $Tar, '<', $Archive ) or die "Can't open '$Archive': ?!";
    binmode $Tar;
    my $TmpTar = do {
        local $/ = undef;
        <$Tar>
    };
    close $Tar;

    # remove all files
    @ListOld = glob( $TempDir . '/*' );
    for my $File (@ListOld) {
        unlink $File;
    }

    # remove temporary directory
    rmdir $TempDir;

    if ( $Kernel::OM->Get('Kernel::System::Main')->Require('Compress::Zlib') ) {
        my $GzTar = Compress::Zlib::memGzip($TmpTar);

        # log info
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => 'Download Compress::Zlib end',
        );

        return {
            Success => 1,
            Data    => {
                Filecontent => \$GzTar,
                Filename    => $Filename . '.tar.gz',
                Filesize    => bytes::length($GzTar) / ( 1024 * 1024 ),
            },
        };
    }

    # log info
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => 'Download no Compress::Zlib end',
    );

    return {
        Success => 1,
        Data    => {
            Filecontent => \$TmpTar,
            Filename    => $Filename . '.tar',
            Filesize    => bytes::length($TmpTar) / ( 1024 * 1024 ),
        },
    };
}

=item GenerateCustomFilesArchive()

Generates a .tar or tar.gz file with all eligible changed or added files taking the ARCHIVE file as
a reference

    my ( $Content, $Filename ) = $SupportBundleGeneratorObject->GenerateCustomFilesArchive();

Returns:
    $Content  = $FileContentsRef;
    $Filename = 'application.tar';      # or 'application.tar.gz'

=cut

sub GenerateCustomFilesArchive {
    my ( $Self, %Param ) = @_;

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $TempDir = $ConfigObject->Get('TempDir') . '/SupportBundle';

    if ( !-d $TempDir ) {
        mkdir $TempDir;
    }

    $TempDir = $ConfigObject->Get('TempDir') . '/SupportBundle/' . $Self->{RandomID};

    if ( !-d $TempDir ) {
        mkdir $TempDir;
    }

    # remove all files
    my @ListOld = glob( $TempDir . '/*' );
    for my $File (@ListOld) {
        unlink $File;
    }

    my $CustomFilesArchive = $TempDir . '/application.tar';
    if ( -f $CustomFilesArchive ) {
        unlink $CustomFilesArchive || die "Can't unlink $CustomFilesArchive: $!";
    }

    # get a MD5Sum lookup table from all known files (from framework and packages)
    $Self->{MD5SumLookup} = $Self->_GetMD5SumLookup();

    # get the list of file to add to the Dump
    my @List = $Self->_GetCustomFileList( Directory => $Self->{Home} );

    # add files to the Dump
    my $TarObject = Archive::Tar->new();

    $TarObject->add_files(@List);

    # within the tar file the paths are not absolute, so leading "/" must be removed
    my $HomeWithoutSlash = $Self->{Home};
    $HomeWithoutSlash =~ s{\A\/}{};

    # Mask Passwords in Config.pm
    my $Config = $TarObject->get_content( $HomeWithoutSlash . '/Kernel/Config.pm' );

    if ( !$Config ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Kernel/Config.pm was not found in the modified files!",
        );
        return;
    }

    # get config for obfuscation
    my $Obfuscation = $ConfigObject->Get('SupportBundle::Obfuscation');

    # check obfuscation config
    if ( ref( $Obfuscation ) eq 'HASH' ) {
        # process obfuscation pattern
        PATTERN:
        for my $Pattern ( keys( %{ $Obfuscation } ) ) {
            next PATTERN if ( !$Pattern );
            # prepare replace pattern
            my $Replace = $Obfuscation->{ $Pattern };
            $Replace    =~ s/"/\\"/g;
            $Replace    = '"' . $Replace . '"';

            $Config =~ s/$Pattern/$Replace/eeg;
        }
    }

    $TarObject->replace_content( $HomeWithoutSlash . '/Kernel/Config.pm', $Config );

    my $Write = $TarObject->write( $CustomFilesArchive, 0 );
    if ( !$Write ) {

        # log info
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Can't write $CustomFilesArchive: $!",
        );
        return;
    }

    # add files to the tar archive
    my $TARFH;
    if ( !open( $TARFH, '<', $CustomFilesArchive ) ) {

        # log info
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Can't read $CustomFilesArchive: $!",
        );
        return;
    }

    binmode $TARFH;
    my $TmpTar = do {
        local $/ = undef;
        <$TARFH>
    };
    close $TARFH;

    if ( $Kernel::OM->Get('Kernel::System::Main')->Require('Compress::Zlib') ) {
        my $GzTar = Compress::Zlib::memGzip($TmpTar);

        # log info
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "Compression of $CustomFilesArchive end",
        );

        return ( \$GzTar, 'application.tar.gz' );
    }

    # log info
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "$CustomFilesArchive was not compressed",
    );

    return ( \$TmpTar, 'application.tar' );
}

=item GeneratePackageList()

Generates a .csv file with all installed packages

    my ( $Content, $Filename ) = $SupportBundleGeneratorObject->GeneratePackageList();

Returns:
    $Content  = $FileContentsRef;
    $Filename = 'InstalledPackages.csv';

=cut

sub GeneratePackageList {
    my ( $Self, %Param ) = @_;

    my @PackageList = $Kernel::OM->Get('Kernel::System::Package')->RepositoryList( Result => 'Short' );

    # get csv object
    my $CSVObject = $Kernel::OM->Get('Kernel::System::CSV');

    my $CSVContent = '';
    for my $Package (@PackageList) {

        my @PackageData = (
            [
                $Package->{Name},
                $Package->{Version},
                $Package->{MD5sum},
                $Package->{Vendor},
            ],
        );

        # convert data into CSV string
        $CSVContent .= $CSVObject->Array2CSV(
            Data => \@PackageData,
        );
    }

    return ( \$CSVContent, 'InstalledPackages.csv' );
}

=item GenerateSupportData()

Generates a .json file with the support data

    my ( $Content, $Filename ) = $SupportBundleGeneratorObject->GenerateSupportData();

Returns:
    $Content  = $FileContentsRef;
    $Filename = 'GenerateSupportData.json';

=cut

sub GenerateSupportData {
    my ( $Self, %Param ) = @_;

    my %SupportData = $Kernel::OM->Get('Kernel::System::SupportDataCollector')->Collect();

    my $JSONContent = $Kernel::OM->Get('Kernel::System::JSON')->Encode(
        Data => \%SupportData,
    );

    return ( \$JSONContent, 'SupportData.json' );
}

sub _GetMD5SumLookup {
    my ( $Self, %Param ) = @_;

    # generate a MD5 Sum lookup table from framework ARCHIVE
    my $FileList = $Kernel::OM->Get('Kernel::System::Main')->FileRead(
        Location        => $Self->{Home} . '/ARCHIVE',
        Mode            => 'utf8',
        Type            => 'Local',
        Result          => 'ARRAY',
        DisableWarnings => 1,
    );
    my %MD5SumLookup;
    for my $Line ( @{$FileList} ) {
        my ( $MD5Sum, $File ) = split /::/, $Line;
        chomp $File;
        $MD5SumLookup{ $Self->{Home} . '/' . $File } = $MD5Sum;
    }

    # get package object
    my $PackageObject = $Kernel::OM->Get('Kernel::System::Package');

    # get a list of packages installed
    my @PackagesList = $PackageObject->RepositoryList(
        Result => 'short',
    );

    # get from each installed package  a MD5 Sum Lookup table and store it on a global Lookup table
    my %PackageMD5SumLookup;
    for my $Package (@PackagesList) {
        my $PartialMD5Sum = $PackageObject->PackageFileGetMD5Sum( %{$Package} );
        %PackageMD5SumLookup = ( %PackageMD5SumLookup, %{$PartialMD5Sum} );
    }

    # add MD5Sums from all packages to the list from framwork ARCHIVE
    # overwritten files by packages will also overwrite the MD5 Sum
    %MD5SumLookup = ( %MD5SumLookup, %PackageMD5SumLookup );

    return \%MD5SumLookup;
}

sub _GetCustomFileList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(Directory)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # article directory
    my $ArticleDir = $ConfigObject->Get('ArticleDir');

    # cleanup file name
    $ArticleDir =~ s/\/\//\//g;

    # temp directory
    my $TempDir = $ConfigObject->Get('TempDir');

    # cleanup file name
    $TempDir =~ s/\/\//\//g;

    # check all $Param{Directory}/* in home directory
    my @Files;
    my @List = glob("$Param{Directory}/*");
    FILE:
    for my $File (@List) {

        # cleanup file name
        $File =~ s/\/\//\//g;

        # check if directory
        if ( -d $File ) {

            # do not include article in file system
            next FILE if $File =~ /\Q$ArticleDir\E/i;

            # do not include tmp in file system
            next FILE if $File =~ /\Q$TempDir\E/i;

            # do not include js-cache
            next FILE if $File =~ /js-cache/;

            # do not include css-cache
            next FILE if $File =~ /css-cache/;

            # do not include documentation
            next FILE if $File =~ /doc/;

            # add directory to list
            push @Files, $Self->_GetCustomFileList( Directory => $File );
        }
        else {

            # do not include hidden files
            next FILE if $File =~ /^\./;

            # do not include files with # in file name
            next FILE if $File =~ /#/;

            # do not include previous system dumps
            next FILE if $File =~ /.tar/;

            # do not include ARCHIVE
            next FILE if $File =~ /ARCHIVE/;

            # do not include if file is not readable
            next FILE if !-r $File;

            my $MD5Sum = $Kernel::OM->Get('Kernel::System::Main')->MD5sum(
                Filename => $File,
            );

            # check if is a known file, in such case, check if MD5 is the same as the expected
            #   skip file if MD5 matches
            if ( $Self->{MD5SumLookup}->{$File} && $Self->{MD5SumLookup}->{$File} eq $MD5Sum ) {
                next FILE;
            }

            # add file to list
            push @Files, $File;
        }
    }

    return @Files;
}


1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut
