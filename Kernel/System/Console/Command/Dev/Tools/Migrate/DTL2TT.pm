# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Console::Command::Dev::Tools::Migrate::DTL2TT;

use strict;
use warnings;

use base qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::Main',
    'Kernel::Output::Template::Provider',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Migrate DTL files to Template::Toolkit.');
    $Self->AddArgument(
        Name        => 'directory',
        Description => "Toplevel KIX or module directory where DTL files need to be converted.",
        Required    => 1,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ProviderObject = $Kernel::OM->Get('Kernel::Output::Template::Provider');

    my $Directory = $Self->GetArgument('directory');

    if ( !-d $Directory ) {
        $Self->PrintError("Please provide a directory. '$Directory' is not a valid directory.");
        return $Self->ExitCodeError();
    }

    my @FileList;

    # Regular DTLs
    if ( -d "$Directory/Kernel/Output/HTML/" ) {
        push @FileList, $Kernel::OM->Get('Kernel::System::Main')->DirectoryRead(
            Directory => "$Directory/Kernel/Output/HTML/",
            Filter    => "*.dtl",
            Recursive => 1,
        );
    }

    # Customized DTLs
    if ( -d "$Directory/Custom/Kernel/Output/HTML/" ) {
        push @FileList, $Kernel::OM->Get('Kernel::System::Main')->DirectoryRead(
            Directory => "$Directory/Custom/Kernel/Output/HTML/",
            Filter    => "*.dtl",
            Recursive => 1,
        );
    }

    # XML configuration files, may also contain DTL tags
    if ( -d "$Directory/Kernel/Config/Files/" ) {
        push @FileList, $Kernel::OM->Get('Kernel::System::Main')->DirectoryRead(
            Directory => "$Directory/Kernel/Config/Files/",
            Filter    => "*.xml",
            Recursive => 1,
        );
    }

    if ( !@FileList ) {
        $Self->PrintError("No affected files found in $Directory.");
        return $Self->ExitCodeError();
    }

    my $Success = 1;

    for my $File (@FileList) {
        my $ContentRef = $Kernel::OM->Get('Kernel::System::Main')->FileRead(
            Location => $File,
            Mode     => 'utf8',
        );

        my $TTFile = $File;
        $TTFile =~ s{[.]dtl$}{.tt}smx;

        print "$File -> $TTFile\n";

        # Correct file name in header (*.dtl -> *.tt)
        ${$ContentRef} =~ s{(\A# --\n# [a-zA-Z0-9/]+[.])dtl[ ]}{$1tt };

        my $TTContent;
        eval {
            $TTContent = $ProviderObject->MigrateDTLtoTT( Content => ${$ContentRef} );
        };
        if ($@) {
            $Self->PrintError("There were errors processing this file:\n$@\n");
            $Success = 0;
        }

        if ( $TTContent ne ${$ContentRef} ) {
            $Kernel::OM->Get('Kernel::System::Main')->FileWrite(
                Location => $TTFile,
                Content  => \$TTContent,
                Mode     => 'utf8',
            );
        }
    }

    if ( !$Success ) {
        $Self->PrintError("\nThere were errors converting the files, please see above!\n");
        return $Self->ExitCodeError();
    }

    $Self->Print("\n<green>All files ok.</green>\n");
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
