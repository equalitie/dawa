# bootstrap still uses @import, which is deprecated.
# until it is upgraded to support @use, we don't want to see
# those warnings.
Rails.application.config.dartsass.build_options << "--quiet-deps"
