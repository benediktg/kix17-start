# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::PublicSupportDataCollector;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

use HTTP::Response;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # The request must be authenticated with the correct ChallengeToken
    my $SystemDataObject     = $Kernel::OM->Get('Kernel::System::SystemData');
    my $ChallengeToken       = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'ChallengeToken' );
    my $StoredChallengeToken = $SystemDataObject->SystemDataGet( Key => 'SupportDataCollector::ChallengeToken' );

    # Immediately discard the token (only useable once).
    $SystemDataObject->SystemDataDelete(
        Key    => 'SupportDataCollector::ChallengeToken',
        UserID => 1,
    );

    my %Result;

    if ( !$ChallengeToken || $ChallengeToken ne $StoredChallengeToken ) {
        %Result = (
            Success      => 0,
            ErrorMessage => 'Forbidden',
        );
    }
    else {
        %Result = $Kernel::OM->Get('Kernel::System::SupportDataCollector')->Collect();
    }

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $JSON         = $LayoutObject->JSONEncode(
        Data => \%Result,
    );

    # send JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
        Content     => $JSON || '',
        Type        => 'inline',
        NoCache     => 1,
    );
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
