// --
// Modified version of the work: Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
// based on the original work of:
// Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (AGPL). If you
// did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
// --

"use strict";

var OTRS = OTRS || {};
OTRS.Agent = OTRS.Agent || {};
OTRS.Agent.App = OTRS.Agent.App || {};

/**
 * @namespace
 * @exports TargetNS as OTRS.Agent.App.Dashboard
 * @description
 *      This namespace contains the special module functions for the Dashboard.
 */
OTRS.Agent.App.Dashboard = (function (TargetNS) {
    /**
     * @function
     * @return nothing
     *      This function initializes the special module functions
     */
    TargetNS.Init = function () {
        OTRS.UI.DnD.Sortable(
            $(".SidebarColumn"),
            {
                Handle: '.Header h2',
                Items: '.CanDrag',
                Placeholder: 'DropPlaceholder',
                Tolerance: 'pointer',
                Distance: 15,
                Opacity: 0.6
            }
        );

        OTRS.UI.DnD.Sortable(
            $(".ContentColumn"),
            {
                Handle: '.Header h2',
                Items: '.CanDrag',
                Placeholder: 'DropPlaceholder',
                Tolerance: 'pointer',
                Distance: 15,
                Opacity: 0.6
            }
        );
    };

    /**
     * @function
     * @return nothing
     *      This function binds a click event on an html element to update the preferences of the given dahsboard widget
     * @param {jQueryObject} $ClickedElement The jQuery object of the element(s) that get the event listener
     * @param {string} ElementID The ID of the element whose content should be updated with the server answer
     * @param {jQueryObject} $Form The jQuery object of the form with the data for the server request
     */
    TargetNS.RegisterUpdatePreferences = function ($ClickedElement, ElementID, $Form) {
        if (isJQueryObject($ClickedElement) && $ClickedElement.length) {
            $ClickedElement.click(function () {
                var URL = OTRS.Config.Get('Baselink') + OTRS.AJAX.SerializeForm($Form);
                OTRS.AJAX.ContentUpdate($('#' + ElementID), URL, function () {
                    OTRS.UI.ToggleTwoContainer($('#' + ElementID + '-setting'), $('#' + ElementID));
                    OTRS.UI.Table.InitCSSPseudoClasses();
                });
                return false;
            });
        }
    };

    return TargetNS;
}(OTRS.Agent.App.Dashboard || {}));