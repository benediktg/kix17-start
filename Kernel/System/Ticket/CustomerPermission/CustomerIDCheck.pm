# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::CustomerPermission::CustomerIDCheck;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::CustomerUser',
    'Kernel::System::Log',
    'Kernel::System::Ticket',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(TicketID UserID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!",
            );
            return;
        }
    }

    # disable output of customer company tickets if configured
    return
        if $Kernel::OM->Get('Kernel::Config')->Get('Ticket::Frontend::CustomerDisableCompanyTicketAccess');

    # get ticket data
    my %Ticket = $Kernel::OM->Get('Kernel::System::Ticket')->TicketGet(
        TicketID      => $Param{TicketID},
        DynamicFields => 0,
    );

    return if !%Ticket;
    return if !$Ticket{CustomerID};

    # get customer user object
    my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');

    # check customer id
    my %CustomerData = $CustomerUserObject->CustomerUserDataGet(
        User => $Param{UserID},
    );

    # get customer ids
    my @CustomerIDs = $CustomerUserObject->CustomerIDs(
        User => $Param{UserID},
    );

    # add own customer id
    if ( $CustomerData{UserCustomerID} ) {
        push @CustomerIDs, $CustomerData{UserCustomerID};
    }

    # check customer ids, return access if customer id is the same
    CUSTOMERID:
    for my $CustomerID (@CustomerIDs) {

        next CUSTOMERID if !$CustomerID;

        return 1 if lc $Ticket{CustomerID} eq lc $CustomerID;
    }

    # return no access
    return;
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
