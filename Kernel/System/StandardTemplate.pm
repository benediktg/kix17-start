# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::StandardTemplate;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Cache',
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Valid',
);

=head1 NAME

Kernel::System::StandardTemplate - std template lib

=head1 SYNOPSIS

All std template functions. E. g. to add std template or other functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $StandardTemplateObject = $Kernel::OM->Get('Kernel::System::StandardTemplate');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item StandardTemplateAdd()

add new std template

    my $ID = $StandardTemplateObject->StandardTemplateAdd(
        Name         => 'New Standard Template',
        Template     => 'Thank you for your email.',
        ContentType  => 'text/plain; charset=utf-8',
        TemplateType => 'Answer',                     # or 'Forward' or 'Create'
        ValidID      => 1,
        UserID       => 123,
    );

=cut

sub StandardTemplateAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Name ValidID Template ContentType UserID TemplateType)) {
        if ( !defined( $Param{$_} ) ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # check if a standard template with this name already exists
    if ( $Self->NameExistsCheck( Name => $Param{Name} ) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "A standard template with name '$Param{Name}' already exists!"
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # sql
    return if !$DBObject->Do(
        SQL  => <<'END',
INSERT INTO standard_template (name, valid_id, comments, text,
    content_type, create_time, create_by, change_time, change_by, template_type)
VALUES (?, ?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?, ?)
END
        Bind => [
            \$Param{Name},        \$Param{ValidID}, \$Param{Comment}, \$Param{Template},
            \$Param{ContentType}, \$Param{UserID},  \$Param{UserID},  \$Param{TemplateType},
        ],
    );

    return if !$DBObject->Prepare(
        SQL  => 'SELECT id FROM standard_template WHERE name = ? AND change_by = ?',
        Bind => [ \$Param{Name}, \$Param{UserID}, ],
    );

    my $ID;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $ID = $Row[0];
    }

    # clear queue cache, due to Queue <-> Template relations
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
        Type => 'Queue',
    );

    return $ID;
}

=item StandardTemplateGet()

get std template attributes

    my %StandardTemplate = $StandardTemplateObject->StandardTemplateGet(
        ID => 123,
    );

Returns:

    %StandardTemplate = (
        ID                  => '123',
        Name                => 'Simple remplate',
        Comment             => 'Some comment',
        Template            => 'Template content',
        ContentType         => 'text/plain',
        TemplateType        => 'Answer',
        ValidID             => '1',
        CreateTime          => '2010-04-07 15:41:15',
        CreateBy            => '321',
        ChangeTime          => '2010-04-07 15:59:45',
        ChangeBy            => '223',
    );

=cut

sub StandardTemplateGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need ID!'
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # sql
    return if !$DBObject->Prepare(
        SQL  => <<'END',
SELECT name, valid_id, comments, text, content_type, create_time, create_by,
    change_time, change_by ,template_type
FROM standard_template
WHERE id = ?
END
        Bind => [ \$Param{ID} ],
    );

    my %Data;
    while ( my @Data = $DBObject->FetchrowArray() ) {
        %Data = (
            ID           => $Param{ID},
            Name         => $Data[0],
            Comment      => $Data[2],
            Template     => $Data[3],
            ContentType  => $Data[4] || 'text/plain',
            ValidID      => $Data[1],
            CreateTime   => $Data[5],
            CreateBy     => $Data[6],
            ChangeTime   => $Data[7],
            ChangeBy     => $Data[8],
            TemplateType => $Data[9],
        );
    }

    return %Data;
}

=item StandardTemplateDelete()

delete a standard template

    $StandardTemplateObject->StandardTemplateDelete(
        ID => 123,
    );

=cut

sub StandardTemplateDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need ID!'
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # delete queue<->std template relation
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM queue_standard_template WHERE standard_template_id = ?',
        Bind => [ \$Param{ID} ],
    );

    # delete attachment<->std template relation
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM standard_template_attachment WHERE standard_template_id = ?',
        Bind => [ \$Param{ID} ],
    );

    # sql
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM standard_template WHERE id = ?',
        Bind => [ \$Param{ID} ],
    );

    # clear queue cache, due to Queue <-> Template relations
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
        Type => 'Queue',
    );

    return 1;
}

=item StandardTemplateUpdate()

update std template attributes

    $StandardTemplateObject->StandardTemplateUpdate(
        ID           => 123,
        Name         => 'New Standard Template',
        Template     => 'Thank you for your email.',
        ContentType  => 'text/plain; charset=utf-8',
        TemplateType => 'Answer',
        ValidID      => 1,
        UserID       => 123,
    );

=cut

sub StandardTemplateUpdate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(ID Name ValidID TemplateType ContentType UserID TemplateType)) {
        if ( !defined( $Param{$_} ) ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # check if a standard template with this name already exists
    if (
        $Self->NameExistsCheck(
            Name => $Param{Name},
            ID   => $Param{ID}
        )
    ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "A standard template with name '$Param{Name}' already exists!"
        );
        return;
    }

    # sql
    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => <<'END',
UPDATE standard_template
SET name = ?, text = ?, content_type = ?, comments = ?, valid_id = ?,
    change_time = current_timestamp, change_by = ?, template_type = ?
WHERE id = ?
END
        Bind => [
            \$Param{Name},    \$Param{Template}, \$Param{ContentType},  \$Param{Comment},
            \$Param{ValidID}, \$Param{UserID},   \$Param{TemplateType}, \$Param{ID},
        ],
    );

    # clear queue cache, due to Queue <-> Template relations
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
        Type => 'Queue',
    );

    return 1;
}

=item StandardTemplateLookup()

return the name or the std template id

    my $StandardTemplateName = $StandardTemplateObject->StandardTemplateLookup(
        StandardTemplateID => 123,
    );

    or

    my $StandardTemplateID = $StandardTemplateObject->StandardTemplateLookup(
        StandardTemplate => 'Std Template Name',
    );

=cut

sub StandardTemplateLookup {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{StandardTemplate} && !$Param{StandardTemplateID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got no StandardTemplate or StandardTemplateID!'
        );
        return;
    }

    # check if we ask the same request?
    if (
        $Param{StandardTemplateID}
        && $Self->{"StandardTemplateLookup$Param{StandardTemplateID}"}
    ) {
        return $Self->{"StandardTemplateLookup$Param{StandardTemplateID}"};
    }
    if ( $Param{StandardTemplate} && $Self->{"StandardTemplateLookup$Param{StandardTemplate}"} ) {
        return $Self->{"StandardTemplateLookup$Param{StandardTemplate}"};
    }

    # get data
    my $SQL;
    my $Suffix;
    my @Bind;
    if ( $Param{StandardTemplate} ) {
        $Suffix = 'StandardTemplateID';
        $SQL    = 'SELECT id FROM standard_template WHERE name = ?';
        @Bind   = ( \$Param{StandardTemplate} );
    }
    else {
        $Suffix = 'StandardTemplate';
        $SQL    = 'SELECT name FROM standard_template WHERE id = ?';
        @Bind   = ( \$Param{StandardTemplateID} );
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {

        # store result
        $Self->{"StandardTemplate$Suffix"} = $Row[0];
    }

    # check if data exists
    if ( !exists $Self->{"StandardTemplate$Suffix"} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Found no \$$Suffix!"
        );
        return;
    }

    return $Self->{"StandardTemplate$Suffix"};
}

=item StandardTemplateList()

get all valid std templatess

    my %StandardTemplates = $StandardTemplatesObject->StandardTemplateList();

Returns:
    %StandardTemplates = (
        1 => 'Some Name',
        2 => 'Some Name2',
        3 => 'Some Name3',
    );

get all std templates

    my %StandardTemplates = $StandardTemplateObject->StandardTemplateList(
        Valid => 0,
    );

Returns:
    %StandardTemplates = (
        1 => 'Some Name',
        2 => 'Some Name2',
    );

get std templates from a certain type
    my %StandardTemplates = $StandardTemplateObject->StandardTemplateList(
        Valid => 0,
        Type  => 'Answer',
    );

Returns:
    %StandardTemplates = (
        1 => 'Answer - Some Name',
    );

=cut

sub StandardTemplateList {
    my ( $Self, %Param ) = @_;

    my $Valid = 1;
    if ( defined $Param{Valid} && $Param{Valid} eq '0' ) {
        $Valid = 0;
    }

    my $SQL = 'SELECT id, name FROM standard_template';

    if ($Valid) {
        $SQL .= ' WHERE valid_id IN (' . join ', ',
            $Kernel::OM->Get('Kernel::System::Valid')->ValidIDsGet() . ')';
    }

    my @Bind;
    if ( defined $Param{Type} && $Param{Type} ne '' ) {
        if ($Valid) {
            $SQL .= ' AND';
        }
        else {
            $SQL .= ' WHERE';
        }
        $SQL .= ' template_type = ?';
        push @Bind, \$Param{Type};
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my %Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Data{ $Row[0] } = $Row[1];
    }

    return %Data;
}

=item NameExistsCheck()

    return 1 if another standard template with this name already exists

        $Exist = $StandardTemplateObject->NameExistsCheck(
            Name => 'Some::Template',
            ID => 1, # optional
        );

=cut

sub NameExistsCheck {
    my ( $Self, %Param ) = @_;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL  => 'SELECT id FROM standard_template WHERE name = ?',
        Bind => [ \$Param{Name} ],
    );

    # fetch the result
    my $Flag;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        if ( !$Param{ID} || $Param{ID} ne $Row[0] ) {
            $Flag = 1;
        }
    }
    if ($Flag) {
        return 1;
    }
    return 0;
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
