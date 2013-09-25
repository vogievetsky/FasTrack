geoip = require('geoip-lite')
https = require('https')
express = require('express')
useragent = require('express-useragent')
app = express()

languageLookup = require('./language')

config = require('./config')

version = '1.1.2'
debug = false

events = []
numReceivedEvents = 0
numSentEvents = 0
numBadKafkaPosts = 0

eventTrail = []

if config.kafka
  console.log 'Got kafka config'
  sending = false
  lastSend = new Date()
  sendEvents = ->
    return if sending
    return unless events.length
    now = new Date()
    return if events.length < 1000 and now - lastSend < 1000

    sending = true
    lastSend = now
    eventsToSend = events
    events = []

    req = https.request {
      method: 'POST'
      host: config.kafka.host
      port: config.kafka.port or 443
      path: config.kafka.path
      auth: config.kafka.username + ':' + config.kafka.password
    }, (res) ->
      if 200 <= res.statusCode < 300
        numSentEvents += eventsToSend.length
      else
        numBadKafkaPosts++
        console.log('----------------------------------------------')
        console.log('STATUS: ' + res.statusCode)
        console.log('HEADERS: ' +  JSON.stringify(res.headers))

      # chunks = []
      # res.on 'data', (chunk) ->
      #   chunks.push(chunk)
      #   return

      # res.on 'close', (err) ->
      #   callback({
      #     error: 'close'
      #     message: err
      #   })
      #   return

      # res.on 'end', ->
      #   console.log  chunks.join('')

      sending = false
      return

    req.on 'error', (e) ->
      console.log('problem with request: ' + e.message);

    # write data to request body
    for event in eventsToSend
      eventStr = JSON.stringify(event)
      console.log eventStr if debug
      req.write(eventStr + '\n')

    req.end()
    return

else
  console.log 'No kafka config'
  sendEvents = ->
    for event in events
      console.log('Event:', JSON.stringify(event))
    events = []
    return

setInterval(sendEvents, 200)

app.use(useragent.express())
app.use(express.compress())
app.disable('x-powered-by')
app.enable('trust proxy')

emptyGif = Buffer('\x47\x49\x46\x38\x39\x61\x01
\x00\x01\x00\xf0\x01\x00\xff\xff\xff\x00\x00\x00
\x21\xf9\x04\x01\x0a\x00\x00\x00\x2c\x00\x00\x00
\x00\x01\x00\x01\x00\x00\x02\x02\x44\x01\x00\x3b')

script = """
(function(w,h) {
  try {
    var session = 'S' + Math.random().toFixed(8).substring(2);
    var num = 0;
    var now = new Date();
    var initTime = +now;
    var tzm = String(now).match(/\\((\\w+)\\)/);
    var sx = (window.pageXOffset !== undefined) ? window.pageXOffset : (document.documentElement || document.body.parentNode || document.body).scrollLeft;
    var sy = (window.pageYOffset !== undefined) ? window.pageYOffset : (document.documentElement || document.body.parentNode || document.body).scrollTop;
    w.fastrack = function(a) {
      if (Object.prototype.toString.call(a) != '[object Object]') return false;

      a.S = session;
      a.N = num++;
      a.P = document.location.href;
      a.L = +new Date() - initTime;
      a.F = w.document.referrer || 'Direct';
      a.C = screen.width + 'x' + screen.height;
      a.R = sx + 'x' + sy;
      a.O = now.getTimezoneOffset();
      a.Z = (tzm && tzm.length === 2) ? tzm[1] : 'N/A';

      if ('innerWidth' in window) {
        a.W = w.innerWidth + 'x' + w.innerHeight;
      } else {
        var e = w.document.documentElement || w.document.body;
        a.W = w.clientWidth + 'x' + w.clientHeight;
      }
      var params = [];
      for (var k in a) params.push(encodeURIComponent(k) + "=" + encodeURIComponent(String(a[k])));
      var i = new Image();
      i.src = 'http://' + h + '/m.gif?' + params.join('&');
      return true;
    };
  }catch(e){}
})(window,#{JSON.stringify(config.host)});
"""

app.get '/script.js', (req, res) ->
  res.set('Content-Type', 'application/javascript')
  res.send(script)
  return

app.get '/m.gif', (req, res) ->
  if req.xhr
    res.send(500)
    return

  event = {}
  for own k, v of req.query
    k = 'session' if k is 'S'
    k = 'number' if k is 'N'
    k = 'path' if k is 'P'
    k = 'referrer' if k is 'F'
    k = 'window' if k is 'W'
    k = 'screen' if k is 'C'
    k = 'timezone' if k is 'Z'
    k = 'timezone_offset' if k is 'O'
    k = 'session_length' if k is 'L'
    k = 'scroll' if k is 'R'
    event[k] = v

  # Make sure that these overrides whatever is already named time
  event['tracker_version'] = version
  event['timestamp'] = (new Date()).toISOString()

  if event['referrer']
    if event['referrer'] is 'Direct'
      event['referrer_host'] = 'Direct'
    else
      m = event['referrer'].match(/https?:\/\/([^\/]+)(?:\/|$)/)
      if m
        event['referrer_host'] = m[1]
      else
        event['referrer_host'] = 'Unmatched'

  ip = req.ip
  event['ip'] = ip

  geo = geoip.lookup(ip) or {
    country: 'NoGeo'
    region: 'NoGeo'
    city: 'NoGeo'
    ll: ['', '']
  }
  event['country'] = geo.country or 'N/A'
  event['region'] = geo.region or 'N/A'
  event['city'] = geo.city or 'N/A'
  event['lat'] = geo.ll[0] #ll: [ 37.9746, -122.5616 ]
  event['lon'] = geo.ll[1]

  ua = req.useragent
  event['browser'] = ua.Browser or 'N/A'
  event['browser_version'] = ua.Version or 'N/A'
  event['os'] = ua.OS or 'N/A'
  event['platform'] = ua.Platform or 'N/A'

  languageCode = req.acceptedLanguages[0]
  if languageCode
    language = languageLookup(languageCode)
    language = "Unknown (#{languageCode})" unless language
  else
    language = 'N/A'
  event['language'] = language

  events.push(event)
  eventTrail.unshift(event)
  eventTrail.pop() while eventTrail.length > 10
  numReceivedEvents++

  res.set('Content-Type', 'image/gif')
  res.send(emptyGif)
  return

app.get '/health', (req, res) ->
  res.set('Content-Type', 'text/plain')
  res.send('I feel fine')
  return

app.get '/ping', (req, res) ->
  res.set('Content-Type', 'text/plain')
  res.send('pong')
  return

app.get '/geo', (req, res) ->
  ip = req.ip
  geo = geoip.lookup(ip) or {
    country: 'NoGeo'
    region: 'NoGeo'
    city: 'NoGeo'
  }
  ret = """
  Your info:
    IP: #{ip}
    Country: #{geo.country}
    Region: #{geo.region}
    City: #{geo.city}
  """

  ip = '173.247.199.2' # MMX IP :-)
  geo = geoip.lookup(ip) or {
    country: 'NoGeo'
    region: 'NoGeo'
    city: 'NoGeo'
  }
  ret += '\n\n' + """
  Test info:
    IP: #{ip}
    Country: #{geo.country}
    Region: #{geo.region}
    City: #{geo.city}
  """

  res.set('Content-Type', 'text/plain')
  res.send(ret)
  return

startTime = new Date()
app.get '/stats', (req, res) ->
  uptimeSeconds = Math.floor((Date.now() - startTime.valueOf()) / 1000)
  uptimeMinutes = Math.floor(uptimeSeconds / 60); uptimeSeconds = uptimeSeconds % 60
  uptimeHours =   Math.floor(uptimeMinutes / 60); uptimeMinutes = uptimeMinutes % 60
  uptimeDays =    Math.floor(uptimeHours / 24);   uptimeHours = uptimeHours % 24

  eventTrailStr = eventTrail.map((event) -> JSON.stringify(event, null, 2)).join('\n\n') or '<empty>'

  res.set('Content-Type', 'text/plain')
  res.send """
  FasTrack version #{version}

  Stats:
    Uptime: #{uptimeDays}D #{uptimeHours}H #{uptimeMinutes}M #{uptimeSeconds}S  (since: #{startTime.toISOString()})
    Number of events received: #{numReceivedEvents}
    Number of events sent:     #{numSentEvents}
    Number of post errors:     #{numBadKafkaPosts}

  Event trail (last 10 events):

  #{eventTrailStr}
  """
  return

console.log "FasTrack started server on port 9090"
app.listen(9090)
