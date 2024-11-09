#!/bin/bash
curl -d "[{\"action\":\"fetchRatings\", \"scope\":{\"name\":\"all\"}}]" -H "Content-Type: application/json" -H "api-key: tmmApiKeyHere" -X POST http://tmm.ip.here:port/api/tvshow