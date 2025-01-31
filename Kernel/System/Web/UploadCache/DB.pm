# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Web::UploadCache::DB;

use strict;
use warnings;

use MIME::Base64;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::Encode',
    'Kernel::System::Log',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

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

    for (qw(FormID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'DELETE FROM web_upload_cache WHERE form_id = ?',
        Bind => [ \$Param{FormID} ],
    );

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

    # get file size
    $Param{Filesize} = bytes::length( $Param{Content} );

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # encode attachment if it's a postgresql backend!!!
    if ( !$DBObject->GetDatabaseFunction('DirectBlob') ) {

        $Kernel::OM->Get('Kernel::System::Encode')->EncodeOutput( \$Param{Content} );

        $Param{Content} = encode_base64( $Param{Content} );
    }

    # create content id
    my $ContentID = $Param{ContentID};
    my $Disposition = $Param{Disposition} || '';
    if ( !$ContentID && lc $Disposition eq 'inline' ) {

        my $Random = rand 999999;
        my $FQDN   = $Kernel::OM->Get('Kernel::Config')->Get('FQDN');

        $ContentID = "$Disposition$Random.$Param{FormID}\@$FQDN";
    }

    # write attachment to db
    my $Time = time();

    return if !$DBObject->Do(
        SQL => 'INSERT INTO web_upload_cache (form_id, filename, content_type, content_size, content, create_time_unix, content_id, disposition)'
             . ' VALUES  (?, ?, ?, ?, ?, ?, ?, ?)',
        Bind => [
            \$Param{FormID}, \$Param{Filename}, \$Param{ContentType}, \$Param{Filesize},
            \$Param{Content}, \$Time, \$ContentID, \$Param{Disposition}
        ],
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

    my @Index = @{ $Self->FormIDGetAllFilesMeta(%Param) };

    # finish if files have been already removed by other process
    return if !@Index;

    my $ID = $Param{FileID} - 1;
    $Param{Filename} = $Index[$ID]->{Filename};

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'DELETE FROM web_upload_cache WHERE form_id = ? AND filename = ?',
        Bind => [ \$Param{FormID}, \$Param{Filename} ],
    );

    return 1;
}

sub FormIDGetAllFilesData {
    my ( $Self, %Param ) = @_;

    my $Counter = 0;
    my @Data;
    for (qw(FormID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    $DBObject->Prepare(
        SQL    => 'SELECT filename, content_type, content_size, content, content_id, disposition'
                . ' FROM web_upload_cache'
                . ' WHERE form_id = ?'
                . ' ORDER BY create_time_unix',
        Bind   => [ \$Param{FormID} ],
        Encode => [ 1, 1, 1, 0, 1, 1 ],
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Counter++;

        # human readable file size
        my $Filesize = '';
        if ( $Row[2] ) {
            if ( $Row[2] > ( 1024 * 1024 ) ) {
                $Filesize = sprintf "%.1f MBytes", ( $Row[2] / ( 1024 * 1024 ) );
            }
            elsif ( $Row[2] > 1024 ) {
                $Filesize = sprintf "%.1f KBytes", ( ( $Row[2] / 1024 ) );
            }
            else {
                $Filesize = $Row[2] . ' Bytes';
            }
        }

        # encode attachment if it's a postgresql backend!!!
        if ( !$DBObject->GetDatabaseFunction('DirectBlob') ) {
            $Row[3] = decode_base64( $Row[3] );
        }

        # add the info
        push(
            @Data,
            {
                Content     => $Row[3],
                ContentID   => $Row[4],
                ContentType => $Row[1],
                Filename    => $Row[0],
                FilesizeRaw => $Row[2],
                Filesize    => $Filesize,
                Disposition => $Row[5],
                FileID      => $Counter,
            }
        );
    }

    return \@Data;
}

sub FormIDGetAllFilesMeta {
    my ( $Self, %Param ) = @_;

    my $Counter = 0;
    my @Data;
    for (qw(FormID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    $DBObject->Prepare(
        SQL  => 'SELECT filename, content_type, content_size, content_id, disposition'
              . ' FROM web_upload_cache'
              . ' WHERE form_id = ?'
              . ' ORDER BY create_time_unix',
        Bind => [ \$Param{FormID} ],
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Counter++;

        # human readable file size
        my $Filesize = '';
        if ( $Row[2] ) {
            if ( $Row[2] > ( 1024 * 1024 ) ) {
                $Filesize = sprintf "%.1f MBytes", ( $Row[2] / ( 1024 * 1024 ) );
            }
            elsif ( $Row[2] > 1024 ) {
                $Filesize = sprintf "%.1f KBytes", ( ( $Row[2] / 1024 ) );
            }
            else {
                $Filesize = $Row[2] . ' Bytes';
            }
        }

        # add the info
        push(
            @Data,
            {
                ContentID   => $Row[3],
                ContentType => $Row[1],
                Filename    => $Row[0],
                FilesizeRaw => $Row[2],
                Filesize    => $Filesize,
                Disposition => $Row[4],
                FileID      => $Counter,
            }
        );
    }
    return \@Data;
}

sub FormIDCleanUp {
    my ( $Self, %Param ) = @_;

    my $CurrentTile = time() - ( 60 * 60 * 24 * 1 );

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'DELETE FROM web_upload_cache WHERE create_time_unix < ?',
        Bind => [ \$CurrentTile ],
    );

    return 1;
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
