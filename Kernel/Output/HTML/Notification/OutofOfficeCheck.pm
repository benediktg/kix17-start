# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::Notification::OutofOfficeCheck;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::User',
    'Kernel::System::Time',
    'Kernel::Output::HTML::Layout',
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

    my %UserData = $Kernel::OM->Get('Kernel::System::User')->GetUserData( UserID => $Self->{UserID} );
    return '' if ( !$UserData{OutOfOffice} );

    # get time object
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    my $Time = $TimeObject->SystemTime();

    my $Start
        = "$UserData{OutOfOfficeStartYear}-$UserData{OutOfOfficeStartMonth}-$UserData{OutOfOfficeStartDay} 00:00:00";

    my $TimeStart = $TimeObject->TimeStamp2SystemTime(
        String => $Start,
    );
    my $End     = "$UserData{OutOfOfficeEndYear}-$UserData{OutOfOfficeEndMonth}-$UserData{OutOfOfficeEndDay} 23:59:59";
    my $TimeEnd = $TimeObject->TimeStamp2SystemTime(
        String => $End,
    );
    if ( $TimeStart < $Time && $TimeEnd > $Time ) {

        # get layout object
        my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

        return $LayoutObject->Notify(
            Priority => 'Notice',
            Link     => $LayoutObject->{Baselink} . 'Action=AgentPreferences',
            Data =>
                $LayoutObject->{LanguageObject}
                ->Translate("You have Out of Office enabled, would you like to disable it?"),
        );
    }
    else {
        return '';
    }
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
