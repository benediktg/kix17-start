# --
# Modified version of the work: Copyright (C) 2006-2018 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2018 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::AuthSession::FS;

use strict;
use warnings;

use Storable qw();

use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::Time',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get more common params
    $Self->{SessionSpool}      = $ConfigObject->Get('SessionDir');
    $Self->{SystemID}          = $ConfigObject->Get('SystemID');
    $Self->{SessionActiveTime} = $ConfigObject->Get('SessionActiveTime') || 60 * 10;

    if ( $Self->{SessionActiveTime} < 300 ) {
        $Self->{SessionActiveTime} = 300;
    }

    return $Self;
}

sub CheckSessionID {
    my ( $Self, %Param ) = @_;

    # check session id
    if ( !$Param{SessionID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got no SessionID!!'
        );
        return;
    }
    my $RemoteAddr = $ENV{REMOTE_ADDR} || 'none';

    # set default message
    $Self->{SessionIDErrorMessage} = Translatable('Session invalid. Please log in again.');

    # session id check
    my %Data = $Self->GetSessionIDData( SessionID => $Param{SessionID} );

    if ( !$Data{UserID} || !$Data{UserLogin} ) {
        $Self->{SessionIDErrorMessage} = Translatable('Session invalid. Please log in again.');
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "SessionID: '$Param{SessionID}' is invalid!!!",
        );
        return;
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # remote ip check
    if (
        $Data{UserRemoteAddr} ne $RemoteAddr
        && $ConfigObject->Get('SessionCheckRemoteIP')
        )
    {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "RemoteIP of '$Param{SessionID}' ($Data{UserRemoteAddr}) is "
                . "different from registered IP ($RemoteAddr). Invalidating session!"
                . " Disable config 'SessionCheckRemoteIP' if you don't want this!",
        );

        # delete session id if it isn't the same remote ip?
        if ( $ConfigObject->Get('SessionDeleteIfNotRemoteID') ) {
            $Self->RemoveSessionID( SessionID => $Param{SessionID} );
        }

        return;
    }

    # check session idle time
    my $TimeNow            = $Kernel::OM->Get('Kernel::System::Time')->SystemTime();
    my $MaxSessionIdleTime = $ConfigObject->Get('SessionMaxIdleTime');

    if ( ( $TimeNow - $MaxSessionIdleTime ) >= $Data{UserLastRequest} ) {

        $Self->{SessionIDErrorMessage} = Translatable('Session has timed out. Please log in again.');

        my $Timeout = int( ( $TimeNow - $Data{UserLastRequest} ) / ( 60 * 60 ) );

        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message =>
                "SessionID ($Param{SessionID}) idle timeout ($Timeout h)! Don't grant access!!!",
        );

        # delete session id if too old?
        if ( $ConfigObject->Get('SessionDeleteIfTimeToOld') ) {
            $Self->RemoveSessionID( SessionID => $Param{SessionID} );
        }

        return;
    }

    # check session time
    my $MaxSessionTime = $ConfigObject->Get('SessionMaxTime');

    if ( ( $TimeNow - $MaxSessionTime ) >= $Data{UserSessionStart} ) {

        $Self->{SessionIDErrorMessage} = Translatable('Session has timed out. Please log in again.');

        my $Timeout = int( ( $TimeNow - $Data{UserSessionStart} ) / ( 60 * 60 ) );

        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "SessionID ($Param{SessionID}) too old ($Timeout h)! Don't grant access!!!",
        );

        # delete session id if too old?
        if ( $ConfigObject->Get('SessionDeleteIfTimeToOld') ) {
            $Self->RemoveSessionID( SessionID => $Param{SessionID} );
        }

        return;
    }

    return 1;
}

sub SessionIDErrorMessage {
    my ( $Self, %Param ) = @_;

    return $Self->{SessionIDErrorMessage} || '';
}

sub GetSessionIDData {
    my ( $Self, %Param ) = @_;

    # check session id
    if ( !$Param{SessionID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got no SessionID!!'
        );
        return;
    }

    # check cache
    return %{ $Self->{Cache}->{ $Param{SessionID} } }
        if $Self->{Cache}->{ $Param{SessionID} };

    # read data
    my $Content = $Kernel::OM->Get('Kernel::System::Main')->FileRead(
        Directory       => $Self->{SessionSpool},
        Filename        => 'Data-' . $Param{SessionID},
        Type            => 'Local',
        Mode            => 'binmode',
        DisableWarnings => 1,
    );

    return if !$Content;
    return if ref $Content ne 'SCALAR';

    # read data structure back from file dump, use block eval for safety reasons
    my $Session = eval { Storable::thaw( ${$Content} ) };

    if ( !$Session || ref $Session ne 'HASH' ) {
        delete $Self->{Cache}->{ $Param{SessionID} };
        return;
    }

    # cache result
    $Self->{Cache}->{ $Param{SessionID} } = $Session;

    return %{$Session};
}

sub CreateSessionID {
    my ( $Self, %Param ) = @_;

    # get system time
    my $TimeNow = $Kernel::OM->Get('Kernel::System::Time')->SystemTime();

    # get remote address and the http user agent
    my $RemoteAddr      = $ENV{REMOTE_ADDR}     || 'none';
    my $RemoteUserAgent = $ENV{HTTP_USER_AGENT} || 'none';

    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

    # create session id
    my $SessionID = $Self->{SystemID} . $MainObject->GenerateRandomString(
        Length => 32,
    );

    # create challenge token
    my $ChallengeToken = $MainObject->GenerateRandomString(
        Length => 32,
    );

    my %Data;
    KEY:
    for my $Key ( sort keys %Param ) {

        next KEY if !$Key;

        $Data{$Key} = $Param{$Key};
    }

    $Data{UserSessionStart}    = $TimeNow;
    $Data{UserRemoteAddr}      = $RemoteAddr;
    $Data{UserRemoteUserAgent} = $RemoteUserAgent;
    $Data{UserChallengeToken}  = $ChallengeToken;

    # dump the data
    my $DataContent = Storable::nfreeze( \%Data );

    # write data file
    my $FileLocation = $MainObject->FileWrite(
        Directory       => $Self->{SessionSpool},
        Filename        => 'Data-' . $SessionID,
        Content         => \$DataContent,
        Type            => 'Local',
        Mode            => 'binmode',
        Permission      => '660',
        DisableWarnings => 1,
    );

    return if !$FileLocation;

    # set cache
    $Self->{Cache}->{$SessionID} = \%Data;

    # create needed state content
    my $UserType         = $Self->{Cache}->{$SessionID}->{UserType}         || '';
    my $UserLogin        = $Self->{Cache}->{$SessionID}->{UserLogin}        || '';
    my $UserSessionStart = $Self->{Cache}->{$SessionID}->{UserSessionStart} || '';
    my $UserLastRequest  = $Self->{Cache}->{$SessionID}->{UserLastRequest}  || '';

    my $StateContent = $UserType . '####' . $UserLogin . '####' . $UserSessionStart . '####' . $UserLastRequest;

    # write state file
    $MainObject->FileWrite(
        Directory       => $Self->{SessionSpool},
        Filename        => 'State-' . $SessionID,
        Content         => \$StateContent,
        Type            => 'Local',
        Mode            => 'binmode',
        Permission      => '660',
        DisableWarnings => 1,
    );

    return $SessionID;
}

sub RemoveSessionID {
    my ( $Self, %Param ) = @_;

    # check session id
    if ( !$Param{SessionID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got no SessionID!!'
        );
        return;
    }

    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

    # delete file
    my $DeleteData = $MainObject->FileDelete(
        Directory       => $Self->{SessionSpool},
        Filename        => 'Data-' . $Param{SessionID},
        Type            => 'Local',
        DisableWarnings => 1,
    );
    my $DeleteState = $MainObject->FileDelete(
        Directory       => $Self->{SessionSpool},
        Filename        => 'State-' . $Param{SessionID},
        Type            => 'Local',
        DisableWarnings => 1,
    );

    return if !$DeleteData;
    return if !$DeleteState;

    delete $Self->{Cache}->{ $Param{SessionID} };

    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => "Removed SessionID $Param{SessionID}."
    );

    return 1;
}

sub UpdateSessionID {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(SessionID Key)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # check cache
    if ( !$Self->{Cache}->{ $Param{SessionID} } ) {
        my %SessionData = $Self->GetSessionIDData( SessionID => $Param{SessionID} );

        $Self->{Cache}->{ $Param{SessionID} } = \%SessionData;
    }

    # update the value, set cache
    $Self->{Cache}->{ $Param{SessionID} }->{ $Param{Key} } = $Param{Value};

    return 1;
}

sub GetAllSessionIDs {
    my ( $Self, %Param ) = @_;

    # read data
    my @List = $Kernel::OM->Get('Kernel::System::Main')->DirectoryRead(
        Directory => $Self->{SessionSpool},
        Filter    => 'Data-' . $Self->{SystemID} . '*',
    );

    my @SessionIDs;
    for my $SessionID (@List) {
        $SessionID =~ s!^.*/!!;
        $SessionID =~ s{ Data- } {}xms;
        push @SessionIDs, $SessionID;
    }

    return @SessionIDs;
}

sub GetActiveSessions {
    my ( $Self, %Param ) = @_;

    my $TimeNow = $Kernel::OM->Get('Kernel::System::Time')->SystemTime();

    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

    my @List = $MainObject->DirectoryRead(
        Directory => $Self->{SessionSpool},
        Filter    => 'State-' . $Self->{SystemID} . '*',
    );

    my $ActiveSessionCount = 0;
    my %ActiveSessionPerUserCount;
    SESSIONID:
    for my $SessionID (@List) {

        $SessionID =~ s!^.*/!!;
        $SessionID =~ s{ State- } {}xms;

        next SESSIONID if !$SessionID;

        # read state data
        my $StateData = $MainObject->FileRead(
            Directory       => $Self->{SessionSpool},
            Filename        => 'State-' . $SessionID,
            Type            => 'Local',
            Mode            => 'binmode',
            DisableWarnings => 1,
        );

        next SESSIONID if !$StateData;
        next SESSIONID if ref $StateData ne 'SCALAR';

        my @SessionData = split '####', ${$StateData};

        # get needed data
        my $UserType        = $SessionData[0] || '';
        my $UserLogin       = $SessionData[1] || '';
        my $UserLastRequest = $SessionData[3] || $TimeNow;

        next SESSIONID if $UserType ne $Param{UserType};

        next SESSIONID if ( $UserLastRequest + $Self->{SessionActiveTime} ) < $TimeNow;

        $ActiveSessionCount++;

        $ActiveSessionPerUserCount{$UserLogin} || 0;
        $ActiveSessionPerUserCount{$UserLogin}++;
    }

    my %Result = (
        Total   => $ActiveSessionCount,
        PerUser => \%ActiveSessionPerUserCount,
    );

    return %Result;
}

sub GetExpiredSessionIDs {
    my ( $Self, %Param ) = @_;

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get config
    my $MaxSessionTime     = $ConfigObject->Get('SessionMaxTime');
    my $MaxSessionIdleTime = $ConfigObject->Get('SessionMaxIdleTime');

    # get current time
    my $TimeNow = $Kernel::OM->Get('Kernel::System::Time')->SystemTime();

    # get main object
    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

    # read data
    my @List = $MainObject->DirectoryRead(
        Directory => $Self->{SessionSpool},
        Filter    => 'State-' . $Self->{SystemID} . '*',
    );

    my @ExpiredSession;
    my @ExpiredIdle;
    SESSIONID:
    for my $SessionID (@List) {

        $SessionID =~ s!^.*/!!;
        $SessionID =~ s{ State- } {}xms;

        next SESSIONID if !$SessionID;

        # read state data
        my $StateData = $MainObject->FileRead(
            Directory       => $Self->{SessionSpool},
            Filename        => 'State-' . $SessionID,
            Type            => 'Local',
            Mode            => 'binmode',
            DisableWarnings => 1,
        );

        next SESSIONID if !$StateData;
        next SESSIONID if ref $StateData ne 'SCALAR';

        my @SessionData = split '####', ${$StateData};

        # get needed data
        my $UserSessionStart = $SessionData[2] || $TimeNow;
        my $UserLastRequest  = $SessionData[3] || $TimeNow;

        # time calculation
        my $ValidTime     = $UserSessionStart + $MaxSessionTime - $TimeNow;
        my $ValidIdleTime = $UserLastRequest + $MaxSessionIdleTime - $TimeNow;

        # delete invalid session time
        if ( $ValidTime <= 0 ) {
            push @ExpiredSession, $SessionID;
        }

        # delete invalid idle session time
        elsif ( $ValidIdleTime <= 0 ) {
            push @ExpiredIdle, $SessionID;
        }
    }

    return ( \@ExpiredSession, \@ExpiredIdle );
}

sub CleanUp {
    my ( $Self, %Param ) = @_;

    # delete fs files
    my @SessionIDs = $Self->GetAllSessionIDs();

    return 1 if !@SessionIDs;

    SESSIONID:
    for my $SessionID (@SessionIDs) {

        next SESSIONID if !$SessionID;

        $Self->RemoveSessionID( SessionID => $SessionID );
    }

    return 1;
}

sub DESTROY {
    my ( $Self, %Param ) = @_;

    return 1 if !$Self->{Cache};

    # get main object
    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

    SESSIONID:
    for my $SessionID ( sort keys %{ $Self->{Cache} } ) {

        next SESSIONID if !$SessionID;

        my %SessionData;
        KEY:
        for my $Key ( sort keys %{ $Self->{Cache}->{$SessionID} } ) {

            next KEY if !$Key;

            $SessionData{$Key} = $Self->{Cache}->{$SessionID}->{$Key};
        }

        # dump the data
        my $DataContent = Storable::nfreeze( \%SessionData );

        # write data file
        $MainObject->FileWrite(
            Directory       => $Self->{SessionSpool},
            Filename        => 'Data-' . $SessionID,
            Content         => \$DataContent,
            Type            => 'Local',
            Mode            => 'binmode',
            Permission      => '660',
            DisableWarnings => 1,
        );

        # create needed state content
        my $UserType         = $Self->{Cache}->{$SessionID}->{UserType}         || '';
        my $UserLogin        = $Self->{Cache}->{$SessionID}->{UserLogin}        || '';
        my $UserSessionStart = $Self->{Cache}->{$SessionID}->{UserSessionStart} || '';
        my $UserLastRequest  = $Self->{Cache}->{$SessionID}->{UserLastRequest}  || '';

        my $StateContent = $UserType . '####'
            . $UserLogin . '####'
            . $UserSessionStart . '####'
            . $UserLastRequest;

        # write state file
        $MainObject->FileWrite(
            Directory       => $Self->{SessionSpool},
            Filename        => 'State-' . $SessionID,
            Content         => \$StateContent,
            Type            => 'Local',
            Mode            => 'binmode',
            Permission      => '660',
            DisableWarnings => 1,
        );
    }

    # remove cached data
    delete $Self->{Cache};

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
