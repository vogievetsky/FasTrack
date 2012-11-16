fs = require('fs')
geoip = require('geoip-lite')
express = require('express')
useragent = require('express-useragent')
knox = require('knox')
app = express()
config = require('./config')

debug = false

if config.s3
  console.log 'Got S3 config'
  client = knox.createClient(config.s3)
  sendFilesToS3 = ->
    fs.readdir 'track', (err, files) ->
      if err
        console.log "ERROR: Can not read dir"
        return

      files.forEach (file) ->
        myFile = "track/" +  file
        s3File = "/" + (config.s3.path or '') + file
        console.log "Sending #{myFile} to S3"
        client.putFile myFile, s3File, (err, res) ->
          if err or res.statusCode isnt 200
            console.log("ERROR: Failed to upload #{myFile} to #{s3File} [#{res.statusCode} #{err}]")
            return

          fs.unlink myFile, (err) ->
            if err
              console.log("ERROR: Failed to delete #{myFile}")
              return

          return
        return
      return
    return
else
  console.log 'No S3 config'
  sendFilesToS3 = ->
    return

app.use(useragent.express())
app.use(express.compress())
app.disable('x-powered-by')
app.enable('trust proxy')

emptyGif = Buffer('\x47\x49\x46\x38\x39\x61\x01
\x00\x01\x00\xf0\x01\x00\xff\xff\xff\x00\x00\x00
\x21\xf9\x04\x01\x0a\x00\x00\x00\x2c\x00\x00\x00
\x00\x01\x00\x01\x00\x00\x02\x02\x44\x01\x00\x3b')

clientConfig = {
  h: config.host
}
script = """
(function(c) {
  try {
    var num = 0;
    var initTime = +new Date();
    window.flextrack = function(a) {
      if (Object.prototype.toString.call(a) != '[object Object]') return false;
      a.N_ = num++;
      a.P_ = document.location.pathname;
      a.S_ = +new Date() - initTime;
      a.R_ = document.referrer || 'Direct';
      var params = [];
      for (var k in a) params.push(encodeURIComponent(k) + "=" + encodeURIComponent(String(a[k])));
      var i = new Image();
      i.src = 'http://' + c.h + '/m.gif?' + params.join('&');
      return true;
    };
  } catch (e) {}
})(#{JSON.stringify(clientConfig)});
"""

events = []
currentFile = null

app.get '/script.js', (req, res) ->
  res.set('Content-Type', 'application/javascript')
  res.send(script)
  return

app.get '/m.gif', (req, res) ->
  if req.xhr
    res.send(500)
    return

  time = (new Date()).toISOString()

  # Flush events if needed
  file = 'track-' + time.replace(/:\d\d\.\d\d\dZ$/, '') + '.json'

  console.log "I have #{events.length} events for #{file}" if debug
  if events.length and currentFile isnt file
    fs.writeFile "track/#{currentFile}", events.join('\n'), (err) ->
      if err
        console.log 'ERROR: Could not write file', err
        return

      setTimeout(sendFilesToS3, 50)
      return
    events = []

  currentFile = file

  event = {}
  for k, v of req.query
    k = 'Number' if k is 'N_'
    k = 'Path' if k is 'P_'
    k = 'Referrer' if k is 'R_'
    k = 'SessionLength' if k is 'S_'
    event[k] = v

  # Make sure that Time overrides whatever is already named time
  event['Time'] = time

  ip = req.ip
  event['IP'] = ip

  geo = geoip.lookup(ip) or {
    country: 'NoIP'
    region: 'NoIP'
    city: 'NoIP'
    ll: [0, 0]
  }
  event['Country'] = geo.country or 'N/A'
  event['Region'] = geo.region or 'N/A'
  event['City'] = geo.city or 'N/A'
  event['Lat'] = geo.ll[0] #ll: [ 37.9746, -122.5616 ]
  event['Lon'] = geo.ll[1]

  ua = req.useragent
  event['Browser'] = ua.Browser or 'N/A'
  event['BrowserVersion'] = ua.Version or 'N/A'
  event['OS'] = ua.OS or 'N/A'
  event['Platform'] = ua.Platform or 'N/A'

  event['Language'] = req.acceptedLanguages[0] or 'N/A'

  event = JSON.stringify(event)
  #console.log "T: #{event}"
  events.push(event)

  res.set('Content-Type', 'image/gif')
  res.send(emptyGif)
  return

app.get '/ping', (req, res) ->
  res.send('pong')
  return

app.get '/geo', (req, res) ->
  ip = req.ip
  geo = geoip.lookup(ip) or {
    country: 'NoIP'
    region: 'NoIP'
    city: 'NoIP'
  }
  res.send """
  IP: #{ip}
  Country: #{geo.country}
  Region: #{geo.region}
  City: #{geo.city}
  IPs: [#{req.ips}]
  """
  return

console.log "Started server on port 9090"
app.listen(9090)
