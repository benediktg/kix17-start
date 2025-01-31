# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::CustomerAuth::TwoFactor::GoogleAuthenticator;

use strict;
use warnings;

use Digest::SHA qw(sha1);
use Digest::HMAC qw(hmac_hex);

use base qw(Kernel::System::Auth::TwoFactor::GoogleAuthenticator);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::CustomerUser',
    'Kernel::System::Log',
    'Kernel::System::Time',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{Count} = $Param{Count} || '';

    return $Self;
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

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $SecretPreferencesKey
        = $ConfigObject->Get("Customer::AuthTwoFactorModule$Self->{Count}::SecretPreferencesKey") || '';
    if ( !$SecretPreferencesKey ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Found no configuration for SecretPreferencesKey in Customer::AuthTwoFactorModule.",
        );
        return;
    }

    # check if customer has secret stored in preferences
    my %UserPreferences = $Kernel::OM->Get('Kernel::System::CustomerUser')->GetPreferences(
        UserID => $Param{User},
    );
    if ( !$UserPreferences{$SecretPreferencesKey} ) {

        # if login without a stored secret key is permitted, this counts as passed
        if ( $ConfigObject->Get("Customer::AuthTwoFactorModule$Self->{Count}::AllowEmptySecret") ) {
            return 1;
        }

        # otherwise login counts as failed
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Found no SecretPreferencesKey for customer $Param{User}.",
        );
        return;
    }

    # if we get to here (user has preference), we need a passed token
    if ( !$Param{TwoFactorToken} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need TwoFactorToken!"
        );
        return;
    }

    # generate otp based on secret from preferences
    my $OTP = $Self->_GenerateOTP(
        Secret => $UserPreferences{$SecretPreferencesKey},
    );

    # compare against user provided otp
    if ( $Param{TwoFactorToken} ne $OTP ) {

        # check if previous token is also to be accepted
        if ( $ConfigObject->Get("Customer::AuthTwoFactorModule$Self->{Count}::AllowPreviousToken") ) {

            # try again with previous otp (from 30 seconds ago)
            $OTP = $Self->_GenerateOTP(
                Secret   => $UserPreferences{$SecretPreferencesKey},
                Previous => 1,
            );
        }

        if ( $Param{TwoFactorToken} ne $OTP ) {

            # log failure
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "CustomerUser: $Param{User} two factor customer authentication failed (non-matching otp).",
            );
            return;
        }
    }

    # log success
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "CustomerUser: $Param{User} two factor customer authentication ok.",
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
