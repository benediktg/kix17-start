# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::Number::Date;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::Time',
);

sub TicketCreateNumber {
    my ( $Self, $JumpCounter ) = @_;

    if ( !$JumpCounter ) {
        $JumpCounter = 0;
    }

    # get needed objects
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $MainObject   = $Kernel::OM->Get('Kernel::System::Main');
    my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');

    # get needed config options
    my $CounterLog = $ConfigObject->Get('Ticket::CounterLog');
    my $SystemID   = $ConfigObject->Get('SystemID');

    # get current time
    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $TimeObject->SystemTime2Date(
        SystemTime => $TimeObject->SystemTime(),
    );

    # read count
    my $Count = 0;
    if ( -f $CounterLog ) {

        my $ContentSCALARRef = $MainObject->FileRead(
            Location => $CounterLog,
        );

        if ( $ContentSCALARRef && ${$ContentSCALARRef} ) {

            ($Count) = split( /;/, ${$ContentSCALARRef} );

            # just debug
            if ( $Self->{Debug} > 0 ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'debug',
                    Message  => "Read counter from $CounterLog: $Count",
                );
            }
        }
    }

    # count auto increment ($Count++)
    $Count++;
    $Count = $Count + $JumpCounter;

    # write new count
    my $Write = $MainObject->FileWrite(
        Location => $CounterLog,
        Content  => \$Count,
    );

    if ($Write) {

        if ( $Self->{Debug} > 0 ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'debug',
                Message  => "Write counter: $Count",
            );
        }
    }

    if ( $ConfigObject->Get('Ticket::NumberGenerator::Date::UseFormattedCounter') ) {
        my $MinSize = $ConfigObject->Get('Ticket::NumberGenerator::MinCounterSize')
            || 5;
        $Count = sprintf "%.*u", $MinSize, $Count;
    }

    # create new ticket number
    my $Tn = $Year . $Month . $Day . $SystemID . $Count;

    # Check ticket number. If exists generate new one!
    if ( $Self->TicketCheckNumber( Tn => $Tn ) ) {

        $Self->{LoopProtectionCounter}++;

        if ( $Self->{LoopProtectionCounter} >= 16000 ) {

            # loop protection
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "CounterLoopProtection is now $Self->{LoopProtectionCounter}!"
                    . " Stopped TicketCreateNumber()!",
            );
            return;
        }

        # create new ticket number again
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "Tn ($Tn) exists! Creating a new one.",
        );

        $Tn = $Self->TicketCreateNumber( $Self->{LoopProtectionCounter} );
    }

    return $Tn;
}

sub GetTNByString {
    my ( $Self, $String ) = @_;

    if ( !$String ) {
        return;
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get needed config options
    my $CheckSystemID = $ConfigObject->Get('Ticket::NumberGenerator::CheckSystemID');
    my $SystemID      = '';

    if ($CheckSystemID) {
        $SystemID = $ConfigObject->Get('SystemID');
    }

    my $TicketHook        = $ConfigObject->Get('Ticket::Hook');
    my $TicketHookDivider = $ConfigObject->Get('Ticket::HookDivider');

    # check current setting
    if ( $String =~ /\Q$TicketHook$TicketHookDivider\E(\d{8}$SystemID\d{1,40})/i ) {
        return $1;
    }

    # check default setting
    if ( $String =~ /\Q$TicketHook\E:\s{0,2}(\d{8}$SystemID\d{1,40})/i ) {
        return $1;
    }

    return;
}

sub GetTNArrayByString {
    my ( $Self, $String ) = @_;

    if ( !$String ) {
        return;
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get needed config options
    my $CheckSystemID = $ConfigObject->Get('Ticket::NumberGenerator::CheckSystemID');
    my $SystemID      = '';

    if ($CheckSystemID) {
        $SystemID = $ConfigObject->Get('SystemID');
    }

    my $TicketHook        = $ConfigObject->Get('Ticket::Hook');
    my $TicketHookDivider = $ConfigObject->Get('Ticket::HookDivider');

    # check current setting
    if ( $String =~ /\Q$TicketHook$TicketHookDivider\E(\d{8}$SystemID\d{1,40})/i ) {
        my @Result = ( $String =~ /\Q$TicketHook$TicketHookDivider\E(\d{8}$SystemID\d{1,40})/ig );
        return @Result;
    }

    # check default setting
    if ( $String =~ /\Q$TicketHook\E:\s{0,2}(\d{8}$SystemID\d{1,40})/i ) {
        my @Result = ( $String =~ /\Q$TicketHook\E:\s{0,2}(\d{8}$SystemID\d{1,40})/ig );
        return @Result;
    }

    return;
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
