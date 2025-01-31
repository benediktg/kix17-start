# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Console::InterfaceConsole;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Console::Command::List',
    'Kernel::System::Main',
);

=head1 NAME

Kernel::System::Console::InterfaceConsole - console interface

=head1 SYNOPSIS

...

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $InterfaceConsoleObject = $Kernel::OM->Get('Kernel::System::Console::InterfaceConsole');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item Run()

execute a command. Returns the shell status code to be used by exit().

    my $StatusCode = $InterfaceConsoleObject->Run( @ARGV );

=cut

sub Run {
    my ( $Self, @CommandlineArguments ) = @_;

    my $CommandName;

    # Catch bash completion calls
    if ( $ENV{COMP_LINE} ) {
        $CommandName = 'Kernel::System::Console::Command::Internal::BashCompletion';
        return $Kernel::OM->Get($CommandName)->Execute(@CommandlineArguments);
    }

    # If we don't have any arguments OR the first argument is an option and not a command name,
    #   show the overview screen instead.
    if ( !@CommandlineArguments || substr( $CommandlineArguments[0], 0, 2 ) eq '--' ) {
        $CommandName = 'Kernel::System::Console::Command::List';
        return $Kernel::OM->Get($CommandName)->Execute(@CommandlineArguments);
    }

    # Ok, let's try to find the command.
    $CommandName = 'Kernel::System::Console::Command::' . $CommandlineArguments[0];

    if ( $Kernel::OM->Get('Kernel::System::Main')->Require( $CommandName, Silent => 1 ) ) {

        # Regular case: everything was ok, execute command.
        # Remove first parameter (command itself) to not confuse further parsing
        shift @CommandlineArguments;
        return $Kernel::OM->Get($CommandName)->Execute(@CommandlineArguments);
    }

    # If the command cannot be found/loaded, also show the overview screen.
    my $CommandObject = $Kernel::OM->Get('Kernel::System::Console::Command::List');
    $CommandObject->PrintError("Could not find $CommandName.\n\n");
    $CommandObject->Execute();
    return 127;    # EXIT_CODE_COMMAND_NOT_FOUND, see http://www.tldp.org/LDP/abs/html/exitcodes.html
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
