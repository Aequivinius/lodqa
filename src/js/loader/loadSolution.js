var EventEmitter = require('events').EventEmitter,
  _ = require('lodash');

module.exports = function() {
  var emitter = new EventEmitter,
    openConnection = function(pathname, config_url) {
      var ws_url = 'ws://' + location.host + pathname + '?config=' + config_url;
      console.log(ws_url);
      var ws = new WebSocket('ws://' + location.host + pathname + '?config=' + config_url)

      ws.onopen = function() {
        emitter.emit('ws_open');
      };
      ws.onclose = function() {
        emitter.emit('ws_close');
      };
      ws.onmessage = function(m) {
        if (m.data === 'start') return;

        var jsondata = JSON.parse(m.data);

        ['anchored_pgp', 'sparql', 'solution', 'parse_rendering']
        .forEach(function(event) {
          if (jsondata.hasOwnProperty(event)) {
            emitter.emit(event, jsondata[event]);
          }
        });
      };

      return ws;
    };

  return _.extend(emitter, {
    beginSearch: function(pgp, mappings, pathname, config_url) {
      var ws = openConnection(pathname, config_url);
      emitter.once('ws_open', function() {
        ws.send(JSON.stringify({
          pgp: pgp,
          mappings: mappings
        }))
      });
    }
  });
};
