#!/bin/bash
# This creates a test document directly via Firebase CLI
firebase firestore:write marketplace_listings/test-doc \
  --data '{"title":"Test Item","status":"active","price":10,"sellerId":"test","createdAt":"2024-01-01T00:00:00Z","tags":["test"],"condition":"good","type":"fixed_price"}' \
  --project swapdotz
