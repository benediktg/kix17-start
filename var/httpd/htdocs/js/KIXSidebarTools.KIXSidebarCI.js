// --
// Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file LICENSE for license information (AGPL). If you
// did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
// --

"use strict";

var KIXSidebarTools = KIXSidebarTools || {};

/**
 * @namespace
 * @exports TargetNS as KIXSidebarTools.KIXSidebarCI
 * @description
 *      This namespace contains the special module functions for the CI search.
 */
KIXSidebarTools.KIXSidebarCI = (function (TargetNS) {

    TargetNS.ChangeCheckbox = function (Element, ObjectID, LinkMode, LinkType) {
        if ( !Core.Debug.CheckDependency('KIXSidebarTools', 'KIXSidebarTools.LinkObject2Ticket', 'KIXSidebarTools.LinkObject2Ticket') ) {
            return;
        }
        if ( !Core.Debug.CheckDependency('KIXSidebarTools', 'KIXSidebarTools.NoActionWithoutSelection', 'KIXSidebarTools.NoActionWithoutSelection') ) {
            return;
        }
        KIXSidebarTools.LinkObject2Ticket('ITSMConfigItem', Element.val(), ObjectID, LinkMode, LinkType, Element.prop('checked'));
        KIXSidebarTools.NoActionWithoutSelection();
    }

    return TargetNS;
}(KIXSidebarTools.KIXSidebarCI || {}));
