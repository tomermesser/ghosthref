const fs = require('fs');
const robotsParser = require('robots-parser');

// Mounted from outside the image, so editing robots.txt needs no rebuild.
const ROBOTS_TXT_PATH = process.env.ROBOTS_TXT_PATH || '/config/robots.txt';

// robots-parser needs a fake URL to check paths against.
const BASE_URL = 'https://site.internal';

let robots;

function load() {
  const contents = fs.readFileSync(ROBOTS_TXT_PATH, 'utf8');
  robots = robotsParser(`${BASE_URL}/robots.txt`, contents);
  console.log(`[robots] loaded ${ROBOTS_TXT_PATH}`);
}

function isDisallowed(path, userAgent) {
  return robots.isDisallowed(`${BASE_URL}${path}`, userAgent) === true;
}

module.exports = { load, isDisallowed };
