# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::Template::Provider;

use strict;
use warnings;

use base qw (Template::Provider);

use Scalar::Util qw();
use Template::Constants;

use Kernel::Output::Template::Document;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Cache',
    'Kernel::System::Encode',
    'Kernel::System::Log',
    'Kernel::System::Main',
);

## no critic qw(ControlStructures::ProhibitNegativeExpressionsInUnlessAndUntilConditions Subroutines::ProhibitUnusedPrivateSubroutines RegularExpressions::ProhibitComplexRegexes)

# Force the use of our own document class.
$Template::Provider::DOCUMENT = 'Kernel::Output::Template::Document';

=head1 NAME

Kernel::Output::Template::Provider - Template Toolkit custom provider

=head1 PUBLIC INTERFACE

=over 4

=cut

=item KIXInit()

performs some post-initialization and creates a bridget between Template::Toolkit
and KIX by adding the KIX objects to the Provider object. This method must be
called after instantiating the Provider object.

Please note that we only store a weak reference to the LayoutObject to avoid ring
references.

=cut

sub KIXInit {
    my ( $Self, %Param ) = @_;

    # Don't fetch LayoutObject via ObjectManager as there might be several instances involved
    #   at this point (for example in LinkObject there is an own LayoutObject to avoid block
    #   name collisions).
    $Self->{LayoutObject} = $Param{LayoutObject} || die "Got no LayoutObject!";

    #
    # Store a weak reference to the LayoutObject to avoid ring references.
    #   We need it for the filters.
    #
    Scalar::Util::weaken( $Self->{LayoutObject} );

    # define cache type
    $Self->{CacheType} = 'TemplateProvider';

    # caching can be disabled for debugging reasons
    $Self->{CachingEnabled} = $Kernel::OM->Get('Kernel::Config')->Get('Frontend::TemplateCache') // 1;

    # Pre-compute the list of not cacheable Templates. If a pre-output filter is
    #   registered for a particular or for all templates, the template cannot be
    #   cached any more.
    #
    $Self->{FilterElementPre} = $Kernel::OM->Get('Kernel::Config')->Get('Frontend::Output::FilterElementPre');

    my %UncacheableTemplates;

    my %FilterList = %{ $Self->{FilterElementPre} || {} };

    FILTER:
    for my $Filter ( sort keys %FilterList ) {

        # extract filter config
        my $FilterConfig = $FilterList{$Filter};

        next FILTER if !$FilterConfig;
        next FILTER if ref $FilterConfig ne 'HASH';

        # extract template list
        my %TemplateList = %{ $FilterConfig->{Templates} || {} };

        if ( !%TemplateList ) {

            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message =>
                    "Please add a template list to output filter $FilterConfig->{Module} to improve performance.",
            );

            next FILTER;
        }
        elsif ( $TemplateList{ALL} ) {

            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => <<"EOF",
$FilterConfig->{Module} wants to operate on ALL templates.
This will prohibit the templates from being cached and can therefore lead to serious performance issues.
EOF
            );

            next FILTER;
        }

        @UncacheableTemplates{ keys %TemplateList } = values %TemplateList;
    }

    # map filtered template names to real tt names (except 'ALL' placeholder)
    %UncacheableTemplates =
        map { $_ eq 'ALL' ? 'ALL' : $_ . '.tt' => $UncacheableTemplates{$_} }
        keys %UncacheableTemplates;

    $Self->{UncacheableTemplates} = \%UncacheableTemplates;

    return 1;
}

=item _fetch()

try to get a compiled version of a template from the CacheObject,
otherwise compile the template and return it.

Copied and slightly adapted from Template::Provider.

A note about caching: we have three levels of caching.

    1. we have an in-memory cache that stores the compiled Document objects (fastest).
    2. we store the parsed data in the CacheObject to be re-used in another request.
    3. for string templates, we have an in-memory cache in the parsing method _compile().
        It will return the already parsed object if it sees the same template content again.

=cut

sub _fetch {
    my ( $self, $name, $t_name ) = @_;
    my $stat_ttl = $self->{STAT_TTL};

    $self->debug("_fetch($name)") if $self->{DEBUG};

    my $TemplateIsCacheable = !$self->{UncacheableTemplates}->{ALL} && !$self->{UncacheableTemplates}->{$t_name};

    # Check in-memory template cache if we already had this template.
    $self->{_TemplateCache} //= {};

    if ( $TemplateIsCacheable && $self->{_TemplateCache}->{$name} ) {
        return $self->{_TemplateCache}->{$name};
    }

    # See if we already know the template is not found
    if ( $self->{NOTFOUND}->{$name} ) {
        return ( undef, Template::Constants::STATUS_DECLINED );
    }

    # Check if the template exists, is cacheable and if a cached version exists.
    if ( -e $name && $TemplateIsCacheable && $self->{CachingEnabled} ) {

        my $template_mtime = $self->_template_modified($name);
        my $CacheKey       = $self->_compiled_filename($name) . '::' . $template_mtime;

        # Is there an up-to-date compiled version in the cache?
        my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
            Type => $self->{CacheType},
            Key  => $CacheKey,
        );

        if ( ref $Cache ) {

            my $compiled_template = $Template::Provider::DOCUMENT->new($Cache);

            # Store in-memory and return the compiled template
            if ($compiled_template) {

                # Make sure template cache does not get too big
                if ( keys %{ $self->{_TemplateCache} } > 1000 ) {
                    $self->{_TemplateCache} = {};
                }

                $self->{_TemplateCache}->{$name} = $compiled_template;

                return $compiled_template;
            }

            # Problem loading compiled template: warn and continue to fetch source template
            warn( $self->error(), "\n" );
        }
    }

    # load template from source
    my ( $template, $error ) = $self->_load( $name, $t_name );

    if ($error) {

        # Template could not be fetched.  Add to the negative/notfound cache.
        $self->{NOTFOUND}->{$name} = time;
        return ( $template, $error );
    }

    # compile template source
    ( $template, $error ) = $self->_compile( $template, $self->_compiled_filename($name) );

    if ($error) {

        # return any compile time error
        return ( $template, $error );
    }

    if ($TemplateIsCacheable) {

        # Make sure template cache does not get too big
        if ( keys %{ $self->{_TemplateCache} } > 1000 ) {
            $self->{_TemplateCache} = {};
        }

        $self->{_TemplateCache}->{$name} = $template->{data};
    }

    return $template->{data};

}

=item _load()

calls our pre processor when loading a template.

Inherited from Template::Provider.

=cut

sub _load {
    my ( $Self, $Name, $Alias ) = @_;

    my @Result = $Self->SUPER::_load( $Name, $Alias );

    # If there was no error, pre-process our template
    if ( ref $Result[0] ) {

        $Result[0]->{text} = $Self->_PreProcessTemplateContent(
            Content      => $Result[0]->{text},
            TemplateFile => $Result[0]->{name},
        );
    }

    return @Result;
}

=item _compile()

compiles a .tt template into a Perl package and uses the CacheObject
to cache it.

Copied and slightly adapted from Template::Provider.

=cut

sub _compile {
    my ( $self, $data, $compfile ) = @_;
    my $text = $data->{text};
    my ( $parsedoc, $error );

    if ( $self->{DEBUG} ) {
        $self->debug(
            "_compile($data, ",
            defined $compfile ? $compfile : '<no compfile>', ')'
        );
    }

    # Check in-memory parser cache if we already had this template content
    $self->{_ParserCache} //= {};

    if ( $self->{_ParserCache}->{$text} ) {
        return $self->{_ParserCache}->{$text};
    }

    my $parser = $self->{PARSER}
        ||= Template::Config->parser( $self->{PARAMS} )
        || return ( Template::Config->error(), Template::Constants::STATUS_ERROR );

    # discard the template text - we don't need it any more
    delete $data->{text};

    # call parser to compile template into Perl code
    if ( $parsedoc = $parser->parse( $text, $data ) ) {

        $parsedoc->{METADATA} = {
            'name'    => $data->{name},
            'modtime' => $data->{time},
            %{ $parsedoc->{METADATA} },
        };

        # write the Perl code to the file $compfile, if defined
        if ($compfile) {
            my $CacheKey = $compfile . '::' . $data->{time};

            if ( $self->{CachingEnabled} ) {
                $Kernel::OM->Get('Kernel::System::Cache')->Set(
                    Type  => $self->{CacheType},
                    TTL   => 60 * 60 * 24,
                    Key   => $CacheKey,
                    Value => $parsedoc,
                );
            }
        }

        if ( $data->{data} = $Template::Provider::DOCUMENT->new($parsedoc) ) {

            # Make sure parser cache does not get too big
            if ( keys %{ $self->{_ParserCache} } > 1000 ) {
                $self->{_ParserCache} = {};
            }

            $self->{_ParserCache}->{$text} = $data;

            return $data;
        }
        $error = $Template::Document::ERROR;
    }
    else {
        $error = Template::Exception->new( 'parse', "$data->{ name } " . $parser->error() );
    }

    # return STATUS_ERROR, or STATUS_DECLINED if we're being tolerant
    return $self->{TOLERANT}
        ? ( undef, Template::Constants::STATUS_DECLINED )
        : ( $error, Template::Constants::STATUS_ERROR )
}

=item store()

inherited from Template::Provider. This function override just makes sure that the original
in-memory cache cannot be used.

=cut

sub store {
    my ( $Self, $Name, $Data ) = @_;

    return $Data;    # no-op
}

=item _PreProcessTemplateContent()

this is our template pre processor.

It handles some KIX specific tags like [% InsertTemplate("TemplateName.tt") %]
and also performs compile-time code injection (ChallengeToken element into forms).

Besides that, it also makes sure the template is treated as UTF8.

This is run at compile time. If a template is cached, this method does not have to be executed on it
any more.

=cut

sub _PreProcessTemplateContent {
    my ( $Self, %Param ) = @_;

    my $Content = $Param{Content};

    # Make sure the template is treated as utf8.
    $Kernel::OM->Get('Kernel::System::Encode')->EncodeInput( \$Content );

    my $TemplateFileWithoutTT = substr( $Param{TemplateFile}, 0, -3 );

    #
    # Include other templates into this one before parsing.
    # [% IncludeTemplate("DatePicker.tt") %]
    #
    my $ReplaceCounter = 0;
    my $Replaced;
    do {
        $Replaced = $Content =~ s{
            \[% -? \s* InsertTemplate \( \s* ['"]? (.*?) ['"]? \s* \) \s* -? %\]\n?
            }{
                # Load the template via the provider.
                # We'll use SUPER::load here because we don't need the preprocessing twice.
                my $TemplateContent = ($Self->SUPER::load($1))[0];
                $Kernel::OM->Get('Kernel::System::Encode')->EncodeInput(\$TemplateContent);

                # Remove commented lines already here because of problems when the InsertTemplate tag
                #   is not on the beginning of the line.
                $TemplateContent =~ s/^#.*\n//gm;
                $TemplateContent;
            }esmxg;

    } while ( $Replaced && ++$ReplaceCounter <= 100 );

    # pre putput filter handling
    if ( $Self->{FilterElementPre} && ref $Self->{FilterElementPre} eq 'HASH' ) {

        # extract filter list
        my %FilterList = %{ $Self->{FilterElementPre} };

        FILTER:
        for my $Filter ( sort keys %FilterList ) {

            # extract filter config
            my $FilterConfig = $FilterList{$Filter};

            next FILTER if !$FilterConfig;
            next FILTER if ref $FilterConfig ne 'HASH';

            # extract template list
            my %TemplateList = %{ $FilterConfig->{Templates} || {} };

            if ( !%TemplateList ) {

                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message =>
                        "Please add a template list to output filter $FilterConfig->{Module} to improve performance.",
                );

                next FILTER;
            }
            elsif ( $TemplateList{ALL} ) {

                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => <<"EOF",
$FilterConfig->{Module} wants to operate on ALL templates.
This will prohibit the templates from being cached and can therefore lead to serious performance issues.
EOF
                );

                next FILTER;
            }

            # only operate on real files
            next FILTER if !$Param{TemplateFile};

            # check template list
            my $Match = 0;
            for my $Template ( keys %TemplateList ) {
                if (
                    $TemplateList{$Template}
                    && $TemplateFileWithoutTT =~ m/$Template/
                ) {
                    $Match = 1;
                }
            }
            next FILTER if !$Match;

            # check filter construction
            next FILTER if !$Kernel::OM->Get('Kernel::System::Main')->Require( $FilterConfig->{Module} );

            # create new instance
            my $Object = $FilterConfig->{Module}->new(
                LayoutObject => $Self->{LayoutObject},
            );

            next FILTER if !$Object;

            # run output filter
            $Object->Run(
                %{$FilterConfig},
                Data         => \$Content,
                TemplateFile => $TemplateFileWithoutTT || '',
            );
        }
    }

    #
    # Remove DTL-style comments (lines starting with #)
    #
    $Content =~ s/^#.*\n//gm;

    #
    # Insert a BLOCK call into the template.
    # [% RenderBlock('b1') %]...[% END %]
    # becomes
    # [% PerformRenderBlock('b1') %][% BLOCK 'b1' %]...[% END %]
    # This is what we need: define the block and call it from the RenderBlock macro
    # to render it based on available block data from the frontend modules.
    #
    $Content =~ s{
        \[% -? \s* RenderBlockStart \( \s* ['"]? (.*?) ['"]? \s* \) \s* -? %\]
        }{[% PerformRenderBlock("$1") %][% BLOCK "$1" -%]}smxg;

    $Content =~ s{
        \[% -? \s* RenderBlockEnd \( \s* ['"]? (.*?) ['"]? \s* \) \s* -? %\]
        }{[% END -%]}smxg;

    #
    # Add challenge token field to all internal forms
    #
    # (?!...) is a negative look-ahead, so "not followed by https?:"
    # \K is a new feature in perl 5.10 which excludes anything prior
    # to it from being included in the match, which means the string
    # matched before it is not being replaced away.
    # performs better than including $1 in the substitution.
    #
    $Content =~ s{
            <form[^<>]+action="(?!https?:)[^"]*"[^<>]*>\K
        }{[% IF Env("UserChallengeToken") %]<input type="hidden" name="ChallengeToken" value="[% Env("UserChallengeToken") | html %]"/>[% END %][% IF Env("SessionID") && !Env("SessionIDCookie") %]<input type="hidden" name="[% Env("SessionName") %]" value="[% Env("SessionID") | html %]"/>[% END %]}smxig;

    return $Content;

}

=item MigrateDTLtoTT()

translates old DTL template content to Template::Toolkit syntax.

    my $TTCode = $ProviderObject->MigrateDTLtoTT( Content => $DTLCode );

If an error was found, this method will die(), so please use eval around it.

=cut

sub MigrateDTLtoTT {
    my ( $Self, %Param ) = @_;

    my $Content = $Param{Content};

    my $ID = "[a-zA-Z0-9:_\-]+";

    my $SafeArrrayAccess = sub {
        my $SafeID = shift;
        if ( $SafeID !~ m{^[a-zA-Z0-9_]+$}xms ) {
            return "item(\"$SafeID\")";
        }
        return $SafeID;
    };

    # $Quote $Config
    $Content =~ s{\$Quote{"\$Config{"($ID)"}"}}{[% Config("$1") | html %]}smxg;

    # $Quote $Env
    $Content =~ s{\$Quote{"\$Env{"($ID)"}"}}{[% Env("$1") | html %]}smxg;

    # $Quote $Data
    $Content =~ s{
            \$Quote{"\$Data{"($ID)"}"}
        }
        {
            '[% Data.' . $SafeArrrayAccess->($1) . ' | html %]'
        }esmxg;

    # $Quote with length
    $Content =~ s{
            \$Quote{"\$Data{"($ID)"}",\s*"(\d+)"}
        }
        {
            '[% Data.' . $SafeArrrayAccess->($1) . " | truncate($2) | html %]"
        }esmxg;

    # $Quote with dynamic length
    $Content =~ s{
            \$Quote{"\$Data{"($ID)"}",\s*"\$Q?Data{"($ID)"}"}
        }
        {
            '[% Data.' . $SafeArrrayAccess->($1) . ' | truncate(Data.' . $SafeArrrayAccess->($2) . ') | html %]'
        }esmxg;

    # $Quote with translated text and fixed length
    $Content =~ s{
            \$Quote{"\$Text{"\$Data{"($ID)"}"}",\s*"(\d+)"}
        }
        {
            '[% Data.' . $SafeArrrayAccess->($1) . " | Translate | truncate($2) | html %]"
        }esmxg;

    # $Quote with translated text and dynamic length
    $Content =~ s{
            \$Quote{"\$Text{"\$Data{"($ID)"}"}",\s*"\$Q?Data{"($ID)"}"}
        }
        {
            '[% Data.' . $SafeArrrayAccess->($1) . ' | Translate | truncate(Data.' . $SafeArrrayAccess->($2) . ') | html %]'
        }esmxg;

    my $MigrateTextTag = sub {
        my %MigrateParam = @_;
        my $Mode         = $MigrateParam{Mode};          # HTML or JSON
        my $Text         = $MigrateParam{Text};          # The translated text
        my $Dot          = $MigrateParam{Dot};           # Closing dot, sometimes outside of the Tag
        my $ParamString  = $MigrateParam{Parameters};    # Parameters to interpolate

        my $Result = '[% ';

        # Text contains a tag
        if ( $Text =~ m{\$TimeLong{"\$Q?Data{"($ID)"}"}}smx ) {
            $Result .= "Translate(Localize(Data." . $SafeArrrayAccess->($1) . ", \"TimeLong\")";
        }
        elsif ( $Text =~ m{\$TimeShort{"\$Q?Data{"($ID)"}"}}smx ) {
            $Result .= "Translate(Localize(Data." . $SafeArrrayAccess->($1) . ", \"TimeShort\")";
        }
        elsif ( $Text =~ m{\$Date{"\$Q?Data{"($ID)"}"}}smx ) {
            $Result .= "Translate(Localize(Data." . $SafeArrrayAccess->($1) . ", \"Date\")";
        }
        elsif ( $Text =~ m{\$Q?Data{"($ID)"}}smx ) {
            $Result .= "Translate(Data." . $SafeArrrayAccess->($1) . "";
        }
        elsif ( $Text =~ m{\$Config{"($ID)"}}smx ) {
            $Result .= "Translate(Config(\"$1\")";
        }
        elsif ( $Text =~ m{\$Q?Env{"($ID)"}}smx ) {
            $Result .= "Translate(Env(\"$1\")";
        }

        # Plain text
        else {
            $Text =~ s{"}{\\"}smxg;    # Escape " signs
            if ( $MigrateParam{Dot} ) {
                $Text .= $MigrateParam{Dot};
            }
            $Result .= "Translate(\"$Text\"";
        }

        my @Parameters = split m{,\s*}, $ParamString;

        PARAMETER:
        for my $Parameter (@Parameters) {
            next PARAMETER if ( !$Parameter );
            if ( $Parameter =~ m{\$TimeLong{"\$Q?Data{"($ID)"}"}}smx ) {
                $Result .= ", Localize(Data.$1, \"TimeLong\")";
            }
            elsif ( $Parameter =~ m{\$TimeShort{"\$Q?Data{"($ID)"}"}}smx ) {
                $Result .= ", Localize(Data.$1, \"TimeShort\")";
            }
            elsif ( $Parameter =~ m{\$Date{"\$Q?Data{"($ID)"}"}}smx ) {
                $Result .= ", Localize(Data.$1, \"Date\")";
            }
            elsif ( $Parameter =~ m{\$Q?Data{"($ID)"}}smx ) {
                $Result .= ", Data.$1";
            }
            elsif ( $Parameter =~ m{\$Config{"($ID)"}}smx ) {
                $Result .= ", Config(\"$1\")";
            }
            elsif ( $Parameter =~ m{\$Q?Env{"($ID)"}}smx ) {
                $Result .= ", Env(\"$1\")";
            }
            else {
                $Parameter =~ s{^"|"$}{}smxg;    # Remove enclosing ""
                $Parameter =~ s{"}{\\"}smxg;     # Escape " signs in the string
                $Result .= ", \"$Parameter\"";
            }
        }

        if ( $Mode eq 'JSON' ) {
            $Result .= ') | JSON %]';
        }
        else {
            $Result .= ') | html %]';
        }

        return $Result;
    };

    my $TextOrData = "";

    # $Text
    $Content =~ s{
            \$Text{
                ["']
                (
                    [^\$]+?
                    |\$Q?Data{\"$ID\"}
                    |\$Config{\"$ID\"}
                    |\$Q?Env{\"$ID\"}
                    |\$TimeLong{\"\$Q?Data{\"$ID\"}\"}
                    |\$TimeShort{\"\$Q?Data{\"$ID\"}\"}
                    |\$Date{\"\$Q?Data{\"$ID\"}\"}
                )
                ["']
                ((?:
                    ,\s*["']
                    (?:
                        [^\$]+?
                        |\$Q?Data{\"$ID\"}
                        |\$Config{\"$ID\"}
                        |\$Q?Env{\"$ID\"}
                        |\$TimeLong{\"\$Q?Data{\"$ID\"}\"}
                        |\$TimeShort{\"\$Q?Data{\"$ID\"}\"}
                        |\$Date{\"\$Q?Data{\"$ID\"}\"}
                    )
                ["'])*)
            }
        }
        {
            $MigrateTextTag->( Mode => 'HTML', Text => $1, Parameters => $2);
        }esmxg;

    # drop empty $Text
    $Content =~ s{ \$Text [{] "" [}] }{}xmsg;

    # $JSText
    $Content =~ s{
            ["']\$JSText{
                ["']
                (
                    [^\$]+?
                    |\$Q?Data{\"$ID\"}
                    |\$Config{\"$ID\"}
                    |\$Q?Env{\"$ID\"}
                    |\$TimeLong{\"\$Q?Data{\"$ID\"}\"}
                    |\$TimeShort{\"\$Q?Data{\"$ID\"}\"}
                    |\$Date{\"\$Q?Data{\"$ID\"}\"}
                )
                ["']
                ((?:
                    ,\s*["']
                    (?:
                        [^\$]+?
                        |\$Q?Data{\"$ID\"}
                        |\$Config{\"$ID\"}
                        |\$Q?Env{\"$ID\"}
                        |\$TimeLong{\"\$Q?Data{\"$ID\"}\"}
                        |\$TimeShort{\"\$Q?Data{\"$ID\"}\"}
                        |\$Date{\"\$Q?Data{\"$ID\"}\"}
                    )
                ["'])*)
            }
            (.?)["']
        }
        {
            $MigrateTextTag->( Mode => 'JSON', Text => $1, Parameters => $2, Dot => $3);
        }esmxg;

    # $TimeLong
    $Content =~ s{\$TimeLong{"\$Q?Data{"($ID)"}"}}{[% Data.$1 | Localize("TimeLong") %]}smxg;

    # $TimeShort
    $Content =~ s{\$TimeShort{"\$Q?Data{"($ID)"}"}}{[% Data.$1 | Localize("TimeShort") %]}smxg;

    # $Date
    $Content =~ s{\$Date{"\$Q?Data{"($ID)"}"}}{[% Data.$1 | Localize("Date") %]}smxg;

    # $QData with length
    $Content =~ s{
            \$QData{"($ID)",\s*"(\d+)"}
        }
        {
            "[% Data." . $SafeArrrayAccess->($1) . " | truncate($2) | html %]"
        }esmxg;

    # simple $QData
    $Content =~ s{
            \$QData{"($ID)"}
        }
        {
            "[% Data." . $SafeArrrayAccess->($1) . " | html %]"
        }esmxg;

    # $LQData
    $Content =~ s{
            \$LQData{"($ID)"}
        }
        {
            "[% Data." . $SafeArrrayAccess->($1) . " | uri %]"
        }esmxg;

    # simple $Data
    $Content =~ s{
            \$Data{"($ID)"}
        }
        {
            "[% Data." . $SafeArrrayAccess->($1) . " %]"
        }esmxg;

    # $Config
    $Content =~ s{\$Config{"($ID)"}}{[% Config("$1") %]}smxg;

    # $Env
    $Content =~ s{\$Env{"($ID)"}}{[% Env("$1") %]}smxg;

    # $QEnv
    $Content =~ s{\$QEnv{"($ID)"}}{[% Env("$1") | html %]}smxg;

    # dtl:block
    my %BlockSeen;
    $Content =~ s{<!--\s*dtl:block:($ID)\s*-->}{
        if ($BlockSeen{$1}++ % 2) {
            "[% RenderBlockEnd(\"$1\") %]";
        }
        else {
            "[% RenderBlockStart(\"$1\") %]";
        }
    }esmxg;

    # dtl:js_on_document_complete
    $Content =~ s{
            <!--\s*dtl:js_on_document_complete\s*-->(.*?)<!--\s*dtl:js_on_document_complete\s*-->
        }
        {
            "[% WRAPPER JSOnDocumentComplete %]${1}[% END %]";
        }esmxg;

    # dtl:js_on_document_complete_insert
    $Content
        =~ s{<!--\s*dtl:js_on_document_complete_placeholder\s*-->}{[% PROCESS JSOnDocumentCompleteInsert %]}smxg;

    # $Include
    $Content =~ s{\$Include{"($ID)"}}{[% InsertTemplate("$1.tt") %]}smxg;

    my ( $Counter, $ErrorMessage );
    LINE:
    for my $Line ( split /\n/, $Content ) {
        $Counter++;

        # Make sure there are no more DTL tags present in the code.
        if ( $Line =~ m{\$(?:L?Q?Data|Quote|Config|Q?Env|Time|Date|Text|JSText|Include)\{}xms ) {
            $ErrorMessage .= "Line $Counter: $Line\n";
        }
    }

    die $ErrorMessage if $ErrorMessage;

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
