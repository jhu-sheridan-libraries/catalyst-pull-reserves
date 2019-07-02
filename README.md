# catalyst-pull-reserves

Pulls Horizon print reserve information into Catalyst database.

This is a one file script which is run as a cron.
It uses JRuby to connect to the database using the JDBC driver.

## Set up

### Mac and JEnv

It relies on JRuby which requires Java. To use jenv to manage java version, first set the java version

```
jenv local 1.8
```

### Install and Manage JRuby

Install jruby
```
ruby-install jruby-9.1.16.0
exec $SHELL
```

Use chruby to manage jruby
```
chruby jruby 9.1.16.0
```

To set the version of jruby and enable auto-switching by chruby

```
echo "jruby-9.1.16.0" > .ruby-version
```

### Install gems

```bash
bundle install --path=vendor/bundle
bundle exec ruby pull_reserves.rb
```

License
-------

[CC0](LICENSE)
