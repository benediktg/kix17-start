# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::ProcessManagement::TransitionValidation::ValidateDemo;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::System::Log',
);

=head1 NAME

Kernel::System::ProcessManagement::TransitionValidation::ValidateDemo - Demo for Transition Validation Module

=head1 SYNOPSIS

All ValidateDemo functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $ValidateDemoObject = $Kernel::OM->Get('Kernel::System::ProcessManagement::TransitionValidation::ValidateDemo');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item Validate()

    Validate Data

    my $ValidateResult = $ValidateModuleObject->Validate(
        Data       => {
            Queue => 'Raw',
            # ...
        },
    );

    Returns:

    $ValidateResult = 1;        # or undef, only returns 1 if Queue is 'Raw'

    );

=cut

sub Validate {
    my ( $Self, %Param ) = @_;

    for my $Needed (qw(Data)) {
        if ( !defined $Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # Check if we have Data to check against transitions conditions
    if ( !IsHashRefWithData( $Param{Data} ) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Data has no values!",
        );
        return;
    }

    if ( $Param{Data}{Queue} && $Param{Data}{Queue} eq 'Raw' ) {
        return 1;
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
