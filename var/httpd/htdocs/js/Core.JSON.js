// --
// Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
// based on the original work of:
// Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file LICENSE for license information (AGPL). If you
// did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
// --

"use strict";

var Core = Core || {};

/**
 * @namespace Core.JSON
 * @memberof Core
 * @author OTRS AG
 * @description
 *      Contains the code for the JSON functions.
 */
Core.JSON = (function (TargetNS) {

    // Some old browsers (e.g. IE7) don't have native JSON support. Such browsers will
    // let you see a javascript error message instead of the 'old browser' warning box.
    // Therefore we do the dependency check silent in this case.
    if (!Core.Debug.CheckDependency('Core.JSON', 'JSON.parse', 'JSON parser', true)) {
        // KIX4OTRS-capeIT
        // return;
        // check with top prefix for IE8 iframes (i.e. CI Graph)
        if (!Core.Debug.CheckDependency('Core.JSON', 'top.JSON.parse', 'JSON parser', true)) {
            return false;
        }
        else {
            JSON = top.JSON;
        }
        // EO KIX4OTRS-capeIT
    }

    /**
     * @name Parse
     * @memberof Core.JSON
     * @function
     * @returns {Object} The parsed JSON object.
     * @param {String} JSONString - The string which should be parsed.
     * @description
     *      This function parses a JSON String.
     */
    TargetNS.Parse = function (JSONString) {
        var JSONObject;

        try {
            JSONObject = JSON.parse(JSONString);
        }
        catch (e) {
            JSONObject = {};
        }

        return JSONObject;
    };

    /**
     * @name Stringify
     * @memberof Core.JSON
     * @function
     * @returns {String} The stringified JSON object.
     * @param {Object} JSONObject - The object which should be stringified.
     * @description
     *      This function stringifies a given JavaScript object.
     */
    TargetNS.Stringify = function (JSONObject) {
        var JSONString;

        try {
            JSONString = JSON.stringify(JSONObject);
        }
        catch (e) {
            JSONString = "";
        }

        return JSONString;
    };

    return TargetNS;
}(Core.JSON || {}));
