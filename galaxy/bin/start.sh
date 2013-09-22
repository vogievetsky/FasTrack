#!/bin/bash

. conf/environment

cp asset/geo-data/* node_modules/geoip-lite/data
exec node tracker.js
