#!/bin/bash
curl -d "[{\"action\":\"update\", \"scope\":{\"name\":\"all\"}},{\"action\":\"scrape\", \"scope\":{\"name\":\"new\"}}]" -H "Content-Type: application/json" -H "api-key: tmmApiKeyHere" -X POST http://tmm.ip.here:port/api/tvshow
curl -d "[{\"action\":\"scrape\", \"scope\":{\"name\":\"unscraped\"}}]" -H "Content-Type: application/json" -H "api-key: tmmApiKeyHere" -X POST http://tmm.ip.here:port/api/tvshow
