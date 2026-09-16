# Configuration Magic for Ruby on Rails

This simple gem tries to make it easy to configure a Ruby on Rails application.

Use multiple YAML files, with inheritance.

Override any configuration value with an environment variable. E.g. `SITE_URL`
environment variable will override `site_url` definition in the yaml file.

May define metadata on variable via like so:

```yaml
variables:
  variable_name: TYPE [required]
  site_url: url required
  site_name: string
  
development:
  site_url: "My Dev Site"
```

## Usage

`Conf.load` will load the files specified in order, later files overriding the earlier files.

If you want to be able to use `Conf` everywhere, put it very early in `config/application.rb`.

`config/application.rb`:
    require 'conf'
    Conf.load(
      File.expand_path('../defaults.yml', __FILE__),
      File.expand_path('../config.yml', __FILE__)
    )
