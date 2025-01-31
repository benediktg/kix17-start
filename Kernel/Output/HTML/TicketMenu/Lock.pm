# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::TicketMenu::Lock;

use strict;
use warnings;

use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
    'Kernel::System::Log',
    'Kernel::Config',
    'Kernel::System::Ticket',
    'Kernel::System::Group',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get UserID param
    $Self->{UserID} = $Param{UserID} || die "Got no UserID!";

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get log object
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # check needed stuff
    if ( !$Param{Ticket} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'Need Ticket!'
        );
        return;
    }

    # check if frontend module registered, if not, do not show action
    if ( $Param{Config}->{Action} ) {
        my $Module = $Kernel::OM->Get('Kernel::Config')->Get('Frontend::Module')->{ $Param{Config}->{Action} };
        return if !$Module;
    }

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # check lock permission
    my $AccessOk = $TicketObject->TicketPermission(
        Type     => 'lock',
        TicketID => $Param{Ticket}->{TicketID},
        UserID   => $Self->{UserID},
        LogNo    => 1,
    );
    return if !$AccessOk;

    # check permission
    if ( $TicketObject->TicketLockGet( TicketID => $Param{Ticket}->{TicketID} ) ) {
        my $HasAccess = $TicketObject->OwnerCheck(
            TicketID => $Param{Ticket}->{TicketID},
            OwnerID  => $Self->{UserID},
        );
        return if !$HasAccess;
    }

    # group check
    if ( $Param{Config}->{Group} ) {

        my @Items = split /;/, $Param{Config}->{Group};

        my $HasAccess;
        ITEM:
        for my $Item (@Items) {

            my ( $Permission, $Name ) = split /:/, $Item;

            if ( !$Permission || !$Name ) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Invalid config for Key Group: '$Item'! "
                        . "Need something like '\$Permission:\$Group;'",
                );
            }

            my %Groups = $Kernel::OM->Get('Kernel::System::Group')->PermissionUserGet(
                UserID => $Self->{UserID},
                Type   => $Permission,
            );

            next ITEM if !%Groups;

            my %GroupsReverse = reverse %Groups;

            next ITEM if !$GroupsReverse{$Name};

            $HasAccess = 1;

            last ITEM;
        }

        return if !$HasAccess;
    }

    # check acl
    my %ACLLookup = reverse( %{ $Param{ACL} || {} } );
    return if ( !$ACLLookup{ $Param{Config}->{Action} } );

    # if ticket is locked
    if ( $Param{Ticket}->{Lock} eq 'lock' ) {

        # if it is locked for somebody else
        return if $Param{Ticket}->{OwnerID} ne $Self->{UserID};

        # show unlock action
        return {
            %{ $Param{Config} },
            %{ $Param{Ticket} },
            %Param,
            Name        => Translatable('Unlock'),
            Description => Translatable('Unlock to give it back to the queue'),
            Link =>
                'Action=AgentTicketLock;Subaction=Unlock;TicketID=[% Data.TicketID | uri %];[% Env("ChallengeTokenParam") | html %]',
        };
    }

    # if ticket is unlocked
    return {
        %{ $Param{Config} },
        %{ $Param{Ticket} },
        %Param,
        Name        => Translatable('Lock'),
        Description => Translatable('Lock it to work on it'),
        Link =>
            'Action=AgentTicketLock;Subaction=Lock;TicketID=[% Data.TicketID | uri %];[% Env("ChallengeTokenParam") | html %]',
    };
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
