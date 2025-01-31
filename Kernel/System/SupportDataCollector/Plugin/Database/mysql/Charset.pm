# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::SupportDataCollector::Plugin::Database::mysql::Charset;

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

    if ( $DBObject->GetDatabaseFunction('Type') ne 'mysql' ) {
        return $Self->GetResults();
    }

    $DBObject->Prepare( SQL => "show variables like 'character_set_client'" );
    while ( my @Row = $DBObject->FetchrowArray() ) {
        if ( $Row[1] =~ /utf8/i ) {
            $Self->AddResultOk(
                Identifier => 'ClientEncoding',
                Label      => Translatable('Client Connection Charset'),
                Value      => $Row[1],
            );
        }
        else {
            $Self->AddResultProblem(
                Identifier => 'ClientEncoding',
                Label      => Translatable('Client Connection Charset'),
                Value      => $Row[1],
                Message    => Translatable('Setting character_set_client needs to be utf8.'),
            );
        }
    }

    $DBObject->Prepare( SQL => "show variables like 'character_set_database'" );
    while ( my @Row = $DBObject->FetchrowArray() ) {
        if ( $Row[1] =~ /utf8/i ) {
            $Self->AddResultOk(
                Identifier => 'ServerEncoding',
                Label      => Translatable('Server Database Charset'),
                Value      => $Row[1],
            );
        }
        else {
            $Self->AddResultProblem(
                Identifier => 'ServerEncoding',
                Label      => Translatable('Server Database Charset'),
                Value      => $Row[1],
                Message    => Translatable('Setting character_set_database needs to be UNICODE or UTF8.'),
            );
        }
    }

    my @TablesWithInvalidCharset;

    # Views have engine == null, ignore those.
    $DBObject->Prepare( SQL => 'show table status where engine is not null' );
    while ( my @Row = $DBObject->FetchrowArray() ) {
        if ( $Row[14] !~ /^utf8/i ) {
            push @TablesWithInvalidCharset, $Row[0];
        }
    }
    if (@TablesWithInvalidCharset) {
        $Self->AddResultProblem(
            Identifier => 'TableEncoding',
            Label      => Translatable('Table Charset'),
            Value      => join( ', ', @TablesWithInvalidCharset ),
            Message    => Translatable('There were tables found which do not have utf8 as charset.'),
        );
    }
    else {
        $Self->AddResultOk(
            Identifier => 'TableEncoding',
            Label      => Translatable('Table Charset'),
            Value      => '',
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
