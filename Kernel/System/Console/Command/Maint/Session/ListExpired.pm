# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Console::Command::Maint::Session::ListExpired;

use strict;
use warnings;

use base qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::AuthSession',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('List expired sessions.');

    return;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my @Expired = $Kernel::OM->Get('Kernel::System::AuthSession')->GetExpiredSessionIDs();

    $Self->Print("<yellow>Listing expired sessions...</yellow>\n");

    for my $SessionID ( @{ $Expired[0] } ) {
        $Self->Print("  $SessionID\n");
    }

    $Self->Print("<yellow>Listing idle sessions...</yellow>\n");

    for my $SessionID ( @{ $Expired[1] } ) {
        $Self->Print("  $SessionID\n");
    }

    $Self->Print("<green>Done.</green>\n");

    return $Self->ExitCodeOk();
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
