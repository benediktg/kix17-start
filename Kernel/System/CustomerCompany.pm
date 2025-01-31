# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::CustomerCompany;

use strict;
use warnings;

use base qw(Kernel::System::EventHandler);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Main',
);

=head1 NAME

Kernel::System::CustomerCompany - customer company lib

=head1 SYNOPSIS

All Customer functions. E.g. to add and update customer companies.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $CustomerCompanyObject = $Kernel::OM->Get('Kernel::System::CustomerCompany');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get needed objects
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $MainObject   = $Kernel::OM->Get('Kernel::System::Main');

    # load generator customer preferences module
    my $GeneratorModule = $ConfigObject->Get('CustomerCompany::PreferencesModule')->{Module}
        || 'Kernel::System::CustomerCompany::Preferences::DB';

    if ( $MainObject->Require($GeneratorModule) ) {
        $Self->{PreferencesObject} = $GeneratorModule->new();
    }

    # load customer company backend modules
    SOURCE:
    for my $Count ( '', 1 .. 10 ) {

        next SOURCE if !$ConfigObject->Get("CustomerCompany$Count");

        my $GenericModule = $ConfigObject->Get("CustomerCompany$Count")->{Module}
            || 'Kernel::System::CustomerCompany::DB';
        if ( !$MainObject->Require($GenericModule) ) {
            $MainObject->Die("Can't load backend module $GenericModule! $@");
        }
        $Self->{"CustomerCompany$Count"} = $GenericModule->new(
            Count              => $Count,
            PreferencesObject  => $Self->{PreferencesObject},
            CustomerCompanyMap => $ConfigObject->Get("CustomerCompany$Count"),
        );
    }

    # init of event handler
    $Self->EventHandlerInit(
        Config => 'CustomerCompany::EventModulePost',
    );

    return $Self;
}

=item CustomerCompanyAdd()

add a new customer company

    my $ID = $CustomerCompanyObject->CustomerCompanyAdd(
        CustomerID              => 'example.com',
        CustomerCompanyName     => 'New Customer Inc.',
        CustomerCompanyStreet   => '5201 Blue Lagoon Drive',
        CustomerCompanyZIP      => '33126',
        CustomerCompanyCity     => 'Miami',
        CustomerCompanyCountry  => 'USA',
        CustomerCompanyURL      => 'http://www.example.org',
        CustomerCompanyComment  => 'some comment',
        ValidID                 => 1,
        UserID                  => 123,
    );

NOTE: Actual fields accepted by this API call may differ based on
CustomerCompany mapping in your system configuration.

=cut

sub CustomerCompanyAdd {
    my ( $Self, %Param ) = @_;

    # check data source
    if ( !$Param{Source} ) {
        $Param{Source} = 'CustomerCompany';
    }

    # check needed stuff
    for (qw(CustomerID UserID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    my $Result = $Self->{ $Param{Source} }->CustomerCompanyAdd(%Param);
    return if !$Result;

    # trigger event
    $Self->EventHandler(
        Event => 'CustomerCompanyAdd',
        Data  => {
            CustomerID => $Param{CustomerID},
            NewData    => \%Param,
        },
        UserID => $Param{UserID},
    );

    return $Result;
}

=item CustomerCompanyGet()

get customer company attributes

    my %CustomerCompany = $CustomerCompanyObject->CustomerCompanyGet(
        CustomerID => 123,
    );

Returns:

    %CustomerCompany = (
        'CustomerCompanyName'    => 'Customer Inc.',
        'CustomerID'             => 'example.com',
        'CustomerCompanyStreet'  => '5201 Blue Lagoon Drive',
        'CustomerCompanyZIP'     => '33126',
        'CustomerCompanyCity'    => 'Miami',
        'CustomerCompanyCountry' => 'United States',
        'CustomerCompanyURL'     => 'http://example.com',
        'CustomerCompanyComment' => 'Some Comments',
        'ValidID'                => '1',
        'CreateTime'             => '2010-10-04 16:35:49',
        'ChangeTime'             => '2010-10-04 16:36:12',
    );

NOTE: Actual fields returned by this API call may differ based on
CustomerCompany mapping in your system configuration.

=cut

sub CustomerCompanyGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{CustomerID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need CustomerID!"
        );
        return;
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    SOURCE:
    for my $Count ( '', 1 .. 10 ) {

        next SOURCE if !$Self->{"CustomerCompany$Count"};

        my %Company = $Self->{"CustomerCompany$Count"}->CustomerCompanyGet( %Param, );
        next SOURCE if !%Company;

        # return company data
        return (
            %Company,
            Source => "CustomerCompany$Count",
            Config => $ConfigObject->Get("CustomerCompany$Count"),
        );
    }

    return;
}

=item CustomerCompanyUpdate()

update customer company attributes

    $CustomerCompanyObject->CustomerCompanyUpdate(
        CustomerCompanyID       => 'oldexample.com', # required for CustomerCompanyID-update
        CustomerID              => 'example.com',
        CustomerCompanyName     => 'New Customer Inc.',
        CustomerCompanyStreet   => '5201 Blue Lagoon Drive',
        CustomerCompanyZIP      => '33126',
        CustomerCompanyLocation => 'Miami',
        CustomerCompanyCountry  => 'USA',
        CustomerCompanyURL      => 'http://example.com',
        CustomerCompanyComment  => 'some comment',
        ValidID                 => 1,
        UserID                  => 123,
    );

=cut

sub CustomerCompanyUpdate {
    my ( $Self, %Param ) = @_;

    $Param{CustomerCompanyID} ||= $Param{CustomerID};

    # check needed stuff
    if ( !$Param{CustomerCompanyID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need CustomerCompanyID or CustomerID!"
        );
        return;
    }

    # check if company exists
    my %Company = $Self->CustomerCompanyGet( CustomerID => $Param{CustomerCompanyID} );
    if ( !%Company ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "No such company '$Param{CustomerCompanyID}'!",
        );
        return;
    }
    my $Result = $Self->{ $Company{Source} }->CustomerCompanyUpdate(%Param);
    return if !$Result;

    # trigger event
    $Self->EventHandler(
        Event => 'CustomerCompanyUpdate',
        Data  => {
            CustomerID    => $Param{CustomerID},
            OldCustomerID => $Param{CustomerCompanyID},
            NewData       => \%Param,
            OldData       => \%Company,
        },
        UserID => $Param{UserID},
    );
    return $Result;
}

=item CustomerCompanySourceList()

return customer company source list

    my %List = $CustomerCompanyObject->CustomerCompanySourceList(
        ReadOnly => 0 # optional, 1 returns only RO backends, 0 returns writable, if not passed returns all backends
    );

=cut

sub CustomerCompanySourceList {
    my ( $Self, %Param ) = @_;

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my %Data;
    SOURCE:
    for my $Count ( '', 1 .. 10 ) {

        next SOURCE if !$ConfigObject->Get("CustomerCompany$Count");

        if ( defined $Param{ReadOnly} ) {
            my $BackendConfig = $ConfigObject->Get("CustomerCompany$Count");
            if ( $Param{ReadOnly} ) {
                next SOURCE if !$BackendConfig->{ReadOnly};
            }
            else {
                next SOURCE if $BackendConfig->{ReadOnly};
            }
        }

        $Data{"CustomerCompany$Count"} = $ConfigObject->Get("CustomerCompany$Count")->{Name}
            || "No Name $Count";
    }

    return %Data;
}

=item CustomerCompanyList()

get list of customer companies.

    my %List = $CustomerCompanyObject->CustomerCompanyList();

    my %List = $CustomerCompanyObject->CustomerCompanyList(
        Valid => 0,
        Limit => 0,     # optional, override configured search result limit (0 means unlimited)
    );

    my %List = $CustomerCompanyObject->CustomerCompanyList(
        Search => 'somecompany',
    );

Returns:

%List = {
          'example.com' => 'example.com Customer Inc.',
          'acme.com'    => 'acme.com Acme, Inc.'
        };

=cut

sub CustomerCompanyList {
    my ( $Self, %Param ) = @_;

    my %Data;
    SOURCE:
    for my $Count ( '', 1 .. 10 ) {

        next SOURCE if !$Self->{"CustomerCompany$Count"};

        # get comppany list result of backend and merge it
        my %SubData = $Self->{"CustomerCompany$Count"}->CustomerCompanyList(%Param);
        %Data = ( %Data, %SubData );
    }
    return %Data;
}

=item GetPreferences()

get customer company preferences

    my %Preferences = $CustomerCompanyObject->GetPreferences(
        CustomerID => 'CustomerID',
    );

=cut

sub GetPreferences {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{CustomerID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need CustomerID!'
        );
        return;
    }

    # check if user exists
    my %Company = $Self->CustomerCompanyGet( CustomerID => $Param{CustomerID} );
    if ( !%Company ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "No such company '$Param{CustomerID}'!",
        );
        return;
    }

    # call new api (2.4.8 and higher)
    if ( $Self->{ $Company{Source} }->can('GetPreferences') ) {
        return $Self->{ $Company{Source} }->GetPreferences(%Param);
    }

    # call old api
    return $Self->{PreferencesObject}->GetPreferences(%Param);
}

=item SetPreferences()

set customer company preferences

    $CustomerCompanyObject->SetPreferences(
        Key        => 'CompanyComment',
        Value      => 'some comment',
        CustomerID => 'CustomerID',
    );

=cut

sub SetPreferences {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{CustomerID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need CustomerID!'
        );
        return;
    }

    # check if user exists
    my %Company = $Self->CustomerCompanyGet( CustomerID => $Param{CustomerID} );
    if ( !%Company ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "No such user '$Param{CustomerID}'!",
        );
        return;
    }

    my $Result;

    # call new api (2.4.8 and higher)
    if ( $Self->{ $Company{Source} }->can('SetPreferences') ) {
        $Result = $Self->{ $Company{Source} }->SetPreferences(%Param);
    }

    # call old api
    else {
        $Result = $Self->{PreferencesObject}->SetPreferences(%Param);
    }

    # trigger event handler
    if ($Result) {
        $Self->EventHandler(
            Event => 'CustomerCompanySetPreferences',
            Data  => {
                %Param,
                CompanyData => \%Company,
                Result      => $Result,
            },
            UserID => 1,
        );
    }
    return $Result;
}

=item SearchPreferences()

search in user preferences

    my %CustomerCompanyList = $CustomerCompanyObject->SearchPreferences(
        Key   => 'SomeKey',
        Value => 'SomeValue',   # optional, limit to a certain value/pattern
    );

=cut

sub SearchPreferences {
    my ( $Self, %Param ) = @_;

    my %Data;
    SOURCE:
    for my $Count ( '', 1 .. 10 ) {

        next SOURCE if !$Self->{"CustomerCompany$Count"};

        # get customer search result of backend and merge it
        # call new api (2.4.8 and higher)
        my %SubData;
        if ( $Self->{"CustomerUserCustomerCompany$Count"}->can('SearchPreferences') ) {
            %SubData = $Self->{"CustomerCompany$Count"}->SearchPreferences(%Param);
        }

        # call old api
        else {
            %SubData = $Self->{PreferencesObject}->SearchPreferences(%Param);
        }
        %Data = ( %SubData, %Data );
    }

    return %Data;
}

sub DESTROY {
    my $Self = shift;

    # execute all transaction events
    $Self->EventHandlerTransaction();

    return 1;
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
