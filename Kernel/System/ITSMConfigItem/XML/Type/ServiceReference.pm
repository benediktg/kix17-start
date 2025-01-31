# --
# Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::ITSMConfigItem::XML::Type::ServiceReference;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Log',
    'Kernel::System::Service'
);

=head1 NAME

Kernel::System::ITSMConfigItem::XML::Type::ServiceReference - xml backend module

=head1 SYNOPSIS

All xml functions of ServiceReference objects

=over 4

=cut

=item new()

create an object

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $XMLTypeDummyBackendObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem::XML::Type::ServiceReference');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item ValueLookup()

get the xml data of a version

    my $Value = $BackendObject->ValueLookup(
        Value => 11, # (optional)
    );

=cut

sub ValueLookup {
    my ( $Self, %Param ) = @_;

    return '' if !$Param{Value};

    my %ServiceData = $Kernel::OM->Get('Kernel::System::Service')->ServiceGet(
        ServiceID => $Param{Value},
        UserID    => 1,
    );

    my $ServiceName = $Param{Value};

    if ( %ServiceData && $ServiceData{Name} ) {
        $ServiceName = $ServiceData{Name};
    }

    return $ServiceName;
}

=item StatsAttributeCreate()

create a attribute array for the stats framework

    my $Attribute = $BackendObject->StatsAttributeCreate(
        Key => 'Key::Subkey',
        Name => 'Name',
        Item => $ItemRef,
    );

=cut

sub StatsAttributeCreate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(Key Name Item)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!"
            );
            return;
        }
    }

    # create arrtibute
    my $Attribute = [
        {
            Name             => $Param{Name},
            UseAsXvalue      => 0,
            UseAsValueSeries => 0,
            UseAsRestriction => 1,
            Element          => $Param{Key},
            Block            => 'InputField',
        },
    ];

    return $Attribute;
}

=item ExportSearchValuePrepare()

prepare search value for export

    my $ArrayRef = $BackendObject->ExportSearchValuePrepare(
        Value => 11, # (optional)
    );

=cut

sub ExportSearchValuePrepare {
    my ( $Self, %Param ) = @_;

    # nothing given?
    return if !defined $Param{Value};

    # empty value?
    return '' if !$Param{Value};

    # lookup name for given service ID
    my %ServiceData = $Kernel::OM->Get('Kernel::System::Service')->ServiceGet(
        ServiceID => $Param{Value},
        UserID    => 1,
    );
    if ( %ServiceData && $ServiceData{Name} ) {
        return $ServiceData{Name};
    }

    return '';
}

=item ExportValuePrepare()

prepare value for export

    my $Value = $BackendObject->ExportValuePrepare(
        Value => 11, # (optional)
    );

=cut

sub ExportValuePrepare {
    my ( $Self, %Param ) = @_;

    # nothing given?
    return if !defined $Param{Value};

    # empty value?
    return '' if !$Param{Value};

    # lookup name for given service ID
    my %ServiceData = $Kernel::OM->Get('Kernel::System::Service')->ServiceGet(
        ServiceID => $Param{Value},
        UserID    => 1,
    );
    if ( %ServiceData && $ServiceData{Name} ) {
        return $ServiceData{Name};
    }

    return '';
}

=item ImportSearchValuePrepare()

prepare search value for import

    my $ArrayRef = $BackendObject->ImportSearchValuePrepare(
        Value => 11, # (optional)
    );

=cut

sub ImportSearchValuePrepare {
    my ( $Self, %Param ) = @_;

    # nothing given?
    return if !defined $Param{Value};

    # empty value?
    return '' if !$Param{Value};

    # check if Service name was given
    my $ServiceID = $Kernel::OM->Get('Kernel::System::Service')->ServiceLookup(
        Name => $Param{Value},
    );
    return $ServiceID if $ServiceID;

    # check if given value is a valid Service ID
    if ( $Param{Value} !~ /\D/ ) {
        my $ServiceName = $Kernel::OM->Get('Kernel::System::Service')->ServiceLookup(
            ServiceID => $Param{Value},
        );
        return $Param{Value} if $ServiceName;
    }

    return '';
}

=item ImportValuePrepare()

prepare value for import

    my $Value = $BackendObject->ImportValuePrepare(
        Value => 11, # (optional)
    );

=cut

sub ImportValuePrepare {
    my ( $Self, %Param ) = @_;

    # nothing given?
    return if !defined $Param{Value};

    # empty value?
    return '' if !$Param{Value};

    # check if Service name was given
    my $ServiceID = $Kernel::OM->Get('Kernel::System::Service')->ServiceLookup(
        Name => $Param{Value},
    );
    return $ServiceID if $ServiceID;

    # check if given value is a valid Service ID
    if ( $Param{Value} !~ /\D/ ) {
        my $ServiceName = $Kernel::OM->Get('Kernel::System::Service')->ServiceLookup(
            ServiceID => $Param{Value},
        );
        return $Param{Value} if $ServiceName;
    }

    return '';
}

1;


=head1 VERSION

$Revision$ $Date$

=cut

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut
