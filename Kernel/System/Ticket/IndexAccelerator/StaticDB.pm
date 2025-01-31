# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::IndexAccelerator::StaticDB;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::Group',
    'Kernel::System::Lock',
    'Kernel::System::Log',
    'Kernel::System::State',
    'Kernel::System::Time',
);

sub TicketAcceleratorUpdate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(TicketID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    my $IsViewable = $Self->TicketSearch(
        TicketID => $Param{TicketID},
        Result     => 'COUNT',
        Permission => 'ro',
        UserID     => 1,
        Limit      => 1,
    );

    # delete index entry if ticket not viewable
    if ( !$IsViewable ) {
        $Self->TicketAcceleratorDelete(%Param);
        $Self->TicketLockAcceleratorDelete(%Param);
    }

    # check if ticket is shown or not
    my $IndexUpdateNeeded = 0;
    my $IndexSelected     = 0;
    my %TicketData        = $Self->TicketGet(
        %Param,
        DynamicFields => 0,
    );

    my %IndexTicketData = $Self->GetIndexTicket(%Param);

    if ( !%IndexTicketData ) {
        $IndexUpdateNeeded = 1;
    }
    else {

        # check if we need to update
        if ( $TicketData{Lock} ne $IndexTicketData{Lock} ) {
            $IndexUpdateNeeded = 1;
        }
        elsif ( $TicketData{State} ne $IndexTicketData{State} ) {
            $IndexUpdateNeeded = 1;
        }
        elsif ( $TicketData{QueueID} ne $IndexTicketData{QueueID} ) {
            $IndexUpdateNeeded = 1;
        }
    }

    # check if this ticket is still viewable
    my @ViewableStates = $Kernel::OM->Get('Kernel::System::State')->StateGetStatesByType(
        Type   => 'Viewable',
        Result => 'Name',
    );

    my $ViewableStatesHit = 0;

    for (@ViewableStates) {

        if ( $_ =~ /^$TicketData{State}$/i ) {
            $ViewableStatesHit = 1;
        }
    }

    my @ViewableLocks = $Kernel::OM->Get('Kernel::System::Lock')->LockViewableLock(
        Type => 'Name',
    );

    my $ViewableLocksHit = 0;

    for (@ViewableLocks) {

        if ( $_ =~ /^$TicketData{Lock}$/i ) {
            $ViewableLocksHit = 1;
        }
    }

    if ($ViewableStatesHit) {
        $IndexSelected = 1;
    }

    if ( $TicketData{ArchiveFlag} eq 'y' ) {
        $IndexSelected = 0;
    }

    # write index back
    if ($IndexUpdateNeeded) {

        if ($IndexSelected) {

            if ( $IndexTicketData{TicketID} ) {

                $Kernel::OM->Get('Kernel::System::DB')->Do(
                    SQL  => 'UPDATE ticket_index'
                          . ' SET queue_id = ?, queue = ?, group_id = ?, s_lock = ?, s_state = ?'
                          . ' WHERE ticket_id = ?',
                    Bind => [
                        \$TicketData{QueueID}, \$TicketData{Queue}, \$TicketData{GroupID},
                        \$TicketData{Lock},    \$TicketData{State}, \$Param{TicketID},
                    ],
                );
            }
            else {
                $Self->TicketAcceleratorAdd(%TicketData);
            }
        }
        else {
            $Self->TicketAcceleratorDelete(%Param);
        }
    }

    # write lock index
    if ( !$ViewableLocksHit ) {

        # check if there is already an lock index entry
        if ( !$Self->_GetIndexTicketLock(%Param) ) {

            # add lock index entry
            $Self->TicketLockAcceleratorAdd(%TicketData);
        }
    }
    else {

        # delete lock index entry if ticket is unlocked
        $Self->TicketLockAcceleratorDelete(%Param);
    }

    return 1;
}

sub TicketAcceleratorUpdateOnQueueUpdate {
    my ( $Self, %Param ) = @_;

    for my $Needed (qw(NewQueueName OldQueueName)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    #update ticket_index for changed queue name
    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'UPDATE ticket_index SET queue = ? WHERE queue = ?',
        Bind => [
            \$Param{NewQueueName},
            \$Param{OldQueueName},
        ],
    );

    return 1;
}

sub TicketAcceleratorDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(TicketID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    return if !$Self->TicketLockAcceleratorDelete(%Param);

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'DELETE FROM ticket_index WHERE ticket_id = ?',
        Bind => [ \$Param{TicketID} ],
    );

    return 1;
}

sub TicketAcceleratorAdd {
    my ( $Self, %Param ) = @_;

    # get database object
    my $DBObject    = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject   = $Kernel::OM->Get('Kernel::System::Log');
    my $StateObject = $Kernel::OM->Get('Kernel::System::State');

    # check needed stuff
    for (qw(TicketID)) {
        if ( !$Param{$_} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    my $IsRebuild = $Param{Rebuild} || 0;

    if ( !$IsRebuild ) {
        # return true, if ticket not viewable
        return 1 if !$Self->TicketSearch(
            TicketID   => $Param{TicketID},
            Result     => 'COUNT',
            UserID     => 1,
            Permission => 'ro',
            Limit      => 1,
        );
    }

    # get all viewable tickets
    return if !$DBObject->Prepare(
        SQL => <<'END',
SELECT st.queue_id, sq.name, sq.group_id, slt.name, tsd.name, st.create_time_unix, st.archive_flag
FROM ticket st
    JOIN queue sq ON st.queue_id = sq.id
    JOIN ticket_state tsd ON st.ticket_state_id = tsd.id
    JOIN ticket_lock_type slt ON st.ticket_lock_id = slt.id
WHERE st.id = ?
END
        Bind => [ \$Param{TicketID} ]
    );

    my %TicketData;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $TicketData{QueueID}        = $Row[0];
        $TicketData{Queue}          = $Row[1];
        $TicketData{GroupID}        = $Row[2];
        $TicketData{Lock}           = $Row[3];
        $TicketData{State}          = $Row[4];
        $TicketData{CreateTimeUnix} = $Row[5];
        $TicketData{ArchiveFlag}    = $Row[6];
    }

    # check if this ticket is still viewable
    my @ViewableStates = $StateObject->StateGetStatesByType(
        Type   => 'Viewable',
        Result => 'Name',
    );

    my $ViewableStatesHit = 0;

    for (@ViewableStates) {
        if ( $_ =~ /^$TicketData{State}$/i ) {
            $ViewableStatesHit = 1;
        }
    }

    # do nothing if state is not viewable
    if ( !$ViewableStatesHit ) {
        return 1;
    }

    # do nothing if ticket is archived
    if ( $TicketData{ArchiveFlag} ) {
        return 1;
    }

    return if !$DBObject->Do(
        SQL  => 'INSERT INTO ticket_index (ticket_id, queue_id, queue, group_id, s_lock, s_state, create_time_unix)'
              . ' VALUES (?, ?, ?, ?, ?, ?, ?)',
        Bind => [
            \$Param{TicketID},     \$TicketData{QueueID}, \$TicketData{Queue},
            \$TicketData{GroupID}, \$TicketData{Lock},    \$TicketData{State},
            \$TicketData{CreateTimeUnix},
        ],
    );

    return 1;
}

sub TicketLockAcceleratorDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(TicketID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # db query
    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'DELETE FROM ticket_lock_index WHERE ticket_id = ?',
        Bind => [ \$Param{TicketID} ],
    );

    return 1;
}

sub TicketLockAcceleratorAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(TicketID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'INSERT INTO ticket_lock_index (ticket_id) VALUES (?)',
        Bind => [ \$Param{TicketID} ],
    );

    return 1;
}

sub TicketAcceleratorIndex {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(UserID QueueID ShownQueueIDs)) {
        if ( !exists( $Param{$_} ) ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    my %Queues;
    $Queues{MaxAge}       = 0;
    $Queues{TicketsShown} = 0;
    $Queues{TicketsAvail} = 0;

    my @QueueIDs = @{ $Param{ShownQueueIDs} };

    my @ViewableLockIDs = $Kernel::OM->Get('Kernel::System::Lock')->LockViewableLock( Type => 'ID' );
    my %UserPreferences = $Kernel::OM->Get('Kernel::System::User')->GetPreferences( UserID => $Param{UserID} );

    # prepare "All tickets: ??" in Queue
    my @ViewableLocks = $Kernel::OM->Get('Kernel::System::Lock')->LockViewableLock(
        Type => 'Name',
    );

    my %ViewableLocks = ( map { $_ => 1 } @ViewableLocks );

    my @ViewableStateIDs = $Kernel::OM->Get('Kernel::System::State')->StateGetStatesByType(
        Type   => 'Viewable',
        Result => 'ID',
    );

    if (@QueueIDs) {

        # get database object
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

        my $SQL = "SELECT count(*) FROM ticket st"
                . " WHERE st.ticket_state_id IN ( ${\(join ', ', @ViewableStateIDs)} )"
                . "  AND st.queue_id IN (";

        for ( 0 .. $#QueueIDs ) {

            if ( $_ > 0 ) {
                $SQL .= ",";
            }

            $SQL .= $DBObject->Quote( $QueueIDs[$_], 'Integer' );
        }

        $SQL .= " )";

        $DBObject->Prepare( SQL => $SQL );

        while ( my @Row = $DBObject->FetchrowArray() ) {
            $Queues{AllTickets} = $Row[0];
        }
    }

    # get user groups
    my $Type             = 'rw';
    my $AgentTicketQueue = $Kernel::OM->Get('Kernel::Config')->Get('Ticket::Frontend::AgentTicketQueue');

    if (
        $AgentTicketQueue
        && ref $AgentTicketQueue eq 'HASH'
        && $AgentTicketQueue->{ViewAllPossibleTickets}
    ) {
        $Type = 'ro';
    }

    my %GroupList = $Kernel::OM->Get('Kernel::System::Group')->PermissionUserGet(
        UserID => $Param{UserID},
        Type   => $Type,
    );

    my @GroupIDs = sort keys %GroupList;

    # get index
    $Queues{MaxAge} = 0;

    # check if user is in min. one group! if not, return here
    if ( !@GroupIDs ) {

        my %Hashes;
        $Hashes{QueueID} = 0;
        $Hashes{Queue}   = 'CustomQueue';
        $Hashes{MaxAge}  = 0;
        $Hashes{Count}   = 0;

        push @{ $Queues{Queues} }, \%Hashes;

        return %Queues;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # CustomQueue add on
    my $SQL = "SELECT count(*), ti.s_lock"
            . " FROM ticket_index ti, personal_queues suq, ticket_lock_type tl"
            . " WHERE suq.queue_id = ti.queue_id"
            . "  AND tl.name = ti.s_lock"
            . "  AND ti.group_id IN ( ${\(join ', ', @GroupIDs)} )"
            . "  AND suq.user_id = $Param{UserID}";

    if ( $Self->{UserPreferences}->{UserViewAllTickets} ) {
        $SQL .= " AND tl.id IN ( ${\(join ', ', @ViewableLockIDs)} )";
    }

    $SQL .= " GROUP BY ti.s_lock";

    return if !$DBObject->Prepare(
        SQL => $SQL
    );

    my %CustomQueueHashes = (
        QueueID => 0,
        Queue   => 'CustomQueue',
        MaxAge  => 0,
        Count   => 0,
        Total   => 0,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        $CustomQueueHashes{Total} += $Row[0];
        if ( $ViewableLocks{ $Row[1] } ) {
            $CustomQueueHashes{Count} += $Row[0];
        }
    }

    push @{ $Queues{Queues} }, \%CustomQueueHashes;

    # prepare the tickets in Queue bar (all data only with my/your Permission)
    if ( $Self->{UserPreferences}->{UserViewAllTickets} ) {
        $SQL = "SELECT queue_id, queue, min(create_time_unix), s_lock, count(*)"
             . " FROM ticket_index ti, ticket_lock_type tl"
             . " WHERE group_id IN ( ${\(join ', ', @GroupIDs)} )"
             . "  AND tl.name = ti.s_lock"
             . "  AND tl.id IN ( ${\(join ', ', @ViewableLockIDs)} )";
    }
    else {
        $SQL = "SELECT queue_id, queue, min(create_time_unix), s_lock, count(*)"
             . " FROM ticket_index"
             . " WHERE group_id IN ( ${\(join ', ', @GroupIDs)} )";
    }

    $SQL .= " GROUP BY queue_id, queue, s_lock"
          . " ORDER BY queue";

    return if !$DBObject->Prepare(
        SQL => $SQL,
    );

    # get time object
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    my %QueuesSeen;
    while ( my @Row = $DBObject->FetchrowArray() ) {

        my $Queue     = $Row[1];
        my $QueueData = $QueuesSeen{$Queue};    # ref to HASH

        if ( !$QueueData ) {

            $QueueData = $QueuesSeen{$Queue} = {
                QueueID => $Row[0],
                Queue   => $Queue,
                Total   => 0,
                Count   => 0,
                MaxAge  => 0,
            };

            push @{ $Queues{Queues} }, $QueueData;
        }

        my $Count = $Row[4];
        $QueueData->{Total} += $Count;

        if ( $ViewableLocks{ $Row[3] } ) {

            $QueueData->{Count} += $Count;

            my $MaxAge = $TimeObject->SystemTime() - $Row[2];
            $QueueData->{MaxAge} = $MaxAge if $MaxAge > $QueueData->{MaxAge};

            # get the oldest queue id
            if ( $QueueData->{MaxAge} > $Queues{MaxAge} ) {
                $Queues{MaxAge}          = $QueueData->{MaxAge};
                $Queues{QueueIDOfMaxAge} = $QueueData->{QueueID};
            }
        }

        # set some things
        if ( $Param{QueueID} eq $Queue ) {
            $Queues{TicketsShown} = $QueueData->{Total};
            $Queues{TicketsAvail} = $QueueData->{Count};
        }
    }

    return %Queues;
}

sub TicketAcceleratorRebuild {
    my ( $Self, %Param ) = @_;

    # get needed object
    my $DBObject   = $Kernel::OM->Get('Kernel::System::DB');
    my $LockObject = $Kernel::OM->Get('Kernel::System::Lock');

    my %LockIDs            = $LockObject->LockList( UserID => 1 );
    my %ViewableLockIDs    = map { $_ => 1 } $LockObject->LockViewableLock( Type => 'ID' );
    my @NotViewableLockIDs;

    for ( sort keys %LockIDs ) {
        next if $ViewableLockIDs{$_};
        push( @NotViewableLockIDs, $_ );
    }

    my @ViewableTicketIDs = $Self->TicketSearch(
        Result       => 'ARRAY',
        Permission   => 'ro',
        ArchiveFlags => ['n'],
        UserID       => 1,
        Limit        => 0
    );

    # write index
    return if !$DBObject->Do( SQL => 'DELETE FROM ticket_index' );

    for (@ViewableTicketIDs) {
        $Self->TicketAcceleratorAdd(
            TicketID => $_,
            Rebuild  => 1
        );
    }

    # write lock index
    my @ViewableLockTicketIDs = $Self->TicketSearch(
        Result       => 'ARRAY',
        Permission   => 'ro',
        LockIDs      => \@NotViewableLockIDs,
        UserID       => 1,
        Limit        => 0
    );

    # add lock index entry
    return if !$DBObject->Do( SQL => 'DELETE FROM ticket_lock_index' );

    for (@ViewableLockTicketIDs) {
        $Self->TicketLockAcceleratorAdd( TicketID => $_ );
    }

    return 1;
}

sub GetIndexTicket {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(TicketID)) {
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

    # sql query
    return if !$DBObject->Prepare(
        SQL  => 'SELECT ticket_id, queue_id, queue, group_id, s_lock, s_state, create_time_unix'
              . ' FROM ticket_index'
              . ' WHERE ticket_id = ?',
        Bind => [ \$Param{TicketID} ]
    );

    my %Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Data{TicketID}       = $Row[0];
        $Data{QueueID}        = $Row[1];
        $Data{Queue}          = $Row[2];
        $Data{GroupID}        = $Row[3];
        $Data{Lock}           = $Row[4];
        $Data{State}          = $Row[5];
        $Data{CreateTimeUnix} = $Row[6];
    }

    return %Data;
}

sub _GetIndexTicketLock {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(TicketID)) {
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

    # sql query
    return if !$DBObject->Prepare(
        SQL  => 'SELECT ticket_id FROM ticket_lock_index WHERE ticket_id = ?',
        Bind => [ \$Param{TicketID} ],
    );

    my $Hit = 0;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Hit = 1;
    }

    return $Hit;
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
