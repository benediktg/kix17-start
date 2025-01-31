# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AdminGenericInterfaceDebugger;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $WebserviceID = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'WebserviceID' );

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    if ( !$WebserviceID ) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('Need WebserviceID!'),
        );
    }

    my $WebserviceData = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice')->WebserviceGet(
        ID => $WebserviceID,
    );

    if ( !IsHashRefWithData($WebserviceData) ) {
        return $LayoutObject->ErrorScreen(
            Message =>
                $LayoutObject->{LanguageObject}->Translate( 'Could not get data for WebserviceID %s', $WebserviceID ),
        );
    }

    if ( $Self->{Subaction} eq 'GetRequestList' ) {
        return $Self->_GetRequestList(
            %Param,
            WebserviceID   => $WebserviceID,
            WebserviceData => $WebserviceData,
        );
    }
    elsif ( $Self->{Subaction} eq 'GetCommunicationDetails' ) {
        return $Self->_GetCommunicationDetails(
            %Param,
            WebserviceID   => $WebserviceID,
            WebserviceData => $WebserviceData,
        );
    }
    elsif ( $Self->{Subaction} eq 'ClearDebugLog' ) {
        return $Self->_ClearDebugLog(
            %Param,
            WebserviceID   => $WebserviceID,
            WebserviceData => $WebserviceData,
        );
    }

    # default: show start screen
    return $Self->_ShowScreen(
        %Param,
        WebserviceID   => $WebserviceID,
        WebserviceData => $WebserviceData,
    );
}

sub _ShowScreen {
    my ( $Self, %Param ) = @_;

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');

    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();

    my $FilterLimitStrg = $LayoutObject->BuildSelection(
        Data => [
            '10',
            '100',
            '1000',
        ],
        Name          => 'FilterLimit',
        PossibleNone  => 1,
        SelectedValue => '100',
        Translate     => 0,
        Class         => 'Modernize',
    );

    my $FilterTypeStrg = $LayoutObject->BuildSelection(
        Data => [
            'Provider',
            'Requester',
        ],
        Name         => 'FilterType',
        PossibleNone => 1,
        Translate    => 0,
        Class        => 'Modernize',
    );

    # get current data of current time
    my ($Sec, $Min, $Hour, $Day, $Month, $Year, $WeekDay) = $TimeObject->SystemTime2Date(
        SystemTime => $TimeObject->SystemTime(),
    );

    my $FilterFromStrg = $LayoutObject->BuildDateSelection(
        Prefix           => 'FilterFrom',
        FilterFromYear   => $Year,
        FilterFromMonth  => $Month,
        FilterFromDay    => $Day,
        FilterFromHour   => 0,
        FilterFromMinute => 0,
        FilterFromSecond => 0,
    );

    my $FilterToStrg = $LayoutObject->BuildDateSelection(
        Prefix         => 'FilterTo',
        FilterToYear   => $Year,
        FilterToMonth  => $Month,
        FilterToDay    => $Day,
        FilterToHour   => 23,
        FilterToMinute => 59,
        FilterToSecond => 59,
    );

    $Output .= $LayoutObject->Output(
        TemplateFile => 'AdminGenericInterfaceDebugger',
        Data         => {
            %Param,
            WebserviceName  => $Param{WebserviceData}->{Name},
            FilterLimitStrg => $FilterLimitStrg,
            FilterTypeStrg  => $FilterTypeStrg,
            FilterFromStrg  => $FilterFromStrg,
            FilterToStrg    => $FilterToStrg,
        },
    );

    $Output .= $LayoutObject->Footer();
    return $Output;
}

sub _GetRequestList {
    my ( $Self, %Param ) = @_;

    my %LogSearchParam = (
        WebserviceID => $Param{WebserviceID},
    );

    # get param object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    my $FilterType = $ParamObject->GetParam( Param => 'FilterType' );
    $LogSearchParam{CommunicationType} = $FilterType if ($FilterType);

    my $FilterRemoteIP = $ParamObject->GetParam( Param => 'FilterRemoteIP' );

    if ( $FilterRemoteIP && IsIPv4Address($FilterRemoteIP) ) {
        $LogSearchParam{RemoteIP} = $FilterRemoteIP;
    }

    $LogSearchParam{CreatedAtOrAfter}  = $ParamObject->GetParam( Param => 'FilterFrom' );
    $LogSearchParam{CreatedAtOrBefore} = $ParamObject->GetParam( Param => 'FilterTo' );
    $LogSearchParam{Limit}             = $ParamObject->GetParam( Param => 'FilterLimit' ) || undef;

    my $LogData = $Kernel::OM->Get('Kernel::System::GenericInterface::DebugLog')->LogSearch(%LogSearchParam);

    # fail gracefully
    $LogData ||= [];

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # build JSON output
    my $JSON = $LayoutObject->JSONEncode(
        Data => {
            LogData => $LogData,
        },
    );

    # send JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
        Content     => $JSON,
        Type        => 'inline',
        NoCache     => 1,
    );
}

sub _GetCommunicationDetails {
    my ( $Self, %Param ) = @_;

    my $CommunicationID = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'CommunicationID' );

    if ( !$CommunicationID ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got no CommunicationID',
        );

        return;    # return empty response
    }

    my $LogData = $Kernel::OM->Get('Kernel::System::GenericInterface::DebugLog')->LogGetWithData(
        WebserviceID    => $Param{WebserviceID},
        CommunicationID => $CommunicationID,
    );

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # build JSON output
    my $JSON = $LayoutObject->JSONEncode(
        Data => {
            LogData => $LogData,
        },
    );

    # send JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
        Content     => $JSON,
        Type        => 'inline',
        NoCache     => 1,
    );
}

sub _ClearDebugLog {
    my ( $Self, %Param ) = @_;

    my $Success = $Kernel::OM->Get('Kernel::System::GenericInterface::DebugLog')->LogDelete(
        WebserviceID => $Param{WebserviceID},
    );

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # build JSON output
    my $JSON = $LayoutObject->JSONEncode(
        Data => {
            Success => $Success,
        },
    );

    # send JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
        Content     => $JSON,
        Type        => 'inline',
        NoCache     => 1,
    );
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
