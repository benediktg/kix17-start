#!/usr/bin/perl
# --
# Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin) . '/../../';
use lib dirname($RealBin) . '/../../Kernel/cpan-lib';

use Getopt::Std;
use File::Path qw(mkpath);

use Kernel::System::ObjectManager;
use Kernel::System::VariableCheck qw(:all);

# create object manager
local $Kernel::OM = Kernel::System::ObjectManager->new(
    'Kernel::System::Log' => {
        LogPrefix => 'db-update-17.11.0.pl',
    },
);

use vars qw(%INC);

# save configuration
_SaveConfig();

exit 0;

sub _SaveConfig {
    my ( $Self, %Param ) = @_;

    # get config values to save from config object
    my %ConfigBackup = ();
    for my $Key ( qw( SystemID LostPassword CustomerPanelLostPassword CustomerPanelCreateAccount Ticket::ACL-PossiblePropertiesSubsumption ) ) {
        $ConfigBackup{ $Key } = $Kernel::OM->Get('Kernel::Config')->Get( $Key );
    }

    # update SysConfig
    my $Result;
    for my $Key ( keys( %ConfigBackup ) ) {
        $Result = $Kernel::OM->Get('Kernel::System::SysConfig')->ConfigItemUpdate(
            Key   => $Key,
            Value => $ConfigBackup{ $Key },
            Valid => 1,
        );
    }

    return $Result;
}

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut
