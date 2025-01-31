# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Console::Command::Dev::Tools::RPMSpecGenerate;

use strict;
use warnings;

use base qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Main',
    'Kernel::Output::HTML::Layout',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Generate RPM spec files.');

    return;
}

sub Run {
    my ( $Self, %Param ) = @_;

    $Self->Print("<yellow>Starting...</yellow>\n\n");

    my $Home = $Kernel::OM->Get('Kernel::Config')->Get('Home');

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # Call Output() once so that the TT objects are created.
    $LayoutObject->Output( Template => '' );
    $LayoutObject->{TemplateProviderObject}->include_path(
        ["$Home/scripts/auto_build/spec/templates"]
    );

    my @SpecFileTemplates = $Kernel::OM->Get('Kernel::System::Main')->DirectoryRead(
        Directory => "$Home/scripts/auto_build/spec/templates",
        Filter    => "*.spec.tt",
    );

    for my $SpecFileTemplate (@SpecFileTemplates) {
        my $SpecFileName = $SpecFileTemplate;
        $SpecFileName =~ s{^.*/spec/templates/}{};
        $SpecFileName = substr( $SpecFileName, 0, -3 );    # cut off .tt

        my $Output = $Kernel::OM->Get('Kernel::Output::HTML::Layout')->Output(
            TemplateFile => $SpecFileName,
        );
        my $TargetPath = "$Home/scripts/auto_build/spec/$SpecFileName";
        my $Written    = $Kernel::OM->Get('Kernel::System::Main')->FileWrite(
            Location => $TargetPath,
            Mode     => 'utf8',
            Content  => \$Output,
        );
        if ( !$Written ) {
            $Self->PrintError("Could not write $TargetPath.");
            return $Self->ExitCodeError();
        }
        $Self->Print("  <yellow>$SpecFileTemplate -> $TargetPath</yellow>\n");
    }

    $Self->Print("\n<green>Done.</green>\n");

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
