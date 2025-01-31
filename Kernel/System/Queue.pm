# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Queue;

use strict;
use warnings;

use base qw(Kernel::System::EventHandler);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Cache',
    'Kernel::System::CustomerGroup',
    'Kernel::System::DB',
    'Kernel::System::Group',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::StandardTemplate',
    'Kernel::System::SysConfig',
    'Kernel::System::Valid',
);

=head1 NAME

Kernel::System::Queue - queue lib

=head1 SYNOPSIS

All queue functions. E. g. to add queue or other functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{QueueID} = $Param{QueueID} || '';

    $Self->{CacheType} = 'Queue';
    $Self->{CacheTTL}  = 60 * 60 * 24 * 20;

    # load generator preferences module
    my $GeneratorModule = $Kernel::OM->Get('Kernel::Config')->Get('Queue::PreferencesModule')
        || 'Kernel::System::Queue::PreferencesDB';
    if ( $Kernel::OM->Get('Kernel::System::Main')->Require($GeneratorModule) ) {
        $Self->{PreferencesObject} = $GeneratorModule->new();
    }

    # --------------------------------------------------- #
    #  default queue settings                             #
    #  these settings are used by the CLI version         #
    # --------------------------------------------------- #
    $Self->{QueueDefaults} = {
        Calendar            => '',
        UnlockTimeout       => 0,
        FirstResponseTime   => 0,
        FirstResponseNotify => 0,
        UpdateTime          => 0,
        UpdateNotify        => 0,
        SolutionTime        => 0,
        SolutionNotify      => 0,
        SystemAddressID     => 1,
        SalutationID        => 1,
        SignatureID         => 1,
        FollowUpID          => 1,
        FollowUpLock        => 0,
    };

    # init of event handler
    $Self->EventHandlerInit(
        Config => 'Queue::EventModulePost',
    );

    return $Self;
}

=item GetQueuesForEmailAddress()

get all queues where the given Email address is used as "sender address" as hash (id, RealName)

    my %QueueIDs = $QueueObject->GetQueuesForEmailAddress(
        AddressID  => 2,
    );

=cut

sub GetQueuesForEmailAddress {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{AddressID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need AddressID!',
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL => 'SELECT id, name FROM queue '
            . 'WHERE system_address_id = ? ',
        Bind  => [ \$Param{AddressID} ],
    );

    # fetch the result
    my %Queues;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Queues{$Row[0]} = $Row[1];
    }

    return %Queues;
}

=item GetSystemAddress()

get a queue system email address as hash (Email, RealName)

    my %Address = $QueueObject->GetSystemAddress(
        QueueID => 123,
    );

=cut

sub GetSystemAddress {
    my ( $Self, %Param ) = @_;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my %Address;
    my $QueueID = $Param{QueueID} || $Self->{QueueID};

    return if !$DBObject->Prepare(
        SQL => 'SELECT sa.value0, sa.value1 FROM system_address sa, queue sq '
            . 'WHERE sq.id = ? AND sa.id = sq.system_address_id',
        Bind  => [ \$QueueID ],
        Limit => 1,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Address{Email}    = $Row[0];
        $Address{RealName} = $Row[1];
    }

    # prepare realname quote
    if ( $Address{RealName} =~ /(?:,|@|\(|\)|:)/ && $Address{RealName} !~ /^(?:"|')/ ) {
        $Address{RealName} =~ s/"/\"/g;
        $Address{RealName} = '"' . $Address{RealName} . '"';
    }

    return %Address;
}

=item GetSignature()

get a queue signature

    my $Signature = $QueueObject->GetSignature(QueueID => 123);

=cut

sub GetSignature {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{QueueID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need QueueID!',
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL => 'SELECT text FROM signature si, queue sq '
            . ' WHERE sq.id = ? AND sq.signature_id = si.id',
        Bind  => [ \$Param{QueueID} ],
        Limit => 1,
    );

    # fetch the result
    my $String = '';
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $String = $Row[0];
    }

    return $String;
}

=item QueueStandardTemplateMemberAdd()

to add a template to a queue

    my $Success = $QueueObject->QueueStandardTemplateMemberAdd(
        QueueID            => 123,
        StandardTemplateID => 123,
        Active             => 1,        # to set/confirm (1) or remove (0) the relation
        UserID             => 123,
    );

=cut

sub QueueStandardTemplateMemberAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(QueueID StandardTemplateID UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # delete existing relation
    return if !$DBObject->Do(
        SQL  => <<'END',
DELETE FROM queue_standard_template
WHERE queue_id = ?
    AND standard_template_id = ?
END
        Bind => [ \$Param{QueueID}, \$Param{StandardTemplateID} ],
    );

    # return if relation is not active
    if ( !$Param{Active} ) {
        $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
            Type => $Self->{CacheType},
        );
        return 1;
    }

    # insert new relation
    my $Success = $DBObject->Do(
        SQL  => <<'END',
INSERT INTO queue_standard_template (queue_id, standard_template_id, create_time,
    create_by, change_time, change_by)
VALUES (?, ?, current_timestamp, ?, current_timestamp, ?)
END
        Bind => [ \$Param{QueueID}, \$Param{StandardTemplateID}, \$Param{UserID}, \$Param{UserID} ],
    );

    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
        Type => $Self->{CacheType},
    );
    return $Success;
}

=item QueueStandardTemplateMemberList()

get std responses of a queue

    my %Templates = $QueueObject->QueueStandardTemplateMemberList( QueueID => 123 );

Returns:
    %Templates = (
        1 => 'Some Name',
        2 => 'Some Name',
    );

    my %Responses = $QueueObject->QueueStandardTemplateMemberList(
        QueueID       => 123,
        TemplateTypes => 1,
    );

Returns:
    %Responses = (
        Answer => {
            1 => 'Some Name',
            2 => 'Some Name',
        },
        # ...
    );

    my %Queues = $QueueObject->QueueStandardTemplateMemberList( StandardTemplateID => 123 );

Returns:
    %Queues = (
        1 => 'Some Name',
        2 => 'Some Name',
    );

=cut

sub QueueStandardTemplateMemberList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{QueueID} && !$Param{StandardTemplateID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got no StandardTemplateID or QueueID!',
        );
        return;
    }

    # get needed objects
    my $ValidObject = $Kernel::OM->Get('Kernel::System::Valid');
    my $DBObject    = $Kernel::OM->Get('Kernel::System::DB');

    my $TemplateTypes = $Param{TemplateTypes} || '0';

    my $CacheKey;

    if ( $Param{QueueID} ) {

        # check if this result is present (in cache)
        $CacheKey = "StandardTemplates::$Param{QueueID}::$TemplateTypes";
        my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
            Type => $Self->{CacheType},
            Key  => $CacheKey,
        );
        return %{$Cache} if ref $Cache eq 'HASH';

        # get std. templates
        my $SQL = "SELECT st.id, st.name, st.template_type "
            . " FROM standard_template st, queue_standard_template qst WHERE "
            . " qst.queue_id IN ("
            . $DBObject->Quote( $Param{QueueID}, 'Integer' )
            . ") AND "
            . " qst.standard_template_id = st.id AND "
            . " st.valid_id IN ( ${\(join ', ', $ValidObject->ValidIDsGet())} )"
            . " ORDER BY st.name";

        return if !$DBObject->Prepare( SQL => $SQL );

        # fetch the result
        my %StandardTemplates;
        while ( my @Row = $DBObject->FetchrowArray() ) {

            if ( $Param{TemplateTypes} ) {
                $StandardTemplates{ $Row[2] }->{ $Row[0] } = $Row[1];
            }
            else {
                $StandardTemplates{ $Row[0] } = $Row[1];
            }
        }

        # store std templates (in cache)
        $Kernel::OM->Get('Kernel::System::Cache')->Set(
            Type  => $Self->{CacheType},
            TTL   => $Self->{CacheTTL},
            Key   => $CacheKey,
            Value => \%StandardTemplates,

        );
        return %StandardTemplates;
    }

    else {

        # check if this result is present (in cache)
        $CacheKey = "Queues::$Param{StandardTemplateID}";
        my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
            Type => $Self->{CacheType},
            Key  => $CacheKey,
        );
        return %{$Cache} if ref $Cache eq 'HASH';

        # get queues
        my $SQL = "SELECT q.id, q.name "
            . " FROM queue q, queue_standard_template qst WHERE "
            . " qst.standard_template_id IN ("
            . $DBObject->Quote( $Param{StandardTemplateID}, 'Integer' )
            . ") AND "
            . " qst.queue_id = q.id AND "
            . " q.valid_id IN ( ${\(join ', ', $ValidObject->ValidIDsGet())} )"
            . " ORDER BY q.name";

        return if !$DBObject->Prepare( SQL => $SQL );

        # fetch the result
        my %Queues;
        while ( my @Row = $DBObject->FetchrowArray() ) {
            $Queues{ $Row[0] } = $Row[1];
        }

        # store queues (in cache)
        $Kernel::OM->Get('Kernel::System::Cache')->Set(
            Type  => $Self->{CacheType},
            TTL   => $Self->{CacheTTL},
            Key   => $CacheKey,
            Value => \%Queues,
        );

        return %Queues;
    }
}

=item GetAllQueues()

get all valid system queues

    my %Queues = $QueueObject->GetAllQueues();

get all system queues of a user with permission type (e. g. ro, move_into, rw, ...)

    my %Queues = $QueueObject->GetAllQueues( UserID => 123, Type => 'ro' );

=cut

sub GetAllQueues {
    my ( $Self, %Param ) = @_;

    my $Type = $Param{Type} || 'ro';

    # get needed objects
    my $ValidObject = $Kernel::OM->Get('Kernel::System::Valid');
    my $DBObject    = $Kernel::OM->Get('Kernel::System::DB');

    # fetch all queues
    my $CacheKey;
    if ( $Param{UserID} ) {

        # get group list
        my %GroupList = $Kernel::OM->Get('Kernel::System::Group')->PermissionUserGet(
            UserID => $Param{UserID},
            Type   => $Type,
        );

        return if !%GroupList;

        my $GroupString = join ', ', sort keys %GroupList;
        $CacheKey = "GetAllQueues::UserID::${Type}::${GroupString}::$Param{UserID}";

        # check cache
        my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
            Type => $Self->{CacheType},
            Key  => $CacheKey,
        );
        return %{$Cache} if $Cache;

        return if !$DBObject->Prepare(
            SQL => "SELECT id, name FROM queue WHERE "
                . " group_id IN ( $GroupString ) AND "
                . " valid_id IN ( ${\(join ', ', $ValidObject->ValidIDsGet())} )",
        );
    }
    elsif ( $Param{CustomerUserID} ) {

        # get group ids
        my @GroupIDs = $Kernel::OM->Get('Kernel::System::CustomerGroup')->GroupMemberList(
            UserID => $Param{CustomerUserID},
            Type   => $Type,
            Result => 'ID',
        );

        return if !@GroupIDs;

        my $GroupString = join ', ', sort @GroupIDs;
        $CacheKey = "GetAllQueues::CustomerUserID::${Type}::${GroupString}::$Param{CustomerUserID}";

        # check cache
        my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
            Type => $Self->{CacheType},
            Key  => $CacheKey,
        );
        return %{$Cache} if $Cache;

        return if !$DBObject->Prepare(
            SQL => "SELECT id, name FROM queue WHERE "
                . " group_id IN ( $GroupString ) AND "
                . " valid_id IN ( ${\(join ', ', $ValidObject->ValidIDsGet())} )",
        );
    }
    else {

        $CacheKey = 'GetAllQueues';

        # check cache
        my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
            Type => $Self->{CacheType},
            Key  => $CacheKey,
        );
        return %{$Cache} if $Cache;

        return if !$DBObject->Prepare(
            SQL => "SELECT id, name FROM queue WHERE valid_id IN "
                . "( ${\(join ', ', $ValidObject->ValidIDsGet())} )",
        );
    }

    my %MoveQueues;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $MoveQueues{ $Row[0] } = $Row[1];
    }

    # set cache
    $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => $CacheKey,
        Value => \%MoveQueues,
    );

    return %MoveQueues;
}

=item GetAllCustomQueues()

get all custom queues of one user

    my @Queues = $QueueObject->GetAllCustomQueues( UserID => 123 );

=cut

sub GetAllCustomQueues {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need UserID!'
        );
        return;
    }

    # check cache
    my $CacheKey = 'GetAllCustomQueues::' . $Param{UserID};
    my $Cache    = $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return @{$Cache} if $Cache;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # search all custom queues
    return if !$DBObject->Prepare(
        SQL  => 'SELECT queue_id FROM personal_queues WHERE user_id = ?',
        Bind => [ \$Param{UserID} ],
    );

    # fetch the result
    my @QueueIDs;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @QueueIDs, $Row[0];
    }

    # set cache
    $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => $CacheKey,
        Value => \@QueueIDs,
    );

    return @QueueIDs;
}

=item QueueLookup()

get id or name for queue

    my $Queue = $QueueObject->QueueLookup(
        QueueID => $QueueID,
        Valid   => 1,         # not required -> 0|1 (default 0)
    );

    my $QueueID = $QueueObject->QueueLookup(
        Queue => $Queue,
        Valid => 1,           # not required -> 0|1 (default 0)
    );

=cut

sub QueueLookup {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Queue} && !$Param{QueueID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got no Queue or QueueID!'
        );
        return;
    }

    # set valid option
    my $Valid = $Param{Valid};
    if ( $Valid ) {
        $Valid = 1;
    }
    else {
        $Valid = 0;
    }

    # get queue data
    my %QueueList = $Self->QueueList(
        Valid => $Valid,
    );

    my $Key;
    my $Value;
    my $ReturnData;
    if ( $Param{QueueID} ) {
        $Key        = 'QueueID';
        $Value      = $Param{QueueID};
        $ReturnData = $QueueList{ $Param{QueueID} };
    }
    else {
        $Key   = 'Queue';
        $Value = $Param{Queue};
        my %QueueListReverse = reverse %QueueList;
        $ReturnData = $QueueListReverse{ $Param{Queue} };
    }

    # check if data exists
    if ( !$ReturnData ) {
        if ( $Valid ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Found no valid $Key for $Value!",
            );
        }
        else {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Found no $Key for $Value!",
            );
        }
        return;
    }

    return $ReturnData;
}

=item GetFollowUpOption()

get FollowUpOption for the given QueueID

    my $FollowUpOption = $QueueObject->GetFollowUpOption( QueueID => $QueueID );

returns any of 'possible', 'reject', 'new ticket'.

=cut

sub GetFollowUpOption {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{QueueID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need QueueID!'
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # fetch queues data
    return if !$DBObject->Prepare(
        SQL => 'SELECT sf.name FROM follow_up_possible sf, queue sq '
            . ' WHERE sq.follow_up_id = sf.id AND sq.id = ?',
        Bind  => [ \$Param{QueueID} ],
        Limit => 1,
    );

    my $Return = '';
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Return = $Row[0];
    }

    return $Return;
}

=item GetFollowUpLockOption()

get FollowUpLockOption for the given QueueID

    my $FollowUpLockOption = $QueueObject->GetFollowUpLockOption( QueueID => $QueueID );

returns '1' if ticket should be locked after a follow up, '0' if not.

=cut

sub GetFollowUpLockOption {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{QueueID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need QueueID!'
        );
        return;
    }

    # get (already cached) queue data
    my %Queue = $Self->QueueGet(
        ID => $Param{QueueID},
    );

    return if !%Queue;
    return $Queue{FollowUpLock};
}

=item GetQueueGroupID()

get GroupID defined for the given QueueID.

    my $GroupID = $QueueObject->GetQueueGroupID( QueueID => $QueueID );

=cut

sub GetQueueGroupID {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{QueueID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need QueueID!'
        );
        return;
    }

    # get (already cached) queue data
    my %Queue = $Self->QueueGet(
        ID => $Param{QueueID},
    );

    return if !%Queue;
    return $Queue{GroupID};
}

=item QueueAdd()

add queue with attributes

    $QueueObject->QueueAdd(
        Name                => 'Some::Queue',
        ValidID             => 1,
        GroupID             => 1,
        Calendar            => 'Calendar1', # (optional)
        FirstResponseTime   => 120,         # (optional)
        FirstResponseNotify => 60,          # (optional, notify agent if first response escalation is 60% reached)
        UpdateTime          => 180,         # (optional)
        UpdateNotify        => 80,          # (optional, notify agent if update escalation is 80% reached)
        SolutionTime        => 580,         # (optional)
        SolutionNotify      => 80,          # (optional, notify agent if solution escalation is 80% reached)
        UnlockTimeout       => 480,         # (optional)
        FollowUpID          => 3,           # possible (1), reject (2) or new ticket (3) (optional, default 0)
        FollowUpLock        => 0,           # yes (1) or no (0) (optional, default 0)
        DefaultSignKey      => 'key name',  # (optional)
        SystemAddressID     => 1,
        SalutationID        => 1,
        SignatureID         => 1,
        Comment             => 'Some comment',
        UserID              => 123,
    );

=cut

sub QueueAdd {
    my ( $Self, %Param ) = @_;

    # check if this request is from web and not from command line
    if ( !$Param{NoDefaultValues} ) {
        for (
            qw(UnlockTimeout FirstResponseTime FirstResponseNotify UpdateTime UpdateNotify SolutionTime SolutionNotify
            FollowUpLock SystemAddressID SalutationID SignatureID
            FollowUpID FollowUpLock DefaultSignKey Calendar)
        ) {

            # I added default values in the Load Routine
            if ( !$Param{$_} ) {
                $Param{$_} = $Self->{QueueDefaults}->{$_} || 0;
            }
        }
    }

    for (qw(Name GroupID SystemAddressID SalutationID SignatureID ValidID UserID FollowUpID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # cleanup queue name
    $Param{Name} =~ s/(\n|\r)//g;
    $Param{Name} =~ s/\s$//g;

    # check queue name
    if ( $Param{Name} =~ /::$/i ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Invalid Queue name '$Param{Name}'!",
        );
        return;
    }

    # check if a queue with this name already exists
    if ( $Self->NameExistsCheck( Name => $Param{Name} ) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "A queue with name '$Param{Name}' already exists!"
        );
        return;
    }

    # get needed objects
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Do(
        SQL => 'INSERT INTO queue (name, group_id, unlock_timeout, system_address_id, '
            . ' calendar_name, default_sign_key, salutation_id, signature_id, '
            . ' first_response_time, first_response_notify, update_time, '
            . ' update_notify, solution_time, solution_notify, follow_up_id, '
            . ' follow_up_lock, valid_id, comments, create_time, create_by, '
            . ' change_time, change_by) VALUES '
            . ' (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
            . ' ?, current_timestamp, ?, current_timestamp, ?)',
        Bind => [
            \$Param{Name},     \$Param{GroupID},        \$Param{UnlockTimeout}, \$Param{SystemAddressID},
            \$Param{Calendar}, \$Param{DefaultSignKey}, \$Param{SalutationID},  \$Param{SignatureID},
            \$Param{FirstResponseTime}, \$Param{FirstResponseNotify}, \$Param{UpdateTime},
            \$Param{UpdateNotify},      \$Param{SolutionTime},        \$Param{SolutionNotify},
            \$Param{FollowUpID},        \$Param{FollowUpLock},        \$Param{ValidID},
            \$Param{Comment},           \$Param{UserID},              \$Param{UserID},
        ],
    );

    # get new id
    return if !$DBObject->Prepare(
        SQL   => 'SELECT id FROM queue WHERE name = ?',
        Bind  => [ \$Param{Name} ],
        Limit => 1,
    );

    # fetch the result
    my $QueueID = '';
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $QueueID = $Row[0];
    }

    # reset cache
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
        Type => $Self->{CacheType},
    );

    my $StandardTemplate2QueueByCreating = $ConfigObject->Get('StandardTemplate2QueueByCreating');

    # add default responses (if needed), add response by name
    if (
        $StandardTemplate2QueueByCreating
        && ref $StandardTemplate2QueueByCreating eq 'ARRAY'
        && @{$StandardTemplate2QueueByCreating}
    ) {

        # get standard template object
        my $StandardTemplateObject = $Kernel::OM->Get('Kernel::System::StandardTemplate');

        ST:
        for my $ST ( @{$StandardTemplate2QueueByCreating} ) {

            my $StandardTemplateID = $StandardTemplateObject->StandardTemplateLookup(
                StandardTemplate => $ST,
            );

            next ST if !$StandardTemplateID;

            $Self->QueueStandardTemplateMemberAdd(
                QueueID            => $QueueID,
                StandardTemplateID => $StandardTemplateID,
                Active             => 1,
                UserID             => $Param{UserID},
            );
        }
    }

    # get standard template id
    my $StandardTemplateID2QueueByCreating = $ConfigObject->Get(' StandardTemplate2QueueByCreating');

    # get queue data with updated name for QueueCreate event
    my %Queue = $Self->QueueGet( Name => $Param{Name} );

    # trigger event
    $Self->EventHandler(
        Event => 'QueueCreate',
        Data  => {
            Queue => \%Queue,
        },
        UserID => $Param{UserID},
    );

    return $QueueID if !$StandardTemplateID2QueueByCreating;
    return $QueueID if ref $StandardTemplateID2QueueByCreating ne 'ARRAY';
    return $QueueID if !@{$StandardTemplateID2QueueByCreating};

    # add template by id
    for my $StandardTemplateID ( @{$StandardTemplateID2QueueByCreating} ) {

        $Self->QueueStandardTemplateMemberAdd(
            QueueID            => $QueueID,
            StandardTemplateID => $StandardTemplateID,
            Active             => 1,
            UserID             => $Param{UserID},
        );
    }

    return $QueueID;
}

=item QueueGet()

get queue attributes

    my %Queue = $QueueObject->QueueGet(
        ID    => 123,
    );

    my %Queue = $QueueObject->QueueGet(
        Name  => 'Some::Queue',
    );

=cut

sub QueueGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ID} && !$Param{Name} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need ID or Name!'
        );
        return;
    }

    # check runtime cache
    my $CacheKey;
    my $Key;
    my $Value;
    if ( $Param{ID} ) {
        $CacheKey = 'QueueGetID::' . $Param{ID};
        $Key      = 'ID';
        $Value    = $Param{ID};
    }
    else {
        $CacheKey = 'QueueGetName::' . $Param{Name};
        $Key      = 'Name';
        $Value    = $Param{Name};
    }

    # check cache
    my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return %{$Cache} if $Cache;

    # sql
    my @Bind;
    my $SQL = 'SELECT q.name, q.group_id, q.unlock_timeout, '
        . 'q.system_address_id, q.salutation_id, q.signature_id, q.comments, q.valid_id, '
        . 'q.first_response_time, q.first_response_notify, '
        . 'q.update_time, q.update_notify, q.solution_time, q.solution_notify, '
        . 'q.follow_up_id, q.follow_up_lock, sa.value0, sa.value1, q.id, '
        . 'q.default_sign_key, q.calendar_name, q.create_time, q.change_time FROM queue q, '
        . 'system_address sa WHERE q.system_address_id = sa.id AND ';

    if ( $Param{ID} ) {
        $SQL .= 'q.id = ?';
        push @Bind, \$Param{ID};
    }
    else {
        $SQL .= 'q.name = ?';
        push @Bind, \$Param{Name};
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL   => $SQL,
        Bind  => \@Bind,
        Limit => 1,
    );

    # fetch the result
    my %Data;
    while ( my @Data = $DBObject->FetchrowArray() ) {
        %Data = (
            QueueID             => $Data[18],
            Name                => $Data[0],
            GroupID             => $Data[1],
            UnlockTimeout       => $Data[2],
            FirstResponseTime   => $Data[8],
            FirstResponseNotify => $Data[9],
            UpdateTime          => $Data[10],
            UpdateNotify        => $Data[11],
            SolutionTime        => $Data[12],
            SolutionNotify      => $Data[13],
            FollowUpID          => $Data[14],
            FollowUpLock        => $Data[15],
            SystemAddressID     => $Data[3],
            SalutationID        => $Data[4],
            SignatureID         => $Data[5],
            Comment             => $Data[6],
            ValidID             => $Data[7],
            Email               => $Data[16],
            RealName            => $Data[17],
            DefaultSignKey      => $Data[19],
            Calendar            => $Data[20] || '',
            CreateTime          => $Data[21],
            ChangeTime          => $Data[22],
        );
    }

    # check if data exists
    if ( !%Data ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Found no $Key for $Value!",
        );
        return;
    }

    # get queue preferences
    my %Preferences = $Self->QueuePreferencesGet( QueueID => $Data{QueueID} );

    # merge hash
    if (%Preferences) {
        %Data = ( %Data, %Preferences );
    }

    # set cache
    $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => $CacheKey,
        Value => \%Data,
    );

    return %Data;
}

=item QueueUpdate()

update queue attributes

    $QueueObject->QueueUpdate(
        QueueID             => 123,
        Name                => 'Some::Queue',
        ValidID             => 1,
        GroupID             => 1,
        Calendar            => '1', # (optional) default ''
        FirstResponseTime   => 120, # (optional)
        FirstResponseNotify => 60,  # (optional, notify agent if first response escalation is 60% reached)
        UpdateTime          => 180, # (optional)
        UpdateNotify        => 80,  # (optional, notify agent if update escalation is 80% reached)
        SolutionTime        => 580, # (optional)
        SolutionNotify      => 80,  # (optional, notify agent if solution escalation is 80% reached)
        SystemAddressID     => 1,
        SalutationID        => 1,
        SignatureID         => 1,
        UserID              => 123,
        FollowUpID          => 1,
        Comment             => 'Some Comment2',
        DefaultSignKey      => ''
        UnlockTimeOut       => ''
        FollowUpLock        => 1,
        ParentQueueID       => '',
        CheckSysConfig      => 0,   # (optional) default 1
    );

=cut

sub QueueUpdate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (
        qw(QueueID Name ValidID GroupID SystemAddressID SalutationID SignatureID UserID FollowUpID)
    ) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # check CheckSysConfig param
    if ( !defined $Param{CheckSysConfig} ) {
        $Param{CheckSysConfig} = 1;
    }

    # FollowUpLock 0 | 1
    $Param{FollowUpLock} = $Param{FollowUpLock} || 0;

    # DefaultSignKey   '' || 'string'
    $Param{DefaultSignKey} = $Param{DefaultSignKey} || '';

    # Calendar string  '', '1', '2', '3', '4', '5'  default ''
    $Param{Calendar} ||= '';

    # content -> time in seconds
    for my $Time (qw( UnlockTimeout FirstResponseTime UpdateTime SolutionTime )) {

        $Param{$Time} = $Param{$Time} || 0;

        if ( $Param{$Time} !~ m{^\d+$}smx ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "$Time is not numeric!"
            );
            return;
        }
    }

    # content integer from 0 - 99
    for my $Notify (qw(FirstResponseNotify  UpdateNotify  SolutionNotify)) {

        $Param{$Notify} = $Param{$Notify} || 0;

        if ( $Param{$Notify} !~ m{^\d{1,2}}smx ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "$Notify must be an integer in the range from 0 to 99!",
            );
            return;
        }
    }

    # cleanup queue name
    $Param{Name} =~ s/(\n|\r)//g;
    $Param{Name} =~ s/\s$//g;

    # check queue name
    if ( $Param{Name} =~ /::$/i ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Invalid Queue name '$Param{Name}'!",
        );
        return;
    }

    # check if queue name exists
    my %AllQueue = $Self->QueueList( Valid => 0 );
    my %OldQueue = $Self->QueueGet( ID => $Param{QueueID} );

    # check if a queue with this name already exists
    if (
        $Self->NameExistsCheck(
            ID   => $Param{QueueID},
            Name => $Param{Name}
        )
    ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "A queue with name '$Param{Name}' already exists!"
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # SQL
    return if !$DBObject->Do(
        SQL => <<'END',
UPDATE queue
SET name = ?, comments = ?, group_id = ?, unlock_timeout = ?, first_response_time = ?,
    first_response_notify = ?, update_time = ?, update_notify = ?, solution_time = ?,
    solution_notify = ?, follow_up_id = ?, follow_up_lock = ?, system_address_id = ?,
    calendar_name = ?, default_sign_key = ?, salutation_id = ?, signature_id = ?,
    valid_id = ?, change_time = current_timestamp, change_by = ?
WHERE id = ?
END
        Bind => [
            \$Param{Name}, \$Param{Comment}, \$Param{GroupID}, \$Param{UnlockTimeout},
            \$Param{FirstResponseTime}, \$Param{FirstResponseNotify}, \$Param{UpdateTime},
            \$Param{UpdateNotify},      \$Param{SolutionTime},        \$Param{SolutionNotify},
            \$Param{FollowUpID},        \$Param{FollowUpLock},        \$Param{SystemAddressID},
            \$Param{Calendar},          \$Param{DefaultSignKey},      \$Param{SalutationID},
            \$Param{SignatureID},       \$Param{ValidID},             \$Param{UserID},
            \$Param{QueueID},
        ],
    );

    # get queue data with updated name for QueueUpdate event
    my %Queue = $Self->QueueGet( Name => $Param{Name} );

    # trigger event
    $Self->EventHandler(
        Event => 'QueueUpdate',
        Data  => {
            Queue    => \%Queue,
            OldQueue => \%OldQueue,
        },
        UserID => $Param{UserID},
    );

    # reset cache
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
        Type => $Self->{CacheType},
    );

    # updated all sub queue names
    my @ParentQueue = split( /::/, $OldQueue{Name} );

    for my $QueueID ( sort keys %AllQueue ) {

        my @SubQueue = split( /::/, $AllQueue{$QueueID} );

        if ( $#SubQueue > $#ParentQueue ) {

            if ( $AllQueue{$QueueID} =~ /^\Q$OldQueue{Name}::\E/i ) {

                my $NewQueueName = $AllQueue{$QueueID};
                $NewQueueName =~ s/\Q$OldQueue{Name}\E/$Param{Name}/;

                return if !$DBObject->Do(
                    SQL  => <<'END',
UPDATE queue
SET name = ?, change_time = current_timestamp, change_by = ?
WHERE id = ?
END
                    Bind => [ \$NewQueueName, \$Param{UserID}, \$QueueID ],
                );

                # reset cache
                $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
                    Type => $Self->{CacheType},
                );
            }
        }
    }

    # check all SysConfig options
    return 1 if !$Param{CheckSysConfig};

    # check all SysConfig options and correct them automatically if necessary
    $Kernel::OM->Get('Kernel::System::SysConfig')->ConfigItemCheckAll();

    return 1;
}

=item QueueList()

get all queues

    my %Queues = $QueueObject->QueueList();

    my %Queues = $QueueObject->QueueList( Valid => 1 );

=cut

sub QueueList {
    my ( $Self, %Param ) = @_;

    # set valid option
    my $Valid = $Param{Valid} // 1;

    # check cache
    my $CacheKey = 'QueueList::' . $Valid;
    my $Cache    = $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return %{$Cache} if $Cache;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # sql query
    if ($Valid) {
        return if !$DBObject->Prepare(
            SQL  => "SELECT id, name FROM queue WHERE valid_id = ?",
            Bind => [ \$Valid ]
        );
    }
    else {
        return if !$DBObject->Prepare(
            SQL => 'SELECT id, name FROM queue',
        );
    }

    # fetch the result
    my %Queues;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Queues{ $Row[0] } = $Row[1];
    }

    # set cache
    $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => $CacheKey,
        Value => \%Queues,
    );

    return %Queues;
}

=item QueuePreferencesSet()

set queue preferences

    $QueueObject->QueuePreferencesSet(
        QueueID => 123,
        Key     => 'UserComment',
        Value   => 'some comment',
        UserID  => 123,
    );

=cut

sub QueuePreferencesSet {
    my ( $Self, %Param ) = @_;

    # delete cache
    my $Name = $Self->QueueLookup( QueueID => $Param{QueueID} );
    my @CacheKeys = (
        'QueueGetID::' . $Param{QueueID},
        'QueueGetName::' . $Name,
    );
    for my $CacheKey (@CacheKeys) {
        $Kernel::OM->Get('Kernel::System::Cache')->Delete(
            Type => $Self->{CacheType},
            Key  => $CacheKey,
        );
    }

    return $Self->{PreferencesObject}->QueuePreferencesSet(%Param);
}

=item QueuePreferencesGet()

get queue preferences

    my %Preferences = $QueueObject->QueuePreferencesGet(
        QueueID => 123,
        UserID  => 123,
    );

=cut

sub QueuePreferencesGet {
    my ( $Self, %Param ) = @_;

    return $Self->{PreferencesObject}->QueuePreferencesGet(%Param);
}

sub DESTROY {
    my $Self = shift;

    # execute all transaction events
    $Self->EventHandlerTransaction();

    return 1;
}

=item NameExistsCheck()

return 1 if another queue with this name already exists

    $Exist = $QueueObject->NameExistsCheck(
        Name => 'Some::Queue',
        ID => 1, # optional
    );

=cut

sub NameExistsCheck {
    my ( $Self, %Param ) = @_;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    return if !$DBObject->Prepare(
        SQL  => 'SELECT id FROM queue WHERE name = ?',
        Bind => [ \$Param{Name} ],
    );

    # fetch the result
    my $Flag;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        if ( !$Param{ID} || $Param{ID} ne $Row[0] ) {
            $Flag = 1;
        }
    }

    if ($Flag) {
        return 1;
    }

    return 0;
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
