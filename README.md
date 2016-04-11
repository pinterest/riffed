# Riffed

![Version](https://img.shields.io/github/tag/pinterest/riffed.svg)
[![Build Status](https://travis-ci.org/pinterest/riffed.svg?branch=master)](https://travis-ci.org/pinterest/riffed)
[![Coverage Status](https://coveralls.io/repos/pinterest/riffed/badge.svg?branch=master&service=github)](https://coveralls.io/github/pinterest/riffed?branch=master)
![Issues](https://img.shields.io/github/issues/pinterest/riffed.svg)
![License](https://img.shields.io/badge/license-Apache%202-blue.svg)

### Healing the rift between Elixir and Thrift.

Thrift's Erlang implementation isn't very pleasant to use in Elixir. It prefers records to structs, littering your code with tuples. It swallows enumerations you've defined, banishing them to the realm of wind and ghosts. It requires that you write a bunch of boilerplate handler code, and client code that's not very Elixir-y. Riffed fixes this.


## Getting Started

For a detailed guide on how to get started with Riffed, and creating your first Riffed server and client, see the [Getting Started Guide](https://github.com/pinterest/riffed/blob/master/doc/GettingStarted.md). For a general summary of some of the features Riffed provides, continue reading.

You can also generate Riffed documentation by running `mix docs`.

Riffed Provides three modules, `Riffed.Struct`, `Riffed.Client`, and `Riffed.Server` which will help you manage this impedence mismatch.


## Elixir-style structs with `Riffed.Struct`

`Riffed.Struct` provides functionality for converting Thrift types into Elixir structs.

You tell `Riffed.Struct` about your Erlang Thrift modules and which structs you would like to import. It then looks at the thrift files, parses their metadata and builds Elixir structs for you. It also creates `to_elixir` and `to_erlang` functions that will handle converting Erlang records into Elixir structs and vice versa.

Assuming you have a Thrift module called `pinterest_types` in your `src` directory:

```elixir
defmodule Structs do
  use Riffed.Struct, pinterest_types: :auto
end
```

Riffed will then automatically import all the structs in the `pinterest_types` module.

Then you can do the following:

```elixir
iex> user = Structs.User.new(firstName: "Stinky", lastName: "Stinkman")
iex> user_tuple = Structs.to_erlang(user, {:pinterest_types, :User}
{:User, "Stinky", "Stinkman"}

iex> Structs.to_elixir(user_tuple)
%Structs.User{firstName: "Stinky", lastName: "Stinkman"}
```

If you prefer to control which structs are imported, you can specify them like this:

```elixir
defmodule Structs do
  use Riffed.Struct, pinterest_types: [:User, :Board, :Pin]
end

```
In the above case, only the User, Pin and Board structs will be imported by Riffed. 


Unless you have extremely complex thrift definitions, you'll rarely use the Struct module directly. Instead, you'll use the `Riffed.Client` or `Riffed.Server` modules.

If your Thrift structs define default values for fields, these will be preserved in Elixir structs, using appropiate types. The only exception is that Riffed cannot handle default values that reference other structs; the default value for these fields will always be `:undefined`.


## Generating Servers with `Riffed.Server`

`Riffed.Server` assumes you have a module that has a bunch of handler functions in it. When a thrift RPC is called, your parameters will be converted into Elixir structs and then passed in to one of your handler functions. Let's assume you have the following thrift defined in a file called `pinterest.thrift`:

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
  4: UserState state;
}

service PinterestRegister {
  User register(1: string firstName, 2: string lastName);
  bool isRegistered(1: User user);
  UserState getState(1: string username);
  void setState(1: User user, 2: UserState state);
  void setStatesForUser(1: map<i64, UserState> stateMap);
}
```

You can set it up like this:

```elixir
defmodule Server do
  use Riffed.Server,
  service: :pinterest_thrift,
  structs: Data,
  functions: [register: &ThriftHandlers.register/3,
              isRegistered: &ThriftHandlers.is_registered/1,
              getState: &ThriftHandlers.get_state/1,
              setState: &ThriftHandlers.set_state/2
              setStatesForUser: &ThriftHandlers.set_states_for_user/1
  ],
  server: {:thrift_socket_server,
           port: 2112,
           framed: true,
           max: 10_000,
           socket_opts: [
                   recv_timeout: 3000,
                   keepalive: true]
          }

  enumerize_struct User, state: UserState
  enumerize_function setUserState(_, UserState)
  enumerize_function getState(_), returns: UserState
end

defmodule ThriftHandlers do

  def register(username, first_name, last_name) do
    # registration logic. Return a new user
    Data.User.new(username: username, firstName: "Stinky", lastName: "Stinkman")
  end

  def is_registered(user=%Data.User{}) do
    true
  end

  def get_state(username) do
    user = Models.User.fetch(username)
    case user.state do
      :active -> Data.UserState.active
      :banned -> Data.UserState.banned
      _ -> Data.UserState.inactive
    end
  end

  def set_state(user=%Data.User{}, state=%Data.UserState{}) do
    ...
  end

end
```

`Riffed.Server` is doing a bunch of work for you. It's investigating your thrift files and figuring out which structs need to be imported by looking at the parameters, exceptions and return values. It then makes a module that imports your structs (`Data` in this case) and builds code for the thrift server that takes an incoming thrift request, converts its parameters into Elixir representations and then calls your handler. It also builds all enumerations defined in your thrift server. Notice how the handlers in ThriftHandlers take structs as arguments and return structs. That's what Riffed gets you.

These handler functions also process the values your code returns and hands them back to thrift.

The above example also shows how to handle Thrift enums.  Due to the way thrift enums are handled by the erlang generator, there's no way to tell where they live in your thrift API, and they need to be pointed out with the `enumerize_struct` and `enumerize_function` macros.

The thrift server is configured in the server block. The first element of the tuple is the module of the server you wish to instantiate. In this case, we're using `thrift_socket_server`. The second element is a Keyword list of configuration options for the server. You cannot set the `:name`, `:handler` or `:service params`. The name and handler are set to the current module. The service is given as the `thrift_module` option.


## Generating a client with `Riffed.Client`

Generating a client is similarly simple. `Riffed.Client` just asks that you point it at the erlang module that was generated by thrift, tell it what the client's configuration and compile. When that's done, it examines the thrift module, figures out what functions the module defines, the types you need, creates structs for them and generates helper functions for calling your thrift RPC calls.

Assuming the same configuration above, the following block will generate a client:

```elixir
defmodule RegisterClient do
  use Riffed.Client,
  structs: Models,
  client_opts: [host: "localhost", port: 2112, framed: true],
  service: :pinterest_thrift,

  enumerize_struct User, state: UserState
  enumerize_function getState(_), returns: UserState
end
```

You start the client by calling start_link:

```elixir
RegisterClient.start_link
```

You can then issue calls against the client:

```elixir
iex> user = RegisterClient.register("Stinky", "Stinkman")
%Models.User{firstName: "Stinky", lastName: "Stinkman")

iex> is_registered = RegisterClient.isRegistered(user)
true

iex> state = RegisterClient.getState(user)
%Models.UserState{ordinal: :active, value: 1}
```

Clients support the same callbacks and enumeration transformations that the server suports, and they're configured identically.

## Sharing Structs
Sometimes, you have common structs that are shared between services. Due to Riffed auto-importing structs based on the server definition, Riffed will duplicate shared structs. This auto-import feature can be disabled by specifying `auto_import_structs: false` when creating a client or server. You can then use Riffed.Struct to build a struct module. The following `SharedStructs` module will import all structs in the `shared_types` module.

```elixir
defmodule SharedStructs do
  use Riffed.Struct, shared_types: :auto
end

defmodule UserService do
  use Riffed.Server, service: :user_thrift,
  auto_import_structs: false,
  structs: SharedStructs
  ...
end

defmodule ProfileService do
  use Riffed.Server, service: :profile_thrift,
  auto_import_structs: false,
  structs: SharedStructs
  ...
end
```

## Advanced Struct Packaging

Often, thrift files will make use of `include` statements to share structs. This can present a namespacing problem if you're running several thrift servers or clients that all make use of a common thrift file. This is because each server or client will import the struct separately and produce incompatible structs. 

This can be mitigated by using shared structs in a common module and controlling how they're imported. To control the destination module, use the `dest_modules` keyword dict:

```elixir
defmodule Models do 
  use Rift.Struct, dest_modules: [common_types: Common, 
	                               server_types: Server,
	                               client_types: Client],
	                common_types: :auto,
	                server_types: :auto,
	                client_types: :auto

  enumerize_struct Common.User, state: Common.UserState
end

defmodule Server do 
  use Rift.Server, service: :server_thrift,
  auto_import_structs: false,
  structs: Models
  ...
end

defmodule Client do
  use Rift.Client, 
  auto_import_structs: false,
  structs: Models
  ...
end
```

The above configuration will produce three different modules, `Models.Common`, `Models.Server` and `Models.Client`. The `Models` module 
is capable of serializing and deserializing all the types defined in the three submodules, and should be used as your `:structs` module in your client and servers. 

As you can see above, enumerations are also placed in their module's namespace.


## Handling Thrift Enumerations

Unfortunately, enumeration support in Erlang thrift code is lossy and because of this Riffed can't tell where the enumerations you worked so tirelessly to define appear in the generated code. Unfortunately, this means that you have to tell Riffed where they are; otherwise, all you'll see are integers. 

Creation of enumerations is done automatically when defining rift structs using the `:auto` keyword, but if you import structs manually, enumerations must be re-defined. 

To do this, Riffed supports a syntax to re-define enumerations, and this syntax is available when you use `Riffed.Server` and `Riffed.Client`.

The following examples assume these RPC calls and enumeration:

```thrift
enum DayOfTheWeek {
  SUNDAY,
  MONDAY,
  TUESDAY,
  WEDNESDAY,
  THURSDAY,
  FRIDAY
}

void setCreatedDay(1: User user, 2: DayOfTheWeek day);
DayOfTheWeek getCreatedDay(1: User user);
```

First off, you'll need to re-define your enumeration. To do that, use the defenum macro inside of your `Riffed.Server` or `Riffed.Client` module:

```elixir
defenum DayOfTheWeek do
  :sunday -> 1
  :monday -> 2
  :tuesday -> 3
  :wednesday -> 4
  :thursday -> 5
  :friday -> 6
  :saturday -> 7
end
```

##### Converting enumerations in structs
Now you'll need to tell Riffed where this enum appears in your other data structures. To do that, use the enumerize_struct macro:

```elixir
enumerize_struct User, sign_up_day: DayOfTheWeek, last_login_day: DayOfTheWeek
```

Now all Users will have their `sign_up_day` and `last_login_day` fields automatically converted to enumerations.

##### Converting enumerations in functions

If the enumeration is the argument or return value of a RPC call, you'll need to identify it there too. Use the `enumerize_function` macro:

```elixir
enumerize_function setCreatedDay(_, DayOfTheWeek)
enumerize_function getCreatedDay(_) returns: DayOfTheWeek
```

The `enumerize_function` macro allows you to mark function arguments and return values with the enumeration you would like to use. Unconverted arguments are signaled by using the `_` character. In the example above, setCreatedDay's second argument will be converted to a DayOfTheWeek enumeration and its first argument will be left alone.

Similarly, the function `getCreatedDay` will have its argument left alone and its return value converted into a DayOfTheWeek enumeration

Complex types are also handled in both arguments and return types:

```elixir
enumerize_function setStatesForUser({:map, {:i64, UserState}})
enumerize_function getUserStates(_) returns: {:list, UserState}
enumerize_function allStates() returns: {:set UserState}
```

##### Using enumerations in code
Enumerations are elixir structs whose modules support converting between the struct and integer representation. This shows how to convert integers to enumerations and vice-versa

```elixir
iex> x = DayOfWeek.monday
%DayOfWeek{ordinal: :monday, value: 2}

iex> x.value
1

iex> x = DayOfWeek.value(4)
%DayOfWeek{ordinal: :thursday, value: 4}

iex> x.ordinal
:thursday
```

Since they're just maps, enumerations support pattern matching.

```elixir
def handle_user(user=%User{sign_up_day: DayOfTheWeek.monday}) do
  # code for users that signed up on monday
end

def handle_user(user=%User{})
  # code for everyone else
end
```

You can also retrieve the ordinals, values, or mappings from an enumeration.

```elixir
iex> DayOfWeek.ordinals
[:sunday, :monday, :tuesday, ...]

iex> DayOfWeek.values
[1, 2, 3, ...]

iex> DayOfWeek.mappings
[sunday: 1, monday: 2, tuesday: 3, ...]
```
