# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. This program is
# licensed under the AGPL-3.0 with patches licensed under the GPL-3.0.
# For details, see the enclosed files LICENSE (AGPL) and
# LICENSE-GPL3 (GPL3) for license information. If you did not receive
# this files, see https://www.gnu.org/licenses/agpl.txt (APGL) and
# https://www.gnu.org/licenses/gpl-3.0.txt (GPL3).
# --

package Kernel::System::Web::UploadCache::FS;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Main',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{TempDir} = $Kernel::OM->Get('Kernel::Config')->Get('TempDir') . '/upload_cache/';

    if ( !-d $Self->{TempDir} ) {
        mkdir $Self->{TempDir};
    }

    return $Self;
}

sub FormIDCreate {
    my ( $Self, %Param ) = @_;

    # cleanup temp form ids
    $Self->FormIDCleanUp();

    # return requested form id
    return time() . '.' . rand(12341241);
}

sub FormIDRemove {
    my ( $Self, %Param ) = @_;

    if ( !$Param{FormID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need FormID!'
        );
        return;
    }

### Patch licensed under the GPL-3.0, Copyright (C) 2001-2022 OTRS AG, https://otrs.com/ ###
    return if !$Self->_FormIDValidate( $Param{FormID} );
### EO Patch licensed under the GPL-3.0, Copyright (C) 2001-2022 OTRS AG, https://otrs.com/ ###

    # get main object
    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

    my @List = $MainObject->DirectoryRead(
        Directory => $Self->{TempDir},
        Filter    => "$Param{FormID}.*",
    );

    my @Data;
    for my $File (@List) {
        $MainObject->FileDelete(
            Location => $File,
        );
    }

    return 1;
}

sub FormIDAddFile {
    my ( $Self, %Param ) = @_;

    for (qw(FormID Filename Content ContentType)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

### Patch licensed under the GPL-3.0, Copyright (C) 2001-2022 OTRS AG, https://otrs.com/ ###
    return if !$Self->_FormIDValidate( $Param{FormID} );
### EO Patch licensed under the GPL-3.0, Copyright (C) 2001-2022 OTRS AG, https://otrs.com/ ###

    # create content id
    my $ContentID = $Param{ContentID};
    my $Disposition = $Param{Disposition} || '';
    if ( !$ContentID && lc $Disposition eq 'inline' ) {

        my $Random = rand 999999;
        my $FQDN   = $Kernel::OM->Get('Kernel::Config')->Get('FQDN');

        $ContentID = "$Disposition$Random.$Param{FormID}\@$FQDN";
    }

    # get main object
    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

    # files must readable for creator
    return if !$MainObject->FileWrite(
        Directory  => $Self->{TempDir},
        Filename   => "$Param{FormID}.$Param{Filename}",
        Content    => \$Param{Content},
        Mode       => 'binmode',
        Permission => '640',
    );
    return if !$MainObject->FileWrite(
        Directory  => $Self->{TempDir},
        Filename   => "$Param{FormID}.$Param{Filename}.ContentType",
        Content    => \$Param{ContentType},
        Mode       => 'binmode',
        Permission => '640',
    );
    return if !$MainObject->FileWrite(
        Directory  => $Self->{TempDir},
        Filename   => "$Param{FormID}.$Param{Filename}.ContentID",
        Content    => \$ContentID,
        Mode       => 'binmode',
        Permission => '640',
    );
    return if !$MainObject->FileWrite(
        Directory  => $Self->{TempDir},
        Filename   => "$Param{FormID}.$Param{Filename}.Disposition",
        Content    => \$Disposition,
        Mode       => 'binmode',
        Permission => '644',
    );
    return 1;
}

sub FormIDRemoveFile {
    my ( $Self, %Param ) = @_;

    for (qw(FormID FileID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

### Patch licensed under the GPL-3.0, Copyright (C) 2001-2022 OTRS AG, https://otrs.com/ ###
    return if !$Self->_FormIDValidate( $Param{FormID} );
### EO Patch licensed under the GPL-3.0, Copyright (C) 2001-2022 OTRS AG, https://otrs.com/ ###

    my @Index = @{ $Self->FormIDGetAllFilesMeta(%Param) };

    # finish if files have been already removed by other process
    return if !@Index;

    my $ID   = $Param{FileID} - 1;
    my %File = %{ $Index[$ID] };

    # get main object
    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

    $MainObject->FileDelete(
        Directory => $Self->{TempDir},
        Filename  => "$Param{FormID}.$File{Filename}",
    );
    $MainObject->FileDelete(
        Directory => $Self->{TempDir},
        Filename  => "$Param{FormID}.$File{Filename}.ContentType",
    );
    $MainObject->FileDelete(
        Directory => $Self->{TempDir},
        Filename  => "$Param{FormID}.$File{Filename}.ContentID",
    );
    $MainObject->FileDelete(
        Directory => $Self->{TempDir},
        Filename  => "$Param{FormID}.$File{Filename}.Disposition",
    );

    return 1;
}

sub FormIDGetAllFilesData {
    my ( $Self, %Param ) = @_;

    if ( !$Param{FormID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need FormID!'
        );
        return;
    }

### Patch licensed under the GPL-3.0, Copyright (C) 2001-2022 OTRS AG, https://otrs.com/ ###
    my @Data;

    return \@Data if !$Self->_FormIDValidate( $Param{FormID} );
### EO Patch licensed under the GPL-3.0, Copyright (C) 2001-2022 OTRS AG, https://otrs.com/ ###

    # get main object
    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

    my @List = $MainObject->DirectoryRead(
        Directory => $Self->{TempDir},
        Filter    => "$Param{FormID}.*",
    );

    my $Counter = 0;

    FILE:
    for my $File (@List) {

        # ignore meta files
        next FILE if $File =~ /\.ContentType$/;
        next FILE if $File =~ /\.ContentID$/;
        next FILE if $File =~ /\.Disposition$/;

        $Counter++;
        my $FilesizeRaw = -s $File;

        # human readable file size
        my $Filesize = '';
        if ($FilesizeRaw) {

            # remove meta data in files
            if ( $FilesizeRaw > 30 ) {
                $FilesizeRaw -= 30;
            }
            if ( $FilesizeRaw > ( 1024 * 1024 ) ) {
                $Filesize = sprintf "%.1f MBytes", ( $FilesizeRaw / ( 1024 * 1024 ) );
            }
            elsif ( $FilesizeRaw > 1024 ) {
                $Filesize = sprintf "%.1f KBytes", ( ( $FilesizeRaw / 1024 ) );
            }
            else {
                $Filesize = $FilesizeRaw . ' Bytes';
            }
        }
        my $Content = $MainObject->FileRead(
            Location => $File,
            Mode     => 'binmode',                                             # optional - binmode|utf8
        );
        next FILE if !$Content;

        my $ContentType = $MainObject->FileRead(
            Location => "$File.ContentType",
            Mode     => 'binmode',                                             # optional - binmode|utf8
        );
        next FILE if !$ContentType;

        my $ContentID = $MainObject->FileRead(
            Location => "$File.ContentID",
            Mode     => 'binmode',                                             # optional - binmode|utf8
        );
        next FILE if !$ContentID;

        # verify if content id is empty, set to undef
        if ( !${$ContentID} ) {
            ${$ContentID} = undef;
        }

        my $Disposition = $MainObject->FileRead(
            Location => "$File.Disposition",
            Mode     => 'binmode',                                             # optional - binmode|utf8
        );

        # strip filename
        $File =~ s/^.*\/$Param{FormID}\.(.+?)$/$1/;
        push(
            @Data,
            {
                Content     => ${$Content},
                ContentID   => ${$ContentID},
                ContentType => ${$ContentType},
                Filename    => $File,
                FilesizeRaw => $FilesizeRaw,
                Filesize    => $Filesize,
                FileID      => $Counter,
                Disposition => ${$Disposition},
            },
        );
    }
    return \@Data;

}

sub FormIDGetAllFilesMeta {
    my ( $Self, %Param ) = @_;

    if ( !$Param{FormID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need FormID!'
        );
        return;
    }

### Patch licensed under the GPL-3.0, Copyright (C) 2001-2022 OTRS AG, https://otrs.com/ ###
    my @Data;

    return \@Data if !$Self->_FormIDValidate( $Param{FormID} );
### EO Patch licensed under the GPL-3.0, Copyright (C) 2001-2022 OTRS AG, https://otrs.com/ ###

    # get main object
    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

    my @List = $MainObject->DirectoryRead(
        Directory => $Self->{TempDir},
        Filter    => "$Param{FormID}.*",
    );

    my $Counter = 0;

    FILE:
    for my $File (@List) {

        # ignore meta files
        next FILE if $File =~ /\.ContentType$/;
        next FILE if $File =~ /\.ContentID$/;
        next FILE if $File =~ /\.Disposition$/;

        $Counter++;
        my $FilesizeRaw = -s $File;

        # human readable file size
        my $Filesize = '';
        if ($FilesizeRaw) {

            # remove meta data in files
            if ( $FilesizeRaw > 30 ) {
                $FilesizeRaw -= 30;
            }
            if ( $FilesizeRaw > ( 1024 * 1024 ) ) {
                $Filesize = sprintf "%.1f MBytes", ( $FilesizeRaw / ( 1024 * 1024 ) );
            }
            elsif ( $FilesizeRaw > 1024 ) {
                $Filesize = sprintf "%.1f KBytes", ( ( $FilesizeRaw / 1024 ) );
            }
            else {
                $Filesize = $FilesizeRaw . ' Bytes';
            }
        }

        my $ContentType = $MainObject->FileRead(
            Location => "$File.ContentType",
            Mode     => 'binmode',                                             # optional - binmode|utf8
        );
        next FILE if !$ContentType;

        my $ContentID = $MainObject->FileRead(
            Location => "$File.ContentID",
            Mode     => 'binmode',                                             # optional - binmode|utf8
        );
        next FILE if !$ContentID;

        # verify if content id is empty, set to undef
        if ( !${$ContentID} ) {
            ${$ContentID} = undef;
        }

        my $Disposition = $MainObject->FileRead(
            Location => "$File.Disposition",
            Mode     => 'binmode',                                             # optional - binmode|utf8
        );

        # strip filename
        $File =~ s/^.*\/$Param{FormID}\.(.+?)$/$1/;
        push(
            @Data,
            {
                ContentID   => ${$ContentID},
                ContentType => ${$ContentType},
                Filename    => $File,
                FilesizeRaw => $FilesizeRaw,
                Filesize    => $Filesize,
                FileID      => $Counter,
                Disposition => ${$Disposition},
            },
        );
    }
    return \@Data;
}

sub FormIDCleanUp {
    my ( $Self, %Param ) = @_;

    my $CurrentTile = time() - 86400;                                            # 60 * 60 * 24 * 1
    my @List        = $Kernel::OM->Get('Kernel::System::Main')->DirectoryRead(
        Directory => $Self->{TempDir},
        Filter    => '*'
    );

    my %RemoveFormIDs;
    for my $File (@List) {

        # get FormID
        if ($File =~ m/^.*\/((\d+) \. (?: \d+ | \w+ \. \w+ \. \d+ | \w+ (?:\. \d+)+ \. \w+ ) \. \d+)\..+?$/xms) {
            my $FormID = $1;
            my $Time   = $2;
            if ( $CurrentTile > $Time ) {
                if ( !$RemoveFormIDs{$FormID} ) {
                    $RemoveFormIDs{$FormID} = 1;
                }
            }
        }
    }

    for ( sort keys %RemoveFormIDs ) {
        $Self->FormIDRemove( FormID => $_ );
    }

    return 1;
}

### Patch licensed under the GPL-3.0, Copyright (C) 2001-2022 OTRS AG, https://otrs.com/ ###
sub _FormIDValidate {
    my ( $Self, $FormID ) = @_;

    return if !$FormID;

# KIX-capeIT
#    if ( $FormID !~ m{^ \d+ \. \d+ \. \d+ $}xms ) {
    if ( $FormID !~ m{^ \d+ \. (?: \d+ | \w+ \. \w+ \. \d+ | \w+ (?:\. \d+)+ \. \w+ ) \. \d+ $}xms ) {
# EO KIX-capeIT
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Invalid FormID!',
        );
        return;
    }

    return 1;
}
### EO Patch licensed under the GPL-3.0, Copyright (C) 2001-2022 OTRS AG, https://otrs.com/ ###

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. This program is
licensed under the AGPL-3.0 with patches licensed under the GPL-3.0.
For details, see the enclosed files LICENSE (AGPL) and
LICENSE-GPL3 (GPL3) for license information. If you did not receive
this files, see <https://www.gnu.org/licenses/agpl.txt> (APGL) and
<https://www.gnu.org/licenses/gpl-3.0.txt> (GPL3).

=cut
