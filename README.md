
# Rift

#### Healing the rift between Elixir and Thrift.

Thrift's erlang implementation isn't very pleasant to use in Elixir. It prefers records to maps, making pattern matching difficult. Rift fixes this.

Rift Provides two modules, `Rift.Struct` and `Rift.Server` which will help you manage this impedence mismatch.


## Elixir style structs with `Rift.Struct`

`Rift.Struct` provides functionality for converting Thrift types into Elixir structs.

You tell `Rift.Struct` about your Erlang Thrift modules and which structs you would like to import. It then looks at the thrift files, parses their metadata and builds Elixir structs for you. It also creates `to_elixir` and `to_erlang` functions that will handle converting Erlang records into Elixir structs and vice versa.

Assuming you have a Thrift module called `pinterest_types` in your `src` directory:

```elixir
  defmodule Structs do
    use Rift.Struct, pinterest_types: [:User, :Pin, :Board]
  end
```

Then you can do the following:

```elixir
user = Structs.User.new(firstName: "Stinky", lastName: "Stinkman")
user_tuple = Structs.to_erlang(user)
> {:User, "Stinky", "Stinkman"}

Structs.to_elixir(user_tuple)
> %Structs.User{firstName: "Stinky", lastName: "Stinkman"}

```

...but you'll rarely use the Struct module alone. Instead, you'll use the `Rift.Client` or `Rift.Server` modules.


## Generating Servers with `Rift.Server`

`Rift.Server` assumes you have a module that has a bunch of handler functions in it. When a thrift RPC is called, your parameters will be converted into Elixir structs and then passed in to one of your handler functions. Let's assume you have the following thrift defined:

```thrift
enum UserState {
  ACTIVE,
  INACTIVE,
  BANNED;
}

struct User {
  1: string username,
  2: string firstName,
  3: string lastName;
}

struct UserAndState {
  1: User user,
  2: UserState state;
}

service PinterestRegister {
  User register(1: string firstName, 2: string lastName);
  bool isRegistered(1: User user);
  UserAndState getState(1: string username);
}
```

You can set it up like this:


```elixir
defmodule Server do
    use Rift.Server, service: :pinterest_thrift,
    structs: Data,
    functions: [register: &ThriftHandlers.register/3,
                isRegistered: &ThriftHandlers.is_registered/1,
                getState: &ThriftHandlers.get_state/1
    ],

    server: {:thrift_socket_server,
             port: 2112,
             framed: true,
             max: 10_000,
             socket_opts: [
                     recv_timeout: 3000,
                     keepalive: true]
            }
  end

defmodule ThriftHandlers do
  callback(:after_to_elixir, us=%Data.UserState{}) do
    state_atom = case us.state do
      1 -> :active
      2 -> :inactive
      3 -> :banned
      other -> other
    end
    %Data.UserState{us | state: state_atom}
  end

  callback(:after_to_erlang, {:UserAndstate, user, state}) do
    state_int = case state do
      :active -> 1
      :inactive -> 2
      :banned -> 3
      other -> other
    end
    {:UserAndState, user, state_int}
  end

  def register(username, first_name, last_name) do
     # registration logic. Return a new user
     Data.User.new(username: username, firstName: "Stinky", lastName: "Stinkman")
  end

  def is_registered(user=%Data.User{}) do
     true
  end

  def get_state(username) do
     user = Models.User.fetch(username)
     Data.UserState.new(user: user, state: :active)
  end

end
```

The server is doing a bunch of work for you. It's investigating your thrift files and figuring out which structs need to be imported by looking at the parameters, exceptions and return values. It then makes a module that imports your structs (`Data` in this case) and builds code for the thrift server that takes an incoming thrift request, converts its parameters into Elixir representations and then calls your handler. Notice how the handlers in ThriftHandlers take structs as arguments and return structs. That's what Rift gets you.

These handler functions also process the values your code returns and hands them back to thrift.

The above also features some callbacks that massage data to be more Elixir friendly. Due to the way thrift enums are handled by the erlang generator, there's no way for Rift to convert them into a friendly structure for you, so they need to be handled manually. The callbacks above demonstrate converting from ints to atoms. The callbacks allow pattern matching and will be invoked whenever a tuple is converted into an Elixir struct or an Elixir struct is converted into a tuple.

The server is configured in the server block. The first element of the tuple is the module of the server you wish to instantiate. The second element is a Keyword list of configuration options for the server. You cannot set the :name, :handler or :service params. The name and handler are set to the current module. The service is given as the thrift_module option.
