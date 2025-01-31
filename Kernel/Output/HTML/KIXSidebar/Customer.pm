# --
# Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::KIXSidebar::Customer;

use strict;
use warnings;

use Kernel::System::ObjectManager;

our @ObjectDependencies = (
    'Kernel::Output::HTML::Layout'
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{LayoutObject} = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    $Param{Config}->{QueryMinLength} = $Param{Config}->{QueryMinLength} || 1;
    $Param{Config}->{QueryDelay}     = $Param{Config}->{QueryDelay}     || 300;

    my $AdditionalClasses = '';
    if (
        $Param{Config}->{'NoActionWithoutSelection'}
        && $Param{Action} =~ /$Param{Config}->{'NoActionWithoutSelection'}/
    ) {
        $AdditionalClasses .= 'NoActionWithoutSelection';
    }
    if (
        $Param{Config}->{'InitialCollapsed'}
        && $Param{Action} =~ /$Param{Config}->{'InitialCollapsed'}/
    ) {
        if ( $AdditionalClasses.length > 0 ) {
            $AdditionalClasses .= ' ';
        }
        $AdditionalClasses .= 'Collapsed';
    }

    $Self->{LayoutObject}->Block(
        Name => 'SidebarFrame',
        Data => {
            %{$Param{Ticket} || {}},
            %{$Param{Config}},
            AdditionalClasses => $AdditionalClasses,
        },
    );

    $Self->{LayoutObject}->Block(
        Name => 'SearchBox',
        Data => {
            %{$Param{Ticket} || {}},
            %{$Param{Config}},
        },
    );
    $Self->{LayoutObject}->Block(
        Name => 'SearchJS',
        Data => {
            %{$Param{Ticket} || {}},
            %{$Param{Config}},
        },
    );

    if (
        $Param{Config}->{'AutoSearch'}
        && $Param{Action} =~ /$Param{Config}->{'AutoSearch'}/
    ) {
        $Self->{LayoutObject}->Block(
            Name => 'AutoSearch',
            Data => {
                %{$Param{Ticket} || {}},
                %{$Param{Config}},
            },
        );
    }
    if (
        $Param{Config}->{'AutoSelectOne'}
        && $Param{Action} =~ /$Param{Config}->{'AutoSelectOne'}/
    ) {
        $Self->{LayoutObject}->Block(
            Name => 'AutoSelectOne',
            Data => {
                %{$Param{Ticket} || {}},
                %{$Param{Config}},
            },
        );
    }
    if ( $Param{Config}->{'InitialJS'} ) {
        $Self->{LayoutObject}->Block(
            Name => 'InitialJS',
            Data => {
                InitialJS => $Param{Config}->{'InitialJS'},
            },
        );
    }

    # output result
    my $Content = $Self->{LayoutObject}->Output(
        TemplateFile   => 'KIXSidebar/CustomerSearch',
        Data           => {
            %{$Param{Ticket} || {}},
            %{$Param{Config}},
        },
        KeepScriptTags => $Param{AJAX},
    );

    return $Content;
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
