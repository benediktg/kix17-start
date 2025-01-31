# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::SupportDataCollector::Plugin::Database::TablePresence;

use strict;
use warnings;

use base qw(Kernel::System::SupportDataCollector::PluginBase);

use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::Main',
    'Kernel::System::XML',
);

sub GetDisplayPath {
    return Translatable('Database');
}

sub Run {
    my $Self = shift;

    # table check
    my $File = $Kernel::OM->Get('Kernel::Config')->Get('Home') . '/scripts/database/kix-schema.xml';
    if ( !-f $File ) {
        $Self->AddResultProblem(
            Label   => Translatable('Table Presence'),
            Value   => '',
            Message => Translatable("Internal Error: Could not open file."),
        );
    }

    my $ContentRef = $Kernel::OM->Get('Kernel::System::Main')->FileRead(
        Location => $File,
        Mode     => 'utf8',
    );
    if ( !ref $ContentRef && !${$ContentRef} ) {
        $Self->AddResultProblem(
            Label   => Translatable('Table Check'),
            Value   => '',
            Message => Translatable("Internal Error: Could not read file."),
        );
    }

    my @XMLHash = $Kernel::OM->Get('Kernel::System::XML')->XMLParse2XMLHash( String => ${$ContentRef} );

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my @MissingTables;
    TABLE:
    for my $Table ( @{ $XMLHash[1]->{database}->[1]->{Table} } ) {
        next TABLE if !$Table;

        my $TableExists = $DBObject->Prepare(
            SQL   => "SELECT 1 FROM $Table->{Name}",
            Limit => 1,
        );

        if ($TableExists) {
            while ( my @Row = $DBObject->FetchrowArray() ) {

                # noop
            }
        }
        else {
            push( @MissingTables, $Table->{Name} );
        }
    }
    if ( !@MissingTables ) {
        $Self->AddResultOk(
            Label => Translatable('Table Presence'),
            Value => '',
        );
    }
    else {
        $Self->AddResultProblem(
            Label   => Translatable('Table Presence'),
            Value   => join( ', ', @MissingTables ),
            Message => Translatable("Tables found which are not present in the database."),
        );
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
