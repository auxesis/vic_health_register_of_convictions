Scraper for [vic.health's](https://www2.health.vic.gov.au/) [convictions register](https://www2.health.vic.gov.au/public-health/food-safety/convictions-register).

The convictions register lists details of businesses and individuals that have been found guilty by a court of a breach of the Victorian Food Act of 1984.

The Act requires that each conviction is to be included in the register for 12 consecutive months.

This scraper [runs on Morph](https://morph.io/auxesis/vic_health_register_of_convictions). To get started [see Morph's documentation](https://morph.io/documentation).

## Run the scraper locally

Clone and set up the scraper locally:

``` bash
git clone https://github.com/auxesis/vic_health_register_of_convictions
cd vic_health_register_of_convictions
bundle
```

Then run it:

``` bash
bundle exec ruby scraper.rb
```

## Why is there a custom certificate bundle?

Per the [Qualsys SSL Labs report](https://www.ssllabs.com/ssltest/analyze.html?d=www2.health.vic.gov.au), **the intermediate certificate is not sent by the server at www2.health.vic.gov.au**.

Browsers fetch the intermediate certificate, or have them bundled. Most programming languages do not.

Fetch the latest bundle (that includes the intermediate) by:

1. [Going to the GeoTrust page for the bundle](https://knowledge.geotrust.com/support/knowledge-base/index?page=content&actp=CROSSLINK&id=SO24877)
2. Copying the bundle into `bundle.pem` in the git repo

The scraper is configured to use `bundle.pem` as the Certificate Authority file for all HTTPS requests.
