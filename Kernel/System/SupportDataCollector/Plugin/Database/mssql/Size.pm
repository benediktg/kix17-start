# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::SupportDataCollector::Plugin::Database::mssql::Size;

use strict;
use warnings;

use base qw(Kernel::System::SupportDataCollector::PluginBase);

use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
    'Kernel::System::DB',
);

sub GetDisplayPath {
    return Translatable('Database');
}

sub Run {
    my $Self = shift;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    if ( $DBObject->GetDatabaseFunction('Type') ne 'mssql' ) {
        return $Self->GetResults();
    }

    $DBObject->Prepare(
        SQL   => 'exec sp_spaceused',
        Limit => 1,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {

        # $Row[0] database_name
        # $Row[1] database_size
        # $Row[2] unallocated space
        if ( $Row[1] ) {
            $Self->AddResultInformation(
                Label => Translatable('Database Size'),
                Value => $Row[1],
            );
        }
        else {
            $Self->AddResultProblem(
                Label   => Translatable('Database Size'),
                Value   => $Row[1],
                Message => Translatable('Could not determine database size.')
            );
        }
    }

    return $Self->GetResults();
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
