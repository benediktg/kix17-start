# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::Dashboard::UserOutOfOffice;

use strict;
use warnings;

use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get needed parameters
    for my $Needed (qw(Config Name UserID)) {
        die "Got no $Needed!" if ( !$Self->{$Needed} );
    }

    # get param object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    # get current start-hit and preferences
    my $Name = $ParamObject->GetParam( Param => 'Name' ) || '';
    my $PreferencesKey = 'UserDashboardUserOutOfOffice' . $Self->{Name};

    $Self->{PrefKey} = 'UserDashboardPref' . $Self->{Name} . '-Shown';

    $Self->{PageShown} = $Kernel::OM->Get('Kernel::Output::HTML::Layout')->{ $Self->{PrefKey} }
        || $Self->{Config}->{Limit} || 10;

    $Self->{StartHit} = int( $ParamObject->GetParam( Param => 'StartHit' ) || 1 );

    $Self->{CacheKey} = $Self->{Name};

    return $Self;
}

sub Preferences {
    my ( $Self, %Param ) = @_;

    my @Params = (
        {
            Desc  => Translatable('Shown'),
            Name  => $Self->{PrefKey},
            Block => 'Option',
            Data  => {
                5  => ' 5',
                10 => '10',
                15 => '15',
                20 => '20',
                25 => '25',
                30 => '30',
                35 => '35',
                40 => '40',
                45 => '45',
                50 => '50',
            },
            SelectedID  => $Self->{PageShown},
            Translation => 0,
        },
    );

    return @Params;
}

sub Config {
    my ( $Self, %Param ) = @_;

    return (
        %{ $Self->{Config} },

        # remember, do not allow to use page cache
        # (it's not working because of internal filter)
        CacheKey => undef,
        CacheTTL => undef,
    );
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get config settings
    my $SortBy = $Self->{Config}->{SortBy} || 'UserFullname';

    # get cache object
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

    # check cache
    my $OutOfOffice = $CacheObject->Get(
        Type => 'Dashboard',
        Key  => $Self->{CacheKey},
    );

    # get session info
    my $CacheUsed = 1;
    if ( !$OutOfOffice ) {

        $CacheUsed   = 0;
        $OutOfOffice = {
            User      => {},
            UserCount => 0,
            UserData  => {},
        };

        # get user object
        my $UserObject = $Kernel::OM->Get('Kernel::System::User');

        my %UserList = $UserObject->SearchPreferences(
            Key   => 'OutOfOffice',
            Value => 1,
        );

        USERID:
        for my $UserID ( sort keys %UserList ) {

            next USERID if !$UserID;

            # get user data
            my %Data = $UserObject->GetUserData(
                UserID        => $UserID,
                NoOutOfOffice => 1,
                Valid         => 1,
            );

            next USERID if !%Data;

            # get time object
            my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

            my $Time  = $TimeObject->SystemTime();
            my $Start = sprintf(
                "%04d-%02d-%02d 00:00:00",
                $Data{OutOfOfficeStartYear}, $Data{OutOfOfficeStartMonth},
                $Data{OutOfOfficeStartDay}
            );
            my $TimeStart = $TimeObject->TimeStamp2SystemTime(
                String => $Start,
            );
            my $End = sprintf(
                "%04d-%02d-%02d 23:59:59",
                $Data{OutOfOfficeEndYear}, $Data{OutOfOfficeEndMonth}, $Data{OutOfOfficeEndDay}
            );
            my $TimeEnd = $TimeObject->TimeStamp2SystemTime(
                String => $End,
            );

            next USERID if $TimeStart > $Time || $TimeEnd < $Time;

            $Data{OutOfOfficeUntil} = $End;

            # remember user and data
            $OutOfOffice->{User}->{ $Data{UserID} } = $Data{$SortBy};
            $OutOfOffice->{UserCount}++;
            $OutOfOffice->{UserData}->{ $Data{UserID} } = \%Data;
        }
    }

    # do not show widget if there are no users out-of-office
    return if !$OutOfOffice->{UserCount};

    # set cache
    if ( !$CacheUsed && $Self->{Config}->{CacheTTLLocal} ) {
        $CacheObject->Set(
            Type  => 'Dashboard',
            Key   => $Self->{CacheKey},
            Value => $OutOfOffice,
            TTL   => $Self->{Config}->{CacheTTLLocal} * 60,
        );
    }

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # add page nav bar if needed
    my $Total = $OutOfOffice->{UserCount} || 0;
    if ( $OutOfOffice->{UserCount} > $Self->{PageShown} ) {

        my $LinkPage = 'Subaction=Element;Name=' . $Self->{Name} . ';';
        my %PageNav  = $LayoutObject->PageNavBar(
            StartHit       => $Self->{StartHit},
            PageShown      => $Self->{PageShown},
            AllHits        => $Total || 1,
            Action         => 'Action=' . $LayoutObject->{Action},
            Link           => $LinkPage,
            WindowSize     => 5,
            AJAXReplace    => 'Dashboard' . $Self->{Name},
            IDPrefix       => 'Dashboard' . $Self->{Name},
            KeepScriptTags => $Param{AJAX},
        );

        $LayoutObject->Block(
            Name => 'ContentSmallTicketGenericNavBar',
            Data => {
                %{ $Self->{Config} },
                Name => $Self->{Name},
                %PageNav,
            },
        );
    }

    # show data
    my %OutOfOfficeUser = %{ $OutOfOffice->{User} };
    my %OutOfOfficeData = %{ $OutOfOffice->{UserData} };
    my $Count           = 0;
    my $Limit           = $LayoutObject->{ $Self->{PrefKey} } || $Self->{Config}->{Limit};

    USERID:
    for my $UserID ( sort { $OutOfOfficeUser{$a} cmp $OutOfOfficeUser{$b} } keys %OutOfOfficeUser ) {

        $Count++;

        next USERID if !$UserID;
        next USERID if $Count < $Self->{StartHit};
        last USERID if $Count >= ( $Self->{StartHit} + $Self->{PageShown} );

        $LayoutObject->Block(
            Name => 'ContentSmallUserOutOfOfficeRow',
            Data => $OutOfOfficeData{$UserID},
        );
    }

    my $Content = $LayoutObject->Output(
        TemplateFile => 'AgentDashboardUserOutOfOffice',
        Data         => {
            %{ $Self->{Config} },
            Name => $Self->{Name},
        },
        KeepScriptTags => $Param{AJAX},
    );

    return $Content;
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
