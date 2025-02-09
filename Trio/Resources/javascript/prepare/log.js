var console = {
    log: function(...args) { _consoleLog(args); },
    error: function(...args) { _consoleLog(args); }
};
var printLog = function(...args) { console.log(args); };
var process = { stderr: { write: printLog } };
