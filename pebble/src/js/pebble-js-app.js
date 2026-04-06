// PebbleKit JS bridge for Trio Pebble watchface
// Polls the local HTTP API server running in the Trio iOS app
// and forwards data to the Pebble watchapp via AppMessage.

var API_HOST = 'http://127.0.0.1:8080';
var POLL_INTERVAL_MS = 30000; // 30 seconds

// AppMessage keys - must match main.c #defines
var KEY_GLUCOSE = 0;
var KEY_TREND = 1;
var KEY_DELTA = 2;
var KEY_IOB = 3;
var KEY_COB = 4;
var KEY_LAST_LOOP = 5;
var KEY_GLUCOSE_STALE = 6;
var KEY_CMD_TYPE = 7;
var KEY_CMD_AMOUNT = 8;
var KEY_CMD_STATUS = 9;
var KEY_GRAPH_DATA = 10;
var KEY_GRAPH_COUNT = 11;
var KEY_LOOP_STATUS = 12;
var KEY_UNITS = 13;
var KEY_PUMP_STATUS = 14;
var KEY_RESERVOIR = 15;

function fetchData() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', API_HOST + '/api/all', true);
    xhr.timeout = 10000;

    xhr.onload = function () {
        if (xhr.status === 200) {
            try {
                var data = JSON.parse(xhr.responseText);
                sendDataToWatch(data);
            } catch (e) {
                console.log('Trio Pebble: JSON parse error: ' + e);
            }
        } else {
            console.log('Trio Pebble: HTTP error ' + xhr.status);
        }
    };

    xhr.onerror = function () {
        console.log('Trio Pebble: connection error (is Trio running?)');
    };

    xhr.ontimeout = function () {
        console.log('Trio Pebble: request timeout');
    };

    xhr.send();
}

function sendDataToWatch(data) {
    var msg = {};
    var cgm = data.cgm || {};
    var loop = data.loop || {};

    // Glucose value - parse from string
    var glucoseStr = cgm.glucose || '--';
    var glucoseVal = parseInt(glucoseStr, 10);
    if (!isNaN(glucoseVal)) {
        msg[KEY_GLUCOSE] = glucoseVal;
    }

    if (cgm.trend) msg[KEY_TREND] = cgm.trend.substring(0, 7);
    if (cgm.delta) msg[KEY_DELTA] = cgm.delta.substring(0, 15);
    if (loop.iob) msg[KEY_IOB] = loop.iob.substring(0, 15);
    if (loop.cob) msg[KEY_COB] = loop.cob.substring(0, 15);
    if (loop.lastLoopTime) msg[KEY_LAST_LOOP] = loop.lastLoopTime.substring(0, 15);
    if (cgm.units) msg[KEY_UNITS] = cgm.units;

    msg[KEY_GLUCOSE_STALE] = cgm.isStale ? 1 : 0;

    // Graph data - pack as byte array (little-endian uint16 per point)
    var history = loop.glucoseHistory || [];
    if (history.length > 0) {
        var count = Math.min(history.length, 36);
        var bytes = new Uint8Array(count * 2);
        for (var i = 0; i < count; i++) {
            var val = history[i];
            bytes[i * 2] = val & 0xFF;
            bytes[i * 2 + 1] = (val >> 8) & 0xFF;
        }
        msg[KEY_GRAPH_DATA] = Array.from ? Array.from(bytes) : Array.prototype.slice.call(bytes);
        msg[KEY_GRAPH_COUNT] = count;
    }

    Pebble.sendAppMessage(msg,
        function () { /* success */ },
        function (e) { console.log('Trio Pebble: AppMessage send failed: ' + JSON.stringify(e)); }
    );
}

function sendCommand(type, amount) {
    var endpoint = type === 1 ? '/api/bolus' : '/api/carbs';
    var body = type === 1
        ? JSON.stringify({ units: amount / 10.0 })
        : JSON.stringify({ grams: amount, absorptionHours: 3 });

    var xhr = new XMLHttpRequest();
    xhr.open('POST', API_HOST + endpoint, true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.timeout = 10000;

    xhr.onload = function () {
        try {
            var resp = JSON.parse(xhr.responseText);
            var statusMsg = resp.message || resp.status || 'sent';
            var msg = {};
            msg[KEY_CMD_STATUS] = statusMsg.substring(0, 63);
            Pebble.sendAppMessage(msg);
        } catch (e) {
            console.log('Trio Pebble: command response parse error');
        }
    };

    xhr.onerror = function () {
        var msg = {};
        msg[KEY_CMD_STATUS] = 'Connection error';
        Pebble.sendAppMessage(msg);
    };

    xhr.send(body);
}

// Handle messages from the Pebble watchapp
Pebble.addEventListener('appmessage', function (e) {
    var payload = e.payload;
    if (payload[KEY_CMD_TYPE] !== undefined && payload[KEY_CMD_AMOUNT] !== undefined) {
        sendCommand(payload[KEY_CMD_TYPE], payload[KEY_CMD_AMOUNT]);
    } else {
        fetchData();
    }
});

Pebble.addEventListener('ready', function () {
    console.log('Trio Pebble: JS bridge ready');
    fetchData();
    setInterval(fetchData, POLL_INTERVAL_MS);
});
