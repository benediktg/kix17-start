# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::ProcessManagement::DB::Entity;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Main',
);

=head1 NAME

Kernel::System::ProcessManagement::DB::Entity

=head1 SYNOPSIS

Process Management DB Entity backend

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $EntityObject = $Kernel::OM->Get('Kernel::System::ProcessManagement::DB::Entity');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{ValidEntities} = {
        'Process'          => 1,
        'Activity'         => 1,
        'ActivityDialog'   => 1,
        'Transition'       => 1,
        'TransitionAction' => 1,
    };

    return $Self;
}

=item EntityIDGenerate()

generate unique Entity ID

    my $EntityID = $EntityObject->EntityIDGenerate(
        EntityType     => 'Process',       # mandatory, 'Process' || 'Activity' || 'ActivityDialog'
                                           #    || 'Transition' || 'TransitionAction'
        UserID         => 123,             # mandatory
    );

Returns:

    $EntityID = 'P1';

=cut

sub EntityIDGenerate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Key (qw(EntityType UserID)) {
        if ( !$Param{$Key} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Key!",
            );
            return;
        }
    }

    # check entity type
    if ( !$Self->{ValidEntities}->{ $Param{EntityType} } ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "The EntityType:$Param{EntityType} is invalid!"
        );
        return;

    }

    # this is not a 'proper' GUID as defined in RFC 4122 but it's close enough for
    # our purposes and we can replace it later if needed
    my $GUID = $Kernel::OM->Get('Kernel::System::Main')->GenerateRandomString(
        Length     => 32,
        Dictionary => [ 0 .. 9, 'a' .. 'f' ],    # hexadecimal
    );

    my $EntityID = $Param{EntityType} . '-' . $GUID;

    return $EntityID;
}

=item EntitySyncStateSet()

set sync state for an entity.

    my $Success = $EntityObject->EntitySyncStateSet(
        EntityType       => 'Process',      # 'Process' || 'Activity' || 'ActivityDialog'
                                            #   || 'Transition' || 'TransitionAction', type of the
                                            #   entity
        EntityID         => 'P1',
        SyncState        => 'not_sync',     # the sync state to set
        UserID           => 123,
    );

=cut

sub EntitySyncStateSet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(EntityType EntityID SyncState UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # check entity type
    if ( !$Self->{ValidEntities}->{ $Param{EntityType} } ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "The EntityType:$Param{EntityType} is invalid!"
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # create new
    if ( !%{ $Self->EntitySyncStateGet(%Param) || {} } ) {
        return if !$DBObject->Do(
            SQL  => 'INSERT INTO pm_entity_sync (entity_type, entity_id, sync_state, create_time, change_time)'
                  . ' VALUES (?, ?, ?, current_timestamp, current_timestamp)',
            Bind => [
                \$Param{EntityType}, \$Param{EntityID}, \$Param{SyncState},
            ],
        );
    }
    else {    # update existing

        return if !$DBObject->Do(
            SQL => 'UPDATE pm_entity_sync'
                 . ' SET sync_state = ?, change_time = current_timestamp'
                 . ' WHERE entity_type = ?'
                 . '  AND entity_id = ?',
            Bind => [
                \$Param{SyncState}, \$Param{EntityType}, \$Param{EntityID},
            ],
        );
    }

    return 1;
}

=item EntitySyncStateGet()

gets the sync state of an entity

    my $EntitySyncState = $EntityObject->EntitySyncStateGet(
        EntityType       => 'Process',      # 'Process' || 'Activity' || 'ActivityDialog'
                                            #   || 'Transition' || 'TransitionAction', type of the
                                            #   entity
        EntityID         => 'P1',
        UserID           => 123,
    );

If sync state was found, returns:

    $ObjectLockState = {
        EntityType       => 'Process',
        EntityID         => 'P1',
        SyncState        => 'not_sync',
        CreateTime       => '2011-02-08 15:08:00',
        ChangeTime       => '2011-02-08 15:08:00',
    };

If no sync state was found, returns undef.

=cut

sub EntitySyncStateGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(EntityType EntityID UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # check entity type
    if ( !$Self->{ValidEntities}->{ $Param{EntityType} } ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "The EntityType:$Param{EntityType} is invalid!"
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL => 'SELECT entity_type, entity_id, sync_state, create_time, change_time'
             . ' FROM pm_entity_sync'
             . ' WHERE entity_type = ?'
             . '  AND entity_id = ?',
        Bind => [
            \$Param{EntityType}, \$Param{EntityID},
        ],
    );

    my %Result;

    while ( my @Data = $DBObject->FetchrowArray() ) {

        %Result = (
            EntityType => $Data[0],
            EntityID   => $Data[1],
            SyncState  => $Data[2],
            CreateTime => $Data[3],
            ChangeTime => $Data[4],
        );
    }

    return if !IsHashRefWithData( \%Result );

    return \%Result;
}

=item EntitySyncStateDelete()

deletes sync state of an entity.

    my $Success = $EntityObject->EntitySyncStateDelete(
        EntityType       => 'Process',      # 'Process' || 'Activity' || 'ActivityDialog'
                                            #   || 'Transition' || 'TransitionAction', type of the
                                            #   entity
        EntityID         => 'P1',
        UserID           => 123,
    );

=cut

sub EntitySyncStateDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Key (qw(EntityType EntityID UserID)) {
        if ( !$Param{$Key} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Key!"
            );
            return;
        }
    }

    # check entity type
    if ( !$Self->{ValidEntities}->{ $Param{EntityType} } ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "The EntityType:$Param{EntityType} is invalid!"
        );
        return;
    }

    return if ( !%{ $Self->EntitySyncStateGet(%Param) || {} } );

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'DELETE FROM pm_entity_sync WHERE entity_type = ? AND entity_id = ?',
        Bind => [
            \$Param{EntityType}, \$Param{EntityID},
        ],
    );

    return 1;
}

=item EntitySyncStatePurge()

deletes all entries .

    my $Success = $EntityObject->EntitySyncStatePurge(
        UserID           => 123,
    );

=cut

sub EntitySyncStatePurge {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'DELETE FROM pm_entity_sync',
        Bind => [],
    );

    return 1;
}

=item EntitySyncStateList()

gets a list of sync states.

    my $EntitySyncStateList = $EntityObject->EntitySyncStateList(
        EntityType       => 'Process',      # optional, 'Process' || 'Activity' || 'ActivityDialog'
                                            #   || 'Transition' || 'TransitionAction', type of the
                                            #   entity
        SyncState        => 'not_sync',     # optional, only entries with this sync state
        UserID           => 123,
    );

Returns:

    $EntitySyncStateList = [
        {
            EntityType       => 'Process',
            EntityID         => 'P1',
            SyncState        => 'sync_started',
            CreateTime       => '2011-02-08 15:08:00',
            ChangeTime       => '2011-02-08 15:08:00',
        },
        ...
    ];

=cut

sub EntitySyncStateList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    if ( $Param{EntityType} ) {

        # check entity type
        if ( !$Self->{ValidEntities}->{ $Param{EntityType} } ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "The EntityType:$Param{EntityType} is invalid!"
            );
            return;
        }
    }

    my $SQL = 'SELECT entity_type, entity_id, sync_state, create_time, change_time'
            . ' FROM pm_entity_sync';

    my @Bind;

    if ( $Param{EntityType} ) {
        $SQL .= ' WHERE entity_type = ?';
        push @Bind, \$Param{EntityType};

        if ( $Param{SyncState} ) {
            $SQL .= ' AND sync_state = ?';
            push @Bind, \$Param{SyncState};
        }
    }
    elsif ( $Param{SyncState} ) {
        $SQL .= ' WHERE sync_state = ?';
        push @Bind, \$Param{SyncState};
    }

    $SQL .= ' ORDER BY entity_id ASC';

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my @Result;
    while ( my @Data = $DBObject->FetchrowArray() ) {

        push @Result, {
            EntityType => $Data[0],
            EntityID   => $Data[1],
            SyncState  => $Data[2],
            CreateTime => $Data[3],
            ChangeTime => $Data[4],
        };
    }

    return \@Result;
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
