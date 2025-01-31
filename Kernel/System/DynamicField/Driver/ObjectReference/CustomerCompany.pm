# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::DynamicField::Driver::ObjectReference::CustomerCompany;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(Kernel::System::DynamicField::Driver::BaseSelect);

our @ObjectDependencies = (
    'Kernel::System::CustomerCompany',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::Ticket::ColumnFilter',
);

=head1 NAME

Kernel::System::DynamicField::Driver::ObjectReference

=head1 SYNOPSIS

DynamicFields ObjectReference Driver delegate

=head1 PUBLIC INTERFACE

This module implements the public interface of L<Kernel::System::DynamicField::Driver>.
Please look there for a detailed reference of the functions.

=over 4

=item new()

usually, you want to create an instance of this
by using Kernel::System::DynamicField::Driver->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{CustomerCompanyObject}   = $Kernel::OM->Get('Kernel::System::CustomerCompany');
    $Self->{DynamicFieldValueObject} = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');

    # set field behaviors
    $Self->{Behaviors} = {
        'IsACLReducible'               => 1,
        'IsNotificationEventCondition' => 1,
        'IsSortable'                   => 0,
        'IsFiltrable'                  => 0,
        'IsStatsCondition'             => 1,
        'IsCustomerInterfaceCapable'   => 1,
        'CanRandomize'                 => 1,
    };

    # get the Dynamic Field Driver custmom extensions
    my $DynamicFieldDriverExtensions
        = $Kernel::OM->Get('Kernel::Config')
        ->Get('DynamicFields::Extension::Driver::CustomerCompany');

    EXTENSION:
    for my $ExtensionKey ( sort keys %{$DynamicFieldDriverExtensions} ) {

        # skip invalid extensions
        next EXTENSION if !IsHashRefWithData( $DynamicFieldDriverExtensions->{$ExtensionKey} );

        # create a extension config shortcut
        my $Extension = $DynamicFieldDriverExtensions->{$ExtensionKey};

        # check if extension has a new module
        if ( $Extension->{Module} ) {

            # check if module can be loaded
            if (
                !$Kernel::OM->Get('Kernel::System::Main')->RequireBaseClass( $Extension->{Module} )
            ) {
                die "Can't load dynamic fields backend module"
                    . " $Extension->{Module}! $@";
            }
        }

        # check if extension contains more behabiors
        if ( IsHashRefWithData( $Extension->{Behaviors} ) ) {

            %{ $Self->{Behaviors} } = (
                %{ $Self->{Behaviors} },
                %{ $Extension->{Behaviors} }
            );
        }
    }

    return $Self;
}

sub ValueGet {
    my ( $Self, %Param ) = @_;

    my $DFValue = $Kernel::OM->Get('Kernel::System::DynamicFieldValue')->ValueGet(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
    );

    return if !$DFValue;
    return if !IsArrayRefWithData($DFValue);
    return if !IsHashRefWithData( $DFValue->[0] );

    # extract real values
    my @ReturnData;
    for my $Item ( @{$DFValue} ) {
        push @ReturnData, $Item->{ValueText}
    }

    return \@ReturnData;
}

sub ValueSet {
    my ( $Self, %Param ) = @_;

    # check value
    my @Values;
    if ( ref $Param{Value} eq 'ARRAY' ) {
        @Values = @{ $Param{Value} };
    }
    else {
        @Values = ( $Param{Value} );
    }

    # get complete customer company list
    my %CustomerCompanyList = $Self->{CustomerCompanyObject}->CustomerCompanyList(
        Limit => 0,
    );

    # process all values
    for my $Object (@Values) {

        next if !$Object;

        # check for valid CustomerCompany
        my $CompanyName = $CustomerCompanyList{ $Object };

        if ( !$CompanyName ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "The value for the field CustomerCompany is invalid!\n"
                    . "No Company with ID "
                    . $Object
                    . " found in configured backend(s).",
            );
            return 0;
        }
    }

    # get dynamic field value object
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');

    my $Success;
    if ( IsArrayRefWithData( \@Values ) ) {

        # if there is at least one value to set, this means one or more values are selected,
        #    set those values!
        my @ValueText;
        for my $Item (@Values) {
            push @ValueText, { ValueText => $Item };
        }

        $Success = $DynamicFieldValueObject->ValueSet(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $Param{ObjectID},
            Value    => \@ValueText,
            UserID   => $Param{UserID},
        );
    }
    else {

        # otherwise no value was selected, then in fact this means that any value there should be
        # deleted
        $Success = $DynamicFieldValueObject->ValueDelete(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $Param{ObjectID},
            UserID   => $Param{UserID},
        );
    }

    return $Success;
}

sub ValueValidate {
    my ( $Self, %Param ) = @_;

    # check value
    my @Values;
    if ( IsArrayRefWithData( $Param{Value} ) ) {
        @Values = @{ $Param{Value} };
    }
    else {
        @Values = ( $Param{Value} );
    }

    # get complete customer company list
    my %CustomerCompanyList = $Self->{CustomerCompanyObject}->CustomerCompanyList(
        Limit => 0,
    );

    # process all values
    for my $Object (@Values) {

        next if !$Object;

        # check for valid CustomerCompany
        my $CompanyName = $CustomerCompanyList{ $Object };

        if ( !$CompanyName ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "The value for the field CustomerCompany is invalid!\n"
                    . "No Company with ID "
                    . $Object
                    . " found in configured backend(s).",
            );
            return 0;
        }
    }

    # get dynamic field value object
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');

    my $Success;
    for my $Item (@Values) {

        $Success = $DynamicFieldValueObject->ValueValidate(
            Value => {
                ValueText => $Item,
            },
            UserID => $Param{UserID}
        );
        return if !$Success
    }
    return $Success;
}

sub EditFieldRender {
    my ( $Self, %Param ) = @_;

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldName   = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel  = $Param{DynamicFieldConfig}->{Label};

    my $ObjectReference  = $FieldConfig->{ObjectReference};
    my $DisplayFieldType = $FieldConfig->{DisplayFieldType};

    my $Value;

    # set the field value or default
    if ( $Param{UseDefaultValue} ) {
        $Value = ( defined $FieldConfig->{DefaultValue} ? $FieldConfig->{DefaultValue} : '' );
    }
    $Value = $Param{Value} // $Value;

    # check if a value in a template (GenericAgent etc.)
    # is configured for this dynamic field
    if (
        IsHashRefWithData( $Param{Template} )
        && defined $Param{Template}->{$FieldName}
    ) {
        $Value = $Param{Template}->{$FieldName};
    }

    # extract the dynamic field value form the web request
    my $FieldValue = $Self->EditFieldValueGet(
        %Param,
    );

    # set values from ParamObject if present
    if ( $DisplayFieldType eq 'AutoComplete' && IsArrayRefWithData($FieldValue) ) {
        $Value = $FieldValue->[0];
    }
    elsif ( IsArrayRefWithData($FieldValue) ) {
        $Value = $FieldValue;
    }

    # check and set class if necessary
    my $FieldClass       = 'DynamicFieldObjectReference Modernize';
    my $HiddenFieldClass = 'Hidden';

    if ( defined $Param{Class} && $Param{Class} ne '' ) {
        $FieldClass .= ' ' . $Param{Class};
    }

    # set field as mandatory
    if ( $Param{Mandatory} ) {
        $FieldClass       .= ' Validate_Required';
        $HiddenFieldClass .= ' Validate_Required';
    }

    # set error css class
    if ( $Param{ServerError} ) {
        $FieldClass       .= ' ServerError';
        $HiddenFieldClass .= ' ServerError';
    }

    # set TreeView class
    if ( $FieldConfig->{TreeView} ) {
        $FieldClass .= ' DynamicFieldWithTreeView';
    }

    # check value
    my $SelectedValuesArrayRef;
    if ( defined $Value ) {
        if ( ref $Value eq 'ARRAY' ) {
            $SelectedValuesArrayRef = $Value;
        }
        else {
            $SelectedValuesArrayRef = [$Value];
        }
    }

    # create HTML string
    my $HTMLString;

    if ( $DisplayFieldType eq 'AutoComplete' ) {

        # set value
        if ( ref($SelectedValuesArrayRef) eq 'ARRAY' && scalar @{$SelectedValuesArrayRef} ) {
            $Value = $SelectedValuesArrayRef->[0];
        }
        else {
            $Value = '';
        }

        # set field as autocomplete
        $FieldClass .= ' CustomerCompanyAutoComplete ';
        my $FieldNameKey = $FieldName . '_Key';

        # get user data to display value
        my $UserDataString = '';
        if ($Value) {
            my %CustomerCompanyData = $Self->{CustomerCompanyObject}->CustomerCompanyGet(
                CustomerID => $Value,
            );
            $UserDataString = $CustomerCompanyData{CustomerCompanyName};
        }

        $HTMLString = <<"EOF";
<input type="text" class="$HiddenFieldClass" id="$FieldName" name="$FieldName" title="$FieldLabel" value="$Value" />
<input type="text" class="$FieldClass" id="$FieldNameKey" name="$FieldNameKey" title="$FieldLabel" value="$UserDataString" />
EOF

        # add JS for AutoComplete
        my $FieldSelector = '.CustomerCompanyAutoComplete';

        $Param{LayoutObject}->AddJSOnDocumentComplete( Code => <<"EOF");
                \$('$FieldSelector').each(function () {
                    Core.Config.Set('Autocomplete.QueryDelay', 100);
                    Core.Config.Set('Autocomplete.MaxResultsDisplayed', 20);
                    Core.Config.Set('Autocomplete.MinQueryLength', 2);
                    Core.Config.Set('Autocomplete.DynamicWidth', 1);
                    Core.Config.Set('Autocomplete.ShowCustomerTickets', 0);
                    Core.Config.Set('Autocomplete.SearchButtonText', "Search Customer");
                    Core.KIX4OTRS.Agent.DynamicFieldObjectReference.Init(\$(this), 1, '$ObjectReference');
                });
EOF

    }
    elsif ( $DisplayFieldType eq 'Multiselect' || $DisplayFieldType eq 'Dropdown' ) {

        # get data
        my %ObjectList;
        my %CompanyList = $Self->{CustomerCompanyObject}->CustomerCompanyList(
            Valid => 1,
        );

        for my $Company ( keys %CompanyList ) {
            $ObjectList{$Company} = $Company;
        }

        # multiselect or dropdown
        my $Multiple = 0;
        if ( $DisplayFieldType eq 'Multiselect' ) {
            $Multiple = 1;
        }

        # set PossibleValues, use PossibleValuesFilter if defined
        my $PossibleValues = $Param{PossibleValuesFilter} // \%ObjectList;

        # create HTML string
        $HTMLString = $Param{LayoutObject}->BuildSelection(
            Data         => $PossibleValues || {},
            SelectedID   => $Value,
            Name         => $FieldName,
            Class        => $FieldClass,
            HTMLQuote    => 1,
            Multiple     => $Multiple,
            PossibleNone => $FieldConfig->{PossibleNone},
        );
    }

    if ( $Param{AJAXUpdate} ) {

        my $FieldSelector = '#' . $FieldName;

        my $FieldsToUpdate = '';
        if ( IsArrayRefWithData( $Param{UpdatableFields} ) ) {

            # Remove current field from updatable fields list
            my @FieldsToUpdate = grep { $_ ne $FieldName } @{ $Param{UpdatableFields} };

            # quote all fields, put commas in between them
            $FieldsToUpdate = join( ', ', map {"'$_'"} @FieldsToUpdate );
        }

        # add js to call FormUpdate()
        $Param{LayoutObject}->AddJSOnDocumentComplete( Code => <<"EOF");
\$('$FieldSelector').on('change', function (Event) {
    Core.AJAX.FormUpdate(\$(this).parents('form'), 'AJAXUpdate', '$FieldName', [ $FieldsToUpdate ]);
});
EOF
    }

    if ( $Param{ServerError} ) {

        my $ErrorMessage = $Param{ErrorMessage} || 'This field is required.';
        $ErrorMessage = $Param{LayoutObject}->{LanguageObject}->Translate($ErrorMessage);
        my $DivID = $FieldName . 'ServerError';

        # for server side validation
        $HTMLString .= <<"EOF";

<div id="$DivID" class="TooltipErrorMessage">
    <p>
        $ErrorMessage
    </p>
</div>
EOF
    }

    # call EditLabelRender on the common Driver
    my $LabelString = $Self->EditLabelRender(
        %Param,
        Mandatory => $Param{Mandatory} || '0',
        FieldName => $FieldName,
    );

    my $Data = {
        Field => $HTMLString,
        Label => $LabelString,
    };

    return $Data;
}

sub EditFieldValueGet {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    my $Value;

    # check if there is a Template and retrieve the dynamic field value from there
    if ( IsHashRefWithData( $Param{Template} ) && defined $Param{Template}->{$FieldName} ) {
        $Value = $Param{Template}->{$FieldName};
    }

    # otherwise get dynamic field value from the web request
    elsif (
        defined $Param{ParamObject}
        && ref $Param{ParamObject} eq 'Kernel::System::Web::Request'
    ) {
        my @Data = $Param{ParamObject}->GetArray( Param => $FieldName );

        if (
            $Param{DynamicFieldConfig}->{Config}->{DisplayFieldType} eq 'AutoComplete'
            && $Data[0]
        ) {
            my $SearchValue = $Param{ParamObject}->GetParam( Param => $FieldName . '_Key' );
            if ( !$SearchValue ) {
                $Data[0] = '';
            }
        }

        # delete empty values (can happen if the user has selected the "-" entry)
        my $Index = 0;
        ITEM:
        for my $Item ( sort @Data ) {

            if ( !$Item ) {
                splice( @Data, $Index, 1 );
                next ITEM;
            }
            $Index++;
        }

        $Value = \@Data;
    }

    if ( defined $Param{ReturnTemplateStructure} && $Param{ReturnTemplateStructure} eq "1" ) {
        return {
            $FieldName => $Value,
        };
    }

    # for this field the normal return an the ReturnValueStructure are the same
    return $Value;
}

sub EditFieldValueValidate {
    my ( $Self, %Param ) = @_;

    # get the field value from the http request
    my $Values = $Self->EditFieldValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        ParamObject        => $Param{ParamObject},

        # not necessary for this Driver but place it for consistency reasons
        ReturnValueStructure => 1,
    );

    my $ServerError;
    my $ErrorMessage;

    # perform necessary validations
    if ( $Param{Mandatory} && !IsArrayRefWithData($Values) ) {
        return {
            ServerError => 1,
        };
    }
    else {

        # get complete customer company list
        my %CustomerCompanyList = $Self->{CustomerCompanyObject}->CustomerCompanyList(
            Limit => 0,
        );

        # process all values
        for my $Object ( @{$Values} ) {
            next if !$Object;

            # check for valid CustomerCompany
            my $CompanyName = $CustomerCompanyList{ $Object };

            if ( !$CompanyName ) {
                $ServerError  = 1;
                $ErrorMessage = 'The field content is invalid';
            }
        }
    }

    # create resulting structure
    my $Result = {
        ServerError  => $ServerError,
        ErrorMessage => $ErrorMessage,
    };

    return $Result;
}

sub DisplayValueRender {
    my ( $Self, %Param ) = @_;

    # set HTMLOuput as default if not specified
    if ( !defined $Param{HTMLOutput} ) {
        $Param{HTMLOutput} = 1;
    }

    # set Value and Title variables
    my $Value         = '';
    my $Title         = '';
    my $ValueMaxChars = $Param{ValueMaxChars} || '';
    my $TitleMaxChars = $Param{TitleMaxChars} || '';

    # check value
    my @Values;
    if ( ref $Param{Value} eq 'ARRAY' ) {
        @Values = @{ $Param{Value} };
    }
    else {
        @Values = ( $Param{Value} );
    }

    my @ReadableValues;
    my @ReadableTitles;

    my $ShowValueEllipsis;
    my $ShowTitleEllipsis;

    VALUEITEM:
    for my $Item (@Values) {
        next VALUEITEM if !$Item;

        my $ReadableValue = $Item;

        my %CustomerCompanyData = $Self->{CustomerCompanyObject}->CustomerCompanyGet(
            CustomerID => $ReadableValue,
        );
        $ReadableValue = $CustomerCompanyData{CustomerCompanyName};

        # alternative display string defined ?
        if ( $Param{DynamicFieldConfig}->{Config}->{AlternativeDisplay} ) {
            $ReadableValue = $Param{DynamicFieldConfig}->{Config}->{AlternativeDisplay};
            $ReadableValue =~ s{<(.+?)>}{$CustomerCompanyData{$1}}egx;
        }

        my $ReadableLength = length $ReadableValue;

        # set title equal value
        my $ReadableTitle = $ReadableValue;

        # cut strings if needed
        if ( $ValueMaxChars ne '' ) {

            if ( length $ReadableValue > $ValueMaxChars ) {
                $ShowValueEllipsis = 1;
            }
            $ReadableValue = substr $ReadableValue, 0, $ValueMaxChars;

            # decrease the max parameter
            $ValueMaxChars = $ValueMaxChars - $ReadableLength;
            if ( $ValueMaxChars < 0 ) {
                $ValueMaxChars = 0;
            }
        }

        if ( $TitleMaxChars ne '' ) {

            if ( length $ReadableTitle > $ValueMaxChars ) {
                $ShowTitleEllipsis = 1;
            }
            $ReadableTitle = substr $ReadableTitle, 0, $TitleMaxChars;

            # decrease the max parameter
            $TitleMaxChars = $TitleMaxChars - $ReadableLength;
            if ( $TitleMaxChars < 0 ) {
                $TitleMaxChars = 0;
            }
        }

        # HTMLOuput transformations
        if ( $Param{HTMLOutput} ) {

            $ReadableValue = $Param{LayoutObject}->Ascii2Html(
                Text => $ReadableValue,
            );

            $ReadableTitle = $Param{LayoutObject}->Ascii2Html(
                Text => $ReadableTitle,
            );
        }

        if ( length $ReadableValue ) {
            push @ReadableValues, $ReadableValue;
        }
        if ( length $ReadableTitle ) {
            push @ReadableTitles, $ReadableTitle;
        }
    }

    # get specific field settings
    my $FieldConfig
        = $Kernel::OM->Get('Kernel::Config')->Get('DynamicFields::Driver')->{Multiselect} || {};

    # set new line separator
    my $ItemSeparator = $FieldConfig->{ItemSeparator} || ', ';

    $Value = join( $ItemSeparator, @ReadableValues );
    $Title = join( $ItemSeparator, @ReadableTitles );

    if ($ShowValueEllipsis) {
        $Value .= '...';
    }
    if ($ShowTitleEllipsis) {
        $Title .= '...';
    }

    # this field type does not support the Link Feature
    my $Link;

    # create return structure
    my $Data = {
        Value => $Value,
        Title => $Title,
        Link  => $Link,
    };
    return $Data;
}

sub SearchFieldRender {
    my ( $Self, %Param ) = @_;

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldName   = 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel  = $Param{DynamicFieldConfig}->{Label};

    my $ObjectReference  = $FieldConfig->{ObjectReference};
    my $DisplayFieldType = $FieldConfig->{DisplayFieldType};

    my $Value = '';

    my @DefaultValue;

    if ( defined $Param{DefaultValue} ) {
        @DefaultValue = split /;/, $Param{DefaultValue};
    }

    # set the field value
    if (@DefaultValue) {
        $Value = \@DefaultValue;
    }

    # get the field value, this function is always called after the profile is loaded
    my $FieldValues = $Self->SearchFieldValueGet(
        %Param,
    );

    if ( $DisplayFieldType eq 'AutoComplete' && defined $FieldValues ) {
        $Value = $FieldValues->[0];
    }
    elsif ( defined $FieldValues ) {
        $Value = $FieldValues;
    }

    # check and set class if necessary
    my $FieldClass = 'DynamicFieldObjectReference Modernize';

    # set PossibleValues
    my $SelectionData;

    # get historical values from database
    my $HistoricalValues = $Self->HistoricalValuesGet(%Param);

    # add historic values to current values (if they don't exist anymore)
    if ( IsHashRefWithData($HistoricalValues) ) {
        for my $Key ( sort keys %{$HistoricalValues} ) {
            if ( !$SelectionData->{$Key} ) {
                $SelectionData->{$Key} = $HistoricalValues->{$Key}
            }
        }
    }

    my $HTMLString;
    if ( $DisplayFieldType eq 'AutoComplete' ) {

        # set field as autocomplete
        $FieldClass .= ' CustomerCompanyAutoComplete ';
        my $FieldNameKey = $FieldName . '_Key';

        # get user data to display value
        my $UserDataString = '';
        if ($Value) {
            my %CustomerCompanyData = $Self->{CustomerCompanyObject}->CustomerCompanyGet(
                CustomerID => $Value,
            );
            $UserDataString = $CustomerCompanyData{CustomerCompanyName};
        }

        $HTMLString = <<"EOF";
<input type="text" class="Hidden" id="$FieldName" name="$FieldName" title="$FieldLabel" value="$Value" />
<input type="text" class="$FieldClass" id="$FieldNameKey" name="$FieldNameKey" title="$FieldLabel" value="$UserDataString" />
EOF

        # add JS for AutoComplete
        my $FieldSelector = '.CustomerCompanyAutoComplete';

        $Param{LayoutObject}->AddJSOnDocumentComplete( Code => <<"EOF");
                \$('$FieldSelector').each(function () {
                    Core.Config.Set('Autocomplete.QueryDelay', 100);
                    Core.Config.Set('Autocomplete.MaxResultsDisplayed', 20);
                    Core.Config.Set('Autocomplete.MinQueryLength', 2);
                    Core.Config.Set('Autocomplete.DynamicWidth', 1);
                    Core.Config.Set('Autocomplete.ShowCustomerTickets', 0);
                    Core.Config.Set('Autocomplete.SearchButtonText', "Search Customer");
                    Core.KIX4OTRS.Agent.DynamicFieldObjectReference.Init(\$(this), 1, '$ObjectReference');
                });
EOF

        $HTMLString .= <<"EOF";
<script type="text/javascript">//<![CDATA[
    function Init$FieldNameKey() {
        \$('$FieldSelector').each(function () {
            Core.Config.Set('Autocomplete.QueryDelay', 100);
            Core.Config.Set('Autocomplete.MaxResultsDisplayed', 20);
            Core.Config.Set('Autocomplete.MinQueryLength', 2);
            Core.Config.Set('Autocomplete.DynamicWidth', 1);
            Core.Config.Set('Autocomplete.ShowCustomerTickets', 0);
            Core.Config.Set('Autocomplete.SearchButtonText', "Search Customer");
            Core.KIX4OTRS.Agent.DynamicFieldObjectReference.Init(\$(this), 1, '$ObjectReference');
        });
    }
    function Wait$FieldNameKey() {
        if (window.jQuery) {
            \$('#Attribute').on('redraw.InputField', function() {
                Init$FieldNameKey();
            });
            if (
                \$('form[name=compose] input[name=Action]').first().val() == 'AdminGenericAgent'
                && \$('form[name=compose] input[name=Subaction]').first().val() == 'UpdateAction'
            ) {
                Init$FieldNameKey();
            }
            if (
                \$('form[name=compose] input[name=Action]').first().val() == 'AdminNotificationEvent'
                && (
                    \$('form[name=compose] input[name=Subaction]').first().val() == 'ChangeAction'
                    || \$('form[name=compose] input[name=Subaction]').first().val() == 'AddAction'
                )
            ) {
                Init$FieldNameKey();
            }
        } else {
            window.setTimeout(Wait$FieldNameKey, 1);
        }
    }
    window.setTimeout(Wait$FieldNameKey, 0);
//]]></script>
EOF
    }
    elsif ( $DisplayFieldType eq 'Multiselect' || $DisplayFieldType eq 'Dropdown' ) {

        # get data
        my %ObjectList;
        my %CompanyList = $Self->{CustomerCompanyObject}->CustomerCompanyList(
            Valid => 1,
        );

        for my $Company ( keys %CompanyList ) {
            $ObjectList{$Company} = $Company;
        }

        # set PossibleValues, use PossibleValuesFilter if defined
        my $PossibleValues = $Param{PossibleValuesFilter} // \%ObjectList;

        # create HTML string
        $HTMLString = $Param{LayoutObject}->BuildSelection(
            Data         => $PossibleValues || {},
            SelectedID   => $Value,
            Name         => $FieldName,
            Class        => $FieldClass,
            HTMLQuote    => 1,
            Multiple     => 1,
            PossibleNone => $FieldConfig->{PossibleNone},
        );
    }

    # call EditLabelRender on the common Driver
    my $LabelString = $Self->EditLabelRender(
        %Param,
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        FieldName          => $FieldName,
    );

    my $Data = {
        Field => $HTMLString,
        Label => $LabelString,
    };

    return $Data;
}

sub SearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    # get field value
    my $Value = $Self->SearchFieldValueGet(%Param);

    my $DisplayValue;

    if ( defined $Value && !$Value ) {
        $DisplayValue = '';
    }

    if ($Value) {
        if ( ref $Value eq 'ARRAY' ) {

            my @DisplayItemList;
            for my $Item ( @{$Value} ) {

                # set the display value
                my $DisplayItem = $Param{DynamicFieldConfig}->{Config}->{PossibleValues}->{$Item}
                    || $Item;

                # translate the value
                if (
                    $Param{DynamicFieldConfig}->{Config}->{TranslatableValues}
                    && defined $Param{LayoutObject}
                ) {
                    $DisplayItem = $Param{LayoutObject}->{LanguageObject}->Translate($DisplayItem);
                }

                push @DisplayItemList, $DisplayItem;
            }

            # combine different values into one string
            $DisplayValue = join ' + ', @DisplayItemList;
        }
        else {

            # set the display value
            $DisplayValue = $Param{DynamicFieldConfig}->{Config}->{PossibleValues}->{$Value};

            # translate the value
            if (
                $Param{DynamicFieldConfig}->{Config}->{TranslatableValues}
                && defined $Param{LayoutObject}
            ) {
                $DisplayValue = $Param{LayoutObject}->{LanguageObject}->Translate($DisplayValue);
            }
        }
    }

    # return search parameter structure
    return {
        Parameter => {
            Equals => $Value,
        },
        Display => $DisplayValue,
    };
}

sub StatsFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    return {
        Name    => $Param{DynamicFieldConfig}->{Label},
        Element => 'DynamicField_' . $Param{DynamicFieldConfig}->{Name},
    };
}

sub CommonSearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    my $Operator = 'Equals';
    my $Value    = $Param{Value};

    return {
        $Operator => $Value,
    };
}

sub ReadableValueRender {
    my ( $Self, %Param ) = @_;

    # set Value and Title variables
    my $Value = '';
    my $Title = '';

    # check value
    my @Values;
    if ( ref $Param{Value} eq 'ARRAY' ) {
        @Values = @{ $Param{Value} };
    }
    else {
        @Values = ( $Param{Value} );
    }

    my @ReadableValues;

    VALUEITEM:
    for my $Item (@Values) {
        next VALUEITEM if !$Item;

        push @ReadableValues, $Item;
    }

    # set new line separator
    my $ItemSeparator = ', ';

    # Ouput transformations
    $Value = join( $ItemSeparator, @ReadableValues );
    $Title = $Value;

    # cut strings if needed
    if ( $Param{ValueMaxChars} && length($Value) > $Param{ValueMaxChars} ) {
        $Value = substr( $Value, 0, $Param{ValueMaxChars} ) . '...';
    }
    if ( $Param{TitleMaxChars} && length($Title) > $Param{TitleMaxChars} ) {
        $Title = substr( $Title, 0, $Param{TitleMaxChars} ) . '...';
    }

    # create return structure
    my $Data = {
        Value => $Value,
        Title => $Title,
    };

    return $Data;
}

sub TemplateValueTypeGet {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # set the field types
    my $EditValueType   = 'ARRAY';
    my $SearchValueType = 'ARRAY';

    # return the correct structure
    if ( $Param{FieldType} eq 'Edit' ) {
        return {
            $FieldName => $EditValueType,
            }
    }
    elsif ( $Param{FieldType} eq 'Search' ) {
        return {
            'Search_' . $FieldName => $SearchValueType,
            }
    }
    else {
        return {
            $FieldName             => $EditValueType,
            'Search_' . $FieldName => $SearchValueType,
            }
    }
}

sub RandomValueSet {
    my ( $Self, %Param ) = @_;

    # get random value
    my %PossibleValues = $Self->{CustomerCompanyObject}->CustomerCompanyList(
        Valid => 1,
    );
    # set none value if defined on field config
    if ( $Param{DynamicFieldConfig}->{Config}->{PossibleNone} ) {
        $PossibleValues{''} = '-';
    }
    my @PossibleKeys   = keys( %PossibleValues );
    my $Value          = $PossibleKeys[ rand( @PossibleKeys ) ];

    my $Success = $Self->ValueSet(
        %Param,
        Value => $Value,
    );

    if ( !$Success ) {
        return {
            Success => 0,
        };
    }
    return {
        Success => 1,
        Value   => $Value,
    };
}

sub ObjectMatch {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # the attribute must be an array
    return 0 if !IsArrayRefWithData( $Param{ObjectAttributes}->{$FieldName} );

    my $Match;

    # search in all values for this attribute
    VALUE:
    for my $AttributeValue ( @{ $Param{ObjectAttributes}->{$FieldName} } ) {

        next VALUE if !defined $AttributeValue;

        # only need to match one
        if ( $Param{Value} eq $AttributeValue ) {
            $Match = 1;
            last VALUE;
        }
    }

    return $Match;
}

sub PossibleValuesGet {
    my ( $Self, %Param ) = @_;

    # to store the possible values
    my %PossibleValues = ();

    if (
        $Param{DynamicFieldConfig}->{Config}->{DisplayFieldType} ne 'AutoComplete'
        || $Param{GetAutocompleteValues}
    ) {
        # get data
        my %ObjectList;
        if ($Param{Search}) {
            %ObjectList = $Self->{CustomerCompanyObject}->CustomerCompanyList(
                Search => $Param{Search},
            );
        }
        else {
            %ObjectList = $Self->{CustomerCompanyObject}->CustomerCompanyList(
                Valid => 1,
            );
        }

        # set PossibleValues
        my $DefinedPossibleValues = \%ObjectList;

        # set none value if defined on field config
        if ( $Param{DynamicFieldConfig}->{Config}->{PossibleNone} ) {
            %PossibleValues = ( '' => '-' );
        }

        # set all other possible values if defined on field config
        if ( IsHashRefWithData($DefinedPossibleValues) ) {

            %PossibleValues = (
                %PossibleValues,
                %{$DefinedPossibleValues},
            );
        }
    }

    # return the possible values hash as a reference
    return \%PossibleValues;
}

sub HistoricalValuesGet {
    my ( $Self, %Param ) = @_;

    # get historical values from database
    my $HistoricalValues = $Self->{DynamicFieldValueObject}->HistoricalValueGet(
        FieldID   => $Param{DynamicFieldConfig}->{ID},
        ValueType => 'Text',
    );

    # return the historical values from database
    return $HistoricalValues;
}

sub ValueLookup {
    my ( $Self, %Param ) = @_;

    my @Keys;
    if ( ref $Param{Key} eq 'ARRAY' ) {
        @Keys = @{ $Param{Key} };
    }
    else {
        @Keys = ( $Param{Key} );
    }

    # to store final values
    my @Values;

    KEYITEM:
    for my $Item (@Keys) {
        next KEYITEM if !$Item;

        # set the value as the key by default
        my $Value = $Item;

        my %CustomerCompanyData = $Self->{CustomerCompanyObject}->CustomerCompanyGet(
            CustomerID => $Value,
        );
        $Value = $CustomerCompanyData{CustomerCompanyName};

        # alternative display string defined ?
        if ( $Param{DynamicFieldConfig}->{Config}->{AlternativeDisplay} ) {
            $Value = $Param{DynamicFieldConfig}->{Config}->{AlternativeDisplay};
            $Value =~ s{<(.+?)>}{$CustomerCompanyData{$1}}egx;
        }
        push @Values, $Value;
    }

    return \@Values;
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
