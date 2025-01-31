# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Auth::DB;

use strict;
use warnings;

use Crypt::PasswdMD5 qw(unix_md5_crypt apache_md5_crypt);
use Digest::SHA;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::Encode',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::Valid',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # Debug 0=off 1=on
    $Self->{Debug} = 0;

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get user table
    $Self->{UserTable} = $ConfigObject->Get( 'DatabaseUserTable' . $Param{Count} )
        || 'users';
    $Self->{UserTableUserID} = $ConfigObject->Get( 'DatabaseUserTableUserID' . $Param{Count} )
        || 'id';
    $Self->{UserTableUserPW} = $ConfigObject->Get( 'DatabaseUserTableUserPW' . $Param{Count} )
        || 'pw';
    $Self->{UserTableUser} = $ConfigObject->Get( 'DatabaseUserTableUser' . $Param{Count} )
        || 'login';

    return $Self;
}

sub GetOption {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{What} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need What!"
        );
        return;
    }

    # module options
    my %Option = (
        PreAuth => 0,
    );

    # return option
    return $Option{ $Param{What} };
}

sub Auth {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{User} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need User!"
        );
        return;
    }

    # get params
    my $User       = $Param{User}      || '';
    my $Pw         = $Param{Pw}        || '';
    my $RemoteAddr = $ENV{REMOTE_ADDR} || 'Got no REMOTE_ADDR env!';
    my $UserID     = '';
    my $GetPw      = '';
    my $Method;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # sql query
    my $SQL = "SELECT $Self->{UserTableUserPW}, $Self->{UserTableUserID}, $Self->{UserTableUser} "
        . " FROM "
        . " $Self->{UserTable} "
        . " WHERE "
        . " valid_id IN ( ${\(join ', ', $Kernel::OM->Get('Kernel::System::Valid')->ValidIDsGet())} ) AND "
        . " $Self->{UserTableUser} = '" . $DBObject->Quote($User) . "'";
    $DBObject->Prepare( SQL => $SQL );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        $GetPw  = $Row[0];
        $UserID = $Row[1];
        $User   = $Row[2];
    }

    # get needed objects
    my $EncodeObject = $Kernel::OM->Get('Kernel::System::Encode');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # crypt given pw
    my $CryptedPw = '';
    my $Salt      = $GetPw;
    if (
        $ConfigObject->Get('AuthModule::DB::CryptType')
        && $ConfigObject->Get('AuthModule::DB::CryptType') eq 'plain'
    ) {
        $CryptedPw = $Pw;
        $Method    = 'plain';
    }

    # md5, bcrypt or sha pw
    elsif ( $GetPw !~ /^.{13}$/ ) {

        # md5 pw
        if ( $GetPw =~ m{\A \$.+? \$.+? \$.* \z}xms ) {

            # strip Salt
            my $Magic = '';
            if ( $Salt =~ s/^(\$.+?\$)(.+?)\$.*$/$2/ ) {
                $Magic = $1;
            }

            # encode output, needed by unix_md5_crypt() only non utf8 signs
            $EncodeObject->EncodeOutput( \$Pw );
            $EncodeObject->EncodeOutput( \$Salt );

            if ( $Magic eq '$apr1$' ) {
                $CryptedPw = apache_md5_crypt( $Pw, $Salt );
                $Method = 'apache_md5_crypt';
            }
            else {
                $CryptedPw = unix_md5_crypt( $Pw, $Salt );
                $Method = 'unix_md5_crypt';
            }

        }

        # sha256 pw
        elsif ( $GetPw =~ m{\A .{64} \z}xms ) {

            my $SHAObject = Digest::SHA->new('sha256');

            # encode output, needed by sha256_hex() only non utf8 signs
            $EncodeObject->EncodeOutput( \$Pw );

            $SHAObject->add($Pw);
            $CryptedPw = $SHAObject->hexdigest();
            $Method    = 'sha256';
        }

        elsif ( $GetPw =~ m{^BCRYPT:} ) {

            # require module, log errors if module was not found
            if ( !$Kernel::OM->Get('Kernel::System::Main')->Require('Crypt::Eksblowfish::Bcrypt') ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message =>
                        "User: '$User' tried to authenticate with bcrypt but 'Crypt::Eksblowfish::Bcrypt' is not installed!",
                );
                return;
            }

            # get salt and cost from stored PW string
            my ( $Cost, $BCryptSalt, $Base64Hash ) = $GetPw =~ m{^BCRYPT:(\d+):(.{16}):(.*)$}xms;

            # remove UTF8 flag, required by Crypt::Eksblowfish::Bcrypt
            $EncodeObject->EncodeOutput( \$Pw );

            # calculate password hash with the same cost and hash settings
            my $Octets = Crypt::Eksblowfish::Bcrypt::bcrypt_hash(
                {
                    key_nul => 1,
                    cost    => $Cost,
                    salt    => $BCryptSalt,
                },
                $Pw
            );

            $CryptedPw = "BCRYPT:$Cost:$BCryptSalt:" . Crypt::Eksblowfish::Bcrypt::en_base64($Octets);
            $Method    = 'bcrypt';
        }

        # fallback: sha1 pw
        else {

            my $SHAObject = Digest::SHA->new('sha1');

            # encode output, needed by sha1_hex() only non utf8 signs
            $EncodeObject->EncodeOutput( \$Pw );

            $SHAObject->add($Pw);
            $CryptedPw = $SHAObject->hexdigest();
            $Method    = 'sha1';
        }
    }

    # crypt pw
    else {

        # strip Salt only for (Extended) DES, not for any of Modular crypt's
        if ( $Salt !~ /^\$\d\$/ ) {
            $Salt =~ s/^(..).*/$1/;
        }

        # encode output, needed by crypt() only non utf8 signs
        $EncodeObject->EncodeOutput( \$Pw );
        $EncodeObject->EncodeOutput( \$Salt );
        $CryptedPw = crypt( $Pw, $Salt );
        $Method = 'crypt';
    }

    # just in case for debug!
    if ( $Self->{Debug} > 0 ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message =>
                "User: '$User' tried to authenticate with Pw: '$Pw' ($UserID/$Method/$CryptedPw/$GetPw/$Salt/$RemoteAddr)",
        );
    }

    # just a note
    if ( !$Pw ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "User: $User without Pw!!! (REMOTE_ADDR: $RemoteAddr)",
        );
        return;
    }

    # login note
    elsif ( ( ($GetPw) && ($User) && ($UserID) ) && $CryptedPw eq $GetPw ) {

        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "User: $User authentication ok (Method: $Method, REMOTE_ADDR: $RemoteAddr).",
        );
        return $User;
    }

    # just a note
    elsif ( ($UserID) && ($GetPw) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message =>
                "User: $User authentication with wrong Pw!!! (Method: $Method, REMOTE_ADDR: $RemoteAddr)"
        );
        return;
    }

    # just a note
    else {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "User: $User doesn't exist or is invalid!!! (REMOTE_ADDR: $RemoteAddr)"
        );
        return;
    }
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
