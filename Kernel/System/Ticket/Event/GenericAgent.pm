# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::Event::GenericAgent;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::System::GenericAgent',
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
    for my $Needed (qw(Data Event Config)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # check for TicketID
    if ( !$Param{Data}->{TicketID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need TicketID! in Data",
        );
        return;
    }

    # Loop protection: only execute this handler once for each ticket and event.
    return
        if $Kernel::OM->Get('Kernel::System::Ticket')->{'_GenericAgent::AlreadyProcessed'}
        ->{ $Param{Data}->{TicketID} }->{ $Param{Event} }++;

    # get generic agent object
    my $GenericAgentObject = $Kernel::OM->Get('Kernel::System::GenericAgent');

    my %JobEventList = $GenericAgentObject->JobEventList();

    # no configured jobs is OK
    return 1 if !IsHashRefWithData( \%JobEventList );

    # loop over jobs
    JOB:
    for my $JobName ( sort keys %JobEventList ) {

        next JOB if !IsArrayRefWithData( $JobEventList{$JobName} );

        # check if the job is connected to this event
        my @Events = @{ $JobEventList{$JobName} };
        next JOB if !grep { $_ eq $Param{Event} } @Events;

        # execute the job
        my $Result = $GenericAgentObject->JobRun(
            Job          => $JobName,
            OnlyTicketID => $Param{Data}->{TicketID},
            UserID       => 1,                          # run the job as system user
        );
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
