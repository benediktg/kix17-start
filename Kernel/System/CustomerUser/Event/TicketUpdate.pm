# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::CustomerUser::Event::TicketUpdate;

use strict;
use warnings;

our @ObjectDependencies = (
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
    for (qw( Data Event Config UserID )) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }
    for (qw( UserLogin NewData OldData )) {
        if ( !$Param{Data}->{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_ in Data!"
            );
            return;
        }
    }

    # only update if fields have really changed
    if (
        $Param{Data}->{OldData}->{UserCustomerID} ne $Param{Data}->{NewData}->{UserCustomerID}
        || $Param{Data}->{OldData}->{UserLogin} ne $Param{Data}->{NewData}->{UserLogin}
    ) {

        # get ticket object
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

        # perform search
        my @Tickets = $TicketObject->TicketSearch(
            Result               => 'ARRAY',
            Limit                => 100_000,
            CustomerUserLoginRaw => $Param{Data}->{OldData}->{UserLogin},
            CustomerIDRaw        => $Param{Data}->{OldData}->{UserCustomerID},
            ArchiveFlags         => [ 'y', 'n' ],
            UserID               => 1,
        );

        # update the customer ID and login of tickets
        for my $TicketID (@Tickets) {
            $TicketObject->TicketCustomerSet(
                No       => $Param{Data}->{NewData}->{UserCustomerID},
                User     => $Param{Data}->{NewData}->{UserLogin},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
    }

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
