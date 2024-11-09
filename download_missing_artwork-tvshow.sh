#!/bin/bash
curl -d "[{\"action\":\"downloadMissingArtwork\", \"scope\":{\"name\":\"all\"}}]" -H "Content-Type: application/json" -H "api-key: tmmApiKeyHere" -X POST http://tmm.ip.here:port/api/tvshow
