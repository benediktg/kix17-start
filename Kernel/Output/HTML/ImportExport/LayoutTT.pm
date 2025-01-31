# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::ImportExport::LayoutTT;

use strict;
use warnings;

use Kernel::System::ObjectManager;

our @ObjectDependencies = (
    'Kernel::System::Log',
);

=head1 NAME

Kernel::Output::HTML::ImportExport::LayoutTT - layout backend module

=head1 SYNOPSIS

All layout functions for display TT code

=over 4

=cut

=item new()

create an object

    $BackendObject = Kernel::Output::HTML::ImportExport::LayoutTT->new(
        %Param,
    );

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item FormInputCreate()

create a input string

    my $Value = $BackendObject->FormInputCreate(
        Item => $ItemRef,
    );

=cut

sub FormInputCreate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Item} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need Item!'
        );
        return;
    }

    return $Param{Item}->{Input}->{Data};
}

=item FormDataGet()

get form data

    my $FormData = $BackendObject->FormDataGet();

=cut

sub FormDataGet {
    my ( $Self, %Param ) = @_;

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
