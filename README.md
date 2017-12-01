# catalyst-pull-reserves

Pulls Horizon print reserve information into Catalyst database.

This is a one file script which is run as a cron.
It uses JRuby to connect to he SyBase using the JDBC driver. 

# deployment

```bash
bundle install --path=vendor/bundle
bundle exec ruby pull_reserves.rb

License
-------

[CC0](LICENSE)

