# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentTicketEscalationView;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get session object
    my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');

    # get needed objects
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $UserObject   = $Kernel::OM->Get('Kernel::System::User');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # get config
    my $Config       = $ConfigObject->Get("Ticket::Frontend::$Self->{Action}");

    if ( $ParamObject->GetParam( Param => 'SortBy' ) ) {
        $Self->{SortBy} = $ParamObject->GetParam( Param => 'SortBy' );
        $UserObject->SetPreferences(
            UserID => $Self->{UserID},
            Key    => 'UserEscalationViewSortBy',
            Value  => $Self->{SortBy},
        );
    }

    if ( $ParamObject->GetParam( Param => 'OrderBy' ) ) {
        $Self->{OrderBy} = $ParamObject->GetParam( Param => 'OrderBy' );
        $UserObject->SetPreferences(
            UserID => $Self->{UserID},
            Key    => 'UserEscalationViewOrderBy',
            Value  => $Self->{OrderBy},
        );
    }

    if ( !$Self->{SortBy} ) {
        $Self->{SortBy} = $Self->{UserPreferences}->{UserEscalationViewSortBy}
            || $Config->{'SortBy::Default'}
            || 'EscalationTime';
    }

    if ( !$Self->{OrderBy} ) {
        $Self->{OrderBy} = $Self->{UserPreferences}->{UserEscalationViewOrderBy}
            || $Config->{'Order::Default'}
            || 'Up';
    }

    # create URL to store last screen
    my $URL = "Action=AgentTicketEscalationView;"
        . ";View="          . $LayoutObject->LinkEncode( $ParamObject->GetParam(Param => 'View')        || '' )
        . ";Filter="        . $LayoutObject->LinkEncode( $ParamObject->GetParam(Param => 'Filter')      || '' )
        . ";SortBy="        . $LayoutObject->LinkEncode( $Self->{SortBy} )
        . ";OrderBy="       . $LayoutObject->LinkEncode( $Self->{OrderBy} )
        . ";StartHit="      . $LayoutObject->LinkEncode( $ParamObject->GetParam(Param => 'StartHit')    || '')
        . ";StartWindow="   . $LayoutObject->LinkEncode( $ParamObject->GetParam(Param => 'StartWindow') || 0);

    # store last queue screen
    $SessionObject->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastScreenOverview',
        Value     => $URL,
    );

    # store last screen
    $SessionObject->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastScreenView',
        Value     => $URL,
    );

    # get filters stored in the user preferences
    my %Preferences = $UserObject->GetPreferences(
        UserID => $Self->{UserID},
    );
    my $StoredFiltersKey = 'UserStoredFilterColumns-' . $Self->{Action};
    my $JSONObject       = $Kernel::OM->Get('Kernel::System::JSON');
    my $StoredFilters    = $JSONObject->Decode(
        Data => $Preferences{$StoredFiltersKey},
    );

    # delete stored filters if needed
    if ( $ParamObject->GetParam( Param => 'DeleteFilters' ) ) {
        $StoredFilters = {};
    }

    # get the column filters from the web request or user preferences
    my %ColumnFilter;
    my %GetColumnFilter;
    COLUMNNAME:
    for my $ColumnName (
        qw(Owner Responsible State Queue Priority Type Lock Service SLA CustomerID CustomerUserID)
    ) {
        # get column filter from web request
        my $FilterValue = $ParamObject->GetParam( Param => 'ColumnFilter' . $ColumnName )
            || '';

        # if filter is not present in the web request, try with the user preferences
        if ( $FilterValue eq '' ) {
            if ( $ColumnName eq 'CustomerID' ) {
                $FilterValue = $StoredFilters->{$ColumnName}->[0] || '';
            }
            elsif ( $ColumnName eq 'CustomerUserID' ) {
                $FilterValue = $StoredFilters->{CustomerUserLogin}->[0] || '';
            }
            else {
                $FilterValue = $StoredFilters->{ $ColumnName . 'IDs' }->[0] || '';
            }
        }
        next COLUMNNAME if $FilterValue eq '';
        next COLUMNNAME if $FilterValue eq 'DeleteFilter';

        if ( $ColumnName eq 'CustomerID' ) {
            push @{ $ColumnFilter{$ColumnName} }, $FilterValue;
            push @{ $ColumnFilter{ $ColumnName . 'Raw' } }, $FilterValue;
            $GetColumnFilter{$ColumnName} = $FilterValue;
        }
        elsif ( $ColumnName eq 'CustomerUserID' ) {
            push @{ $ColumnFilter{CustomerUserLogin} },    $FilterValue;
            push @{ $ColumnFilter{CustomerUserLoginRaw} }, $FilterValue;
            $GetColumnFilter{$ColumnName} = $FilterValue;
        }
        else {
            push @{ $ColumnFilter{ $ColumnName . 'IDs' } }, $FilterValue;
            $GetColumnFilter{$ColumnName} = $FilterValue;
        }
    }

    # get all dynamic fields
    $Self->{DynamicField} = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid      => 1,
        ObjectType => ['Ticket'],
    );

    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
        next DYNAMICFIELD if !$DynamicFieldConfig->{Name};

        # get filter from web request
        my $FilterValue = $ParamObject->GetParam(
            Param => 'ColumnFilterDynamicField_' . $DynamicFieldConfig->{Name}
        );

        # if no filter from web request, try from user preferences
        if ( !defined $FilterValue || $FilterValue eq '' ) {
            $FilterValue = $StoredFilters->{ 'DynamicField_' . $DynamicFieldConfig->{Name} }->{Equals};
        }

        next DYNAMICFIELD if !defined $FilterValue;
        next DYNAMICFIELD if $FilterValue eq '';
        next DYNAMICFIELD if $FilterValue eq 'DeleteFilter';

        $ColumnFilter{ 'DynamicField_' . $DynamicFieldConfig->{Name} } = {
            Equals => $FilterValue,
        };
        $GetColumnFilter{ 'DynamicField_' . $DynamicFieldConfig->{Name} } = $FilterValue;
    }

    # starting with page ...
    my $Refresh = '';
    if ( $Self->{UserRefreshTime} ) {
        $Refresh = 60 * $Self->{UserRefreshTime};
    }

    my $Output;
    if ( $Self->{Subaction} ne 'AJAXFilterUpdate' ) {
        $Output = $LayoutObject->Header(
            Refresh => $Refresh,
        );
        $Output .= $LayoutObject->NavigationBar();
    }

    # get time object
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $TimeObject->SystemTime2Date(
        SystemTime => $TimeObject->SystemTime() + 60 * 60 * 24 * 7,
    );
    my $TimeStampNextWeek = "$Year-$Month-$Day 23:59:59";

    ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $TimeObject->SystemTime2Date(
        SystemTime => $TimeObject->SystemTime() + 60 * 60 * 24,
    );
    my $TimeStampTomorrow = "$Year-$Month-$Day 23:59:59";

    ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $TimeObject->SystemTime2Date(
        SystemTime => $TimeObject->SystemTime(),
    );
    my $TimeStampToday = "$Year-$Month-$Day 23:59:59";

    # get params
    my $SortBy = $ParamObject->GetParam( Param => 'SortBy' )
        || $Config->{'SortBy::Default'}
        || 'EscalationTime';
    my $OrderBy = $ParamObject->GetParam( Param => 'OrderBy' )
        || $Config->{'Order::Default'}
        || 'Up';

    my %Filters = (
        Today => {
            Name   => Translatable('Today'),
            Prio   => 1000,
            Search => {
                TicketEscalationTimeOlderDate => $TimeStampToday,
                OrderBy                       => $OrderBy,
                SortBy                        => $SortBy,
                UserID                        => $Self->{UserID},
                Permission                    => $Config->{'TicketPermission'},
            },
        },
        Tomorrow => {
            Name   => Translatable('Tomorrow'),
            Prio   => 2000,
            Search => {
                TicketEscalationTimeOlderDate => $TimeStampTomorrow,
                OrderBy                       => $OrderBy,
                SortBy                        => $SortBy,
                UserID                        => $Self->{UserID},
                Permission                    => $Config->{'TicketPermission'},
            },
        },
        NextWeek => {
            Name   => Translatable('Next week'),
            Prio   => 3000,
            Search => {
                TicketEscalationTimeOlderDate => $TimeStampNextWeek,
                OrderBy                       => $OrderBy,
                SortBy                        => $SortBy,
                UserID                        => $Self->{UserID},
                Permission                    => $Config->{'TicketPermission'},
            },
        },
    );

    my $Filter = $ParamObject->GetParam( Param => 'Filter' ) || 'Today';

    # check if filter is valid
    if ( !$Filters{$Filter} ) {
        $LayoutObject->FatalError(
            Message => $LayoutObject->{LanguageObject}->Translate( 'Invalid Filter: %s!', $Filter ),
        );
    }

    # do shown tickets lookup
    my $Limit = $ParamObject->GetParam( Param => 'Limit' ) || 2000;
    my $OriginalLimit = 10_000;

    my $ElementChanged = $ParamObject->GetParam( Param => 'ElementChanged' ) || '';
    my $HeaderColumn = $ElementChanged;
    $HeaderColumn =~ s{\A ColumnFilter }{}msxg;
    my @OriginalViewableTickets;
    my @ViewableTickets;
    my $ViewableTicketCount = 0;

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # get ticket values
    if (
        !IsStringWithData($HeaderColumn)
        || (
            IsStringWithData($HeaderColumn)
            && (
                $ConfigObject->Get('OnlyValuesOnTicket') ||
                $HeaderColumn eq 'CustomerID' ||
                $HeaderColumn eq 'CustomerUserID'
            )
        )
    ) {

        @OriginalViewableTickets = $TicketObject->TicketSearch(
            %{ $Filters{$Filter}->{Search} },
            Limit  => $OriginalLimit,
            Result => 'ARRAY',
        );

        @ViewableTickets = $TicketObject->TicketSearch(
            %{ $Filters{$Filter}->{Search} },
            %ColumnFilter,
            Result => 'ARRAY',
            Limit  => $Limit,
        );
    }

    my $View = $ParamObject->GetParam( Param => 'View' ) || '';

    if ( $Self->{Subaction} eq 'AJAXFilterUpdate' ) {

        my $FilterContent = $LayoutObject->TicketListShow(
            FilterContentOnly   => 1,
            HeaderColumn        => $HeaderColumn,
            ElementChanged      => $ElementChanged,
            OriginalTicketIDs   => \@OriginalViewableTickets,
            Action              => 'AgentTicketStatusView',
            Env                 => $Self,
            View                => $View,
            EnableColumnFilters => 1,
        );

        if ( !$FilterContent ) {
            $LayoutObject->FatalError(
                Message => $LayoutObject->{LanguageObject}
                    ->Translate( 'Can\'t get filter content data of %s!', $HeaderColumn ),
            );
        }

        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $FilterContent,
            Type        => 'inline',
            NoCache     => 1,
        );
    }
    else {

        # store column filters
        my $NewStoredFilters = \%ColumnFilter;

        $UserObject->SetPreferences(
            UserID => $Self->{UserID},
            Key    => $StoredFiltersKey,
            Value  => $JSONObject->Encode( Data => $NewStoredFilters ),
        );
    }

    my %NavBarFilter;
    for my $FilterColumn ( sort keys %Filters ) {
        my @NavViewableTickets = $TicketObject->TicketSearch(
            %{ $Filters{$FilterColumn}->{Search} },
            %ColumnFilter,
            Result => 'ARRAY',
            Limit  => $Limit,
        );
        $NavBarFilter{ $Filters{$FilterColumn}->{Prio} } = {
            Count  => scalar @NavViewableTickets,
            Filter => $FilterColumn,
            %{ $Filters{$FilterColumn} },
        };
    }

    my $ColumnFilterLink = '';
    COLUMNNAME:
    for my $ColumnName ( sort keys %GetColumnFilter ) {
        next COLUMNNAME if !$ColumnName;
        next COLUMNNAME if !$GetColumnFilter{$ColumnName};
        $ColumnFilterLink
            .= ';' . $LayoutObject->Ascii2Html( Text => 'ColumnFilter' . $ColumnName )
            . '=' . $LayoutObject->Ascii2Html( Text => $GetColumnFilter{$ColumnName} )
    }

    # show ticket's
    my $LinkPage = 'Filter='
        . $LayoutObject->Ascii2Html( Text => $Filter )
        . ';View=' . $LayoutObject->Ascii2Html( Text => $View )
        . ';SortBy=' . $LayoutObject->Ascii2Html( Text => $SortBy )
        . ';OrderBy=' . $LayoutObject->Ascii2Html( Text => $OrderBy )
        . $ColumnFilterLink
        . ';';
    my $LinkSort = 'Filter='
        . $LayoutObject->Ascii2Html( Text => $Filter )
        . ';View=' . $LayoutObject->Ascii2Html( Text => $View )
        . $ColumnFilterLink
        . ';';
    my $LinkFilter = 'SortBy=' . $LayoutObject->Ascii2Html( Text => $SortBy )
        . ';OrderBy=' . $LayoutObject->Ascii2Html( Text => $OrderBy )
        . ';View=' . $LayoutObject->Ascii2Html( Text => $View )
        . ';';

    my $LastColumnFilter = $ParamObject->GetParam( Param => 'LastColumnFilter' ) || '';

    if ( !$LastColumnFilter && $ColumnFilterLink ) {

        # is planned to have a link to go back here
        $LastColumnFilter = 1;
    }

    $Output .= $LayoutObject->TicketListShow(
        TicketIDs         => \@ViewableTickets,
        OriginalTicketIDs => \@OriginalViewableTickets,
        GetColumnFilter   => \%GetColumnFilter,
        LastColumnFilter  => $LastColumnFilter,
        Action            => 'AgentTicketEscalationView',
        RequestedURL      => $Self->{RequestedURL},

        Total => scalar @ViewableTickets,

        View => $View,

        Filter     => $Filter,
        Filters    => \%NavBarFilter,

        TitleName  => Translatable('Ticket Escalation View'),
        TitleValue => $Filters{$Filter}->{Name},
        Bulk       => 1,

        Env        => $Self,
        LinkPage   => $LinkPage,
        LinkSort   => $LinkSort,
        LinkFilter => $LinkFilter,

        OrderBy             => $OrderBy,
        SortBy              => $SortBy,
        EnableColumnFilters => 1,
        ColumnFilterForm    => {
            Filter => $Filter || '',
        },

        Escalation => 1,

        # do not print the result earlier, but return complete content
        Output => 1,
    );

    $Output .= $LayoutObject->Footer();
    return $Output;
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
