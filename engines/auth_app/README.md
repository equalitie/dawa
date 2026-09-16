# Auth App

This engine manages authentication, authorization, key management, account recovery.

## Features

* webauthn authentication
* authorization framework
* anonymous authentication via capabilities links
* optional integration with Raft::Encryption, if available:
  * encrypted session data is sql database
  * per-user encrypted vaults

## Configuration

`config/initializers/authenticated_app.rb`

``` ruby
Auth.forbidden_usernames = []  # array of strings to disallow as usernames
```

The format for forbidden_usernames is an array of strings, with globbing allowed. For example:

```
Auth.forbidden_usernames = [
  'root', 'admin*', 'security', 'web-master'
]
```

With the '*', this will match 'admin' but also 'administrator' and
'administration'. Look alike characters are automatically matched. For example,
'root' also matches 'r00t' and 'admin' also matches 'admln' and 'adm1n'. Finally, any
seperator character such as '-', '.', or '_' will match these separators or no
separator. So, 'web-master' matches 'webmaster', 'web.master', 'web_master', and 'web-master'.

## Integration

In your User class:

``` ruby
class User < ApplicationRecord
  include Auth::UserUsername
  include Auth::UserAuthentication

  ##
  ## These methods must be implemented:
  ##
   
  def self.find_by_login(login)
    User.where(username: login).take
  end

  def anon?
    false
  end

end
```

Include the module `Auth::SessionAuthentication` in your application controller.

```ruby
class ApplicationController < ActionController::Base
  include Auth::SessionAuthentication
end
```

By default, authentication and authorization is required. To make it optional:.

```ruby
class HomeController < ApplicationController
  optional_authentication
  optional_authorization
end
```

## Authorization

An exception will be thrown if the action does not at some point call `permit! {
true }`. This won't rollback any database changes, so `permit!` should be called
as before action or as the first line of a controller action.

```ruby
class AdminHomeController < ApplicationController

  def show
    permit! { current_user.admin? }
  end

  def index
    # will create an authorization exception because permit! has not been called
  end
end
```

If you want an authorization failure to rollback any database changes, use
`rollback: true`. This uses an `around_action` to wrap the entire action in a
transaction.

```ruby
class AdminHomeController < ApplicationController
  require_authorization rollback: true
  ...
end
```

Finally, mount the engine in your app's `routes.rb`:

```ruby
mount Auth::Engine => "/auth"
```

## Development

run tests:

```shell
rake app:db:prepare
rake test
```

view docs: `bundle exec yard server`

## The Future

TODO:

* remove time helper dependency
* remote util.js dependency
* Encrypt the join between user and session records, so that only when the user has
  unlocked their vault can they find the list of associated sessions.
* Instead of having a duplicate vault for each credential, replace with a single vault
  and each credential encrypts the key to unlock the vault.

This engine stores sessions in SQL. This has two benefits:

* No need to install an additional service like memcached or valkey.
* We can add custom fields like user_id for looking up all the sessions for a user.
  This is a good security feature so that we can show the users the sessions
  and terminate them all when the user logs out of any of them.

However, it has some problems. Discussed well here in how to optimize postgresql for storing sessions:
https://www.tech-couch.com/post/storing-sessions-or-cache-data-in-postgresql

Alternatively, perhaps we should just use memcached or valkey and then store a list of user => session ids in SQL.
