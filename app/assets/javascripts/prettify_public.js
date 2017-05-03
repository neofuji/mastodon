//= require prettify-all

(function() {
    function onLoad() {
        PR.prettyPrint();
    }

    if (window.addEventListener) {
        window.addEventListener("load", onLoad, false);
    } else if (window.attachEvent) {
        window.attachEvent("onload", onLoad);
    }
})();
